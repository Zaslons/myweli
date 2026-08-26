import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/forms/field_errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../models/provider.dart' as models;
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_salon_profile_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/commune_picker_sheet.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';
import '../../../widgets/common/timed_cached_image.dart';
import '../../../widgets/provider/image_picker_sheet.dart';
import '../../../widgets/provider/mock_image_picker_sheet.dart';

/// The listing categories a salon can choose (the canonical taxonomy —
/// mirrors the server's PATCH validation, pro-salon-lifecycle L1/L2).
const salonCategories = [
  ('salon', 'Salon de coiffure'),
  ('barber', 'Barbier'),
  ('spa', 'Spa'),
  ('nails', 'Onglerie'),
  ('massage', 'Massage & bien-être'),
];

/// « Profil du salon » (docs/design/pro-salon-lifecycle.md L2): the app's
/// editor for the public listing — the fields a client sees, the category,
/// and the MAP PIN (tap to place, « Utiliser ma position ») that puts the
/// salon on the discovery map and gates go-live.
class ProSalonProfileScreen extends StatefulWidget {
  const ProSalonProfileScreen({super.key});

  @override
  State<ProSalonProfileScreen> createState() => _ProSalonProfileScreenState();
}

class _ProSalonProfileScreenState extends State<ProSalonProfileScreen> {
  // Abidjan-ish default center (the app map's constant).
  static const LatLng _defaultCenter = LatLng(5.336, -4.026);

  final _name = TextEditingController();

  // A7/§14 — the salon's contact numbers reach real clients, and nothing
  // checked them.
  //
  // **E.164, not local digits.** The review caught this as a LOCKOUT: these
  // controllers are prefilled from the stored value, which openapi.yaml:1334-5
  // specifies as E.164 (`+225 …`). A 10-digit rule can never match it, so the
  // salon could not save its profile again — the rule would have failed on data
  // the app itself had just loaded.
  late final _errors = FieldErrors({
    'name': Validators.requiredField('le nom du salon'),
    'phone': Validators.phoneNumber,
    'whatsapp': _optionalPhone,
  });
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _whatsappFocus = FocusNode();
  late final _focusNodes = {
    'name': _nameFocus,
    'phone': _phoneFocus,
    'whatsapp': _whatsappFocus,
  };

  /// WhatsApp is optional — blank passes, anything typed must be a real number.
  static String? _optionalPhone(String value) =>
      value.trim().isEmpty ? null : Validators.phoneNumber(value);
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();

  /// Multi-pays MP2: the commune is a LOCALITY pick (areaId) — the server
  /// derives city/timezone/currency from it (T57). The display name shows
  /// in the picker row; legacy free-text communes keep their name until the
  /// first pick self-heals them.
  String? _areaId;
  String _communeName = '';
  String _category = 'salon';
  LatLng? _pin;
  bool _filled = false;
  bool _locating = false;

  String? _providerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = context.read<ProAuthProvider>().activeSalonId;
      if (id != null && id.isNotEmpty) {
        _providerId = id;
        context.read<ProSalonProfileProvider>().load(id);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _address, _phone, _whatsapp]) {
      c.dispose();
    }
    for (final f in [_nameFocus, _phoneFocus, _whatsappFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  void _fillOnce(models.Provider p) {
    if (_filled) return;
    _filled = true;
    _name.text = p.name;
    _description.text = p.description;
    _address.text = p.address;
    _areaId = p.areaId;
    _communeName = p.commune ?? '';
    _phone.text = p.phoneNumber;
    _whatsapp.text = p.whatsapp ?? '';
    if (salonCategories.any((c) => c.$1 == p.category)) {
      _category = p.category;
    }
    if (p.latitude != null && p.longitude != null) {
      _pin = LatLng(p.latitude!, p.longitude!);
    }
  }

  Future<void> _useMyPosition() async {
    // Captured BEFORE the geolocator awaits — the correct idiom, and the one
    // the deleted `_toast` wrapper was hiding behind a `mounted` guard.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        AppSnackBar.showOn(
          messenger,
          'Localisation désactivée',
          kind: SnackKind.error,
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        AppSnackBar.showOn(
          messenger,
          'Autorisez la localisation pour vous placer',
          kind: SnackKind.error,
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _pin = LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      AppSnackBar.showOn(
        messenger,
        'Position indisponible',
        kind: SnackKind.error,
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickCommune() async {
    final choice = await showCommunePicker(
      context,
      selected: _communeName.isEmpty ? null : _communeName,
      allowAll: false, // a salon belongs to exactly one commune
    );
    if (choice == null || choice.areaId == null || !mounted) return;
    setState(() {
      _areaId = choice.areaId;
      _communeName = choice.commune ?? '';
    });
  }

  Future<void> _save() async {
    // A7/§14 rule 3: « Le nom est requis » was a SNACKBAR — a field-level fault
    // in a bar that vanishes on a timer, without saying which field or
    // scrolling to it. The phone and WhatsApp numbers had no rule at all.
    final valid = _errors.validate({
      'name': _name.text,
      'phone': _phone.text,
      'whatsapp': _whatsapp.text,
    });
    setState(() {});
    if (!valid) {
      focusFirstError(_errors, _focusNodes);
      return;
    }
    final profile = context.read<ProSalonProfileProvider>();
    final ok = await profile.save(_providerId!, {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'address': _address.text.trim(),
      // The locality pick — the server derives commune/city/timezone/
      // currency from it; a legacy free-text name rides along until the
      // first pick (the server self-heals matching names).
      if (_areaId != null) 'areaId': _areaId,
      if (_areaId == null) 'commune': _communeName.trim(),
      'phoneNumber': _phone.text.trim(),
      'whatsapp': _whatsapp.text.trim(),
      'category': _category,
      if (_pin != null) 'latitude': _pin!.latitude,
      if (_pin != null) 'longitude': _pin!.longitude,
    });
    if (!mounted) return;
    if (ok) {
      AppSnackBar.show(context, 'Profil enregistré', kind: SnackKind.success);
      Navigator.of(context).pop();
    } else {
      AppSnackBar.show(
        context,
        profile.error ?? 'Enregistrement impossible',
        kind: SnackKind.error,
      );
    }
  }

  Future<void> _pickLogo(ProSalonProfileProvider profile) async {
    // The picker MUST branch on the backend flag — its absence was the
    // avatar slice's defect B (consumer-avatar-upload.md).
    final source = AppConfig.useApiBackend
        ? await showImagePicker(context)
        : await showMockImagePicker(context);
    if (source == null || _providerId == null) return;
    await profile.uploadLogo(_providerId!, source);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profil du salon')),
      body: Consumer<ProSalonProfileProvider>(
        builder: (context, profile, _) {
          if (_providerId == null) {
            return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Profil indisponible',
              description: 'Reconnectez-vous et réessayez.',
            );
          }
          if (profile.isLoading && profile.provider == null) {
            return const Center(child: LoadingIndicator());
          }
          final p = profile.provider;
          if (p == null) {
            return EmptyState(
              icon: Icons.wifi_off,
              title: 'Chargement impossible',
              description: 'Vérifiez votre connexion et réessayez.',
              actionText: 'Réessayer',
              onAction: () => profile.load(_providerId!),
            );
          }
          _fillOnce(p);

          return ListView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            children: [
              // The salon's brand mark — settable at last (salon-logo.md).
              // Uploads and saves IMMEDIATELY (the avatar pattern): the
              // PATCH carries only `logoUrl`, so it cannot fight the staged
              // form below.
              _LogoField(
                logoUrl: p.logoUrl,
                isUploading: profile.isUploadingLogo,
                error: profile.logoError,
                onPick: () => _pickLogo(profile),
                onRemove: p.logoUrl == null
                    ? null
                    : () => profile.removeLogo(_providerId!),
              ),
              const SizedBox(height: AppTheme.spacingM),
              AppTextField(
                label: 'Nom du salon',
                controller: _name,
                focusNode: _nameFocus,
                errorText: _errors['name'],
                onChanged: (v) => setState(() => _errors.revalidate('name', v)),
              ),
              const SizedBox(height: AppTheme.spacingS),
              AppTextField(
                label: 'Description',
                controller: _description,
                maxLines: 3,
              ),
              const SizedBox(height: AppTheme.spacingS),
              AppTextField(label: 'Adresse', controller: _address),
              const SizedBox(height: AppTheme.spacingS),
              InkWell(
                onTap: _pickCommune,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Commune'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _communeName.isEmpty
                              ? 'Choisir une commune'
                              : _communeName,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: _communeName.isEmpty
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.expand_more,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingS),
              AppTextField(
                label: 'Téléphone',
                controller: _phone,
                focusNode: _phoneFocus,
                errorText: _errors['phone'],
                onChanged: (v) =>
                    setState(() => _errors.revalidate('phone', v)),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppTheme.spacingS),
              AppTextField(
                label: 'WhatsApp (optionnel)',
                controller: _whatsapp,
                focusNode: _whatsappFocus,
                errorText: _errors['whatsapp'],
                onChanged: (v) =>
                    setState(() => _errors.revalidate('whatsapp', v)),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppTheme.spacingM),
              Text(
                'CATÉGORIE',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: AppTheme.spacingS),
              DropdownButtonFormField<String>(
                // A11 C8 — see pro_register_screen.dart: without this the
                // button takes its WIDEST item's intrinsic width and overflows
                // the field at 200% text.
                isExpanded: true,
                // A12: `itemHeight` defaults to `kMinInteractiveDimension`
                // (48), a FIXED height around text — so at 200% « Salon de
                // beauté » wraps to two lines, needs 96dp and is clipped to 48
                // the moment the menu opens. A11 C8 fixed the BUTTON with
                // `isExpanded`; the items it lists were still frozen one level
                // down, and nothing could see it until `expectNoVerticalClip`.
                // `null` lets each item take its intrinsic height (§13.3).
                itemHeight: null,
                initialValue: _category,
                items: [
                  for (final c in salonCategories)
                    DropdownMenuItem(value: c.$1, child: Text(c.$2)),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
                // Borders come from the theme (borderStrong + the focus ring).
                // It used to set only `border:` — which InputDecorator uses as a
                // FALLBACK, so the theme's `enabledBorder` won at rest anyway and
                // the custom radius silently applied to nothing. Inheriting makes
                // it match every other field on this screen.
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: AppColors.secondary,
                ),
              ),
              const SizedBox(height: AppTheme.spacingM),
              Text(
                'POSITION SUR LA CARTE',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: AppTheme.spacingS),
              _LocationField(
                pin: _pin,
                defaultCenter: _defaultCenter,
                onPick: (latLng) => setState(() => _pin = latLng),
              ),
              const SizedBox(height: AppTheme.spacingS),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _locating ? null : _useMyPosition,
                    icon: const Icon(Icons.my_location, size: AppTheme.iconS),
                    label: Text(
                      _locating ? 'Recherche…' : 'Utiliser ma position',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.borderStrong),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSM),
                  Expanded(
                    child: Text(
                      _pin == null
                          ? 'Touchez la carte pour placer votre salon.'
                          : 'Touchez la carte pour ajuster.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingL),
              AppButton(
                text: 'Enregistrer',
                isLoading: profile.isSaving,
                onPressed: profile.isSaving ? null : _save,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The tap-to-place pin map (the app map's CARTO light basemap).
class _LocationField extends StatelessWidget {
  final LatLng? pin;
  final LatLng defaultCenter;
  final ValueChanged<LatLng> onPick;

  const _LocationField({
    required this.pin,
    required this.defaultCenter,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: SizedBox(
        height: 240,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: pin ?? defaultCenter,
            initialZoom: pin == null ? 11.5 : 15,
            onTap: (_, latLng) => onPick(latLng),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.sadreddine.myweli',
              retinaMode: true,
            ),
            if (pin != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: pin!,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 2),
                        boxShadow: AppTheme.elevation2,
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: AppColors.primary,
                        size: AppTheme.iconM,
                      ),
                    ),
                  ),
                ],
              ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
                TextSourceAttribution('© CARTO'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The circular logo editor at the top of the profile form.
///
/// 88 dp (radius 44) — comfortably over the 48 dp floor — showing the logo,
/// a store glyph when unset, a progress ring while uploading, and a camera
/// badge naming the action. Errors render inline under the field, never as a
/// toast (SYSTEM.md forms rule).
class _LogoField extends StatelessWidget {
  final String? logoUrl;
  final bool isUploading;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  const _LogoField({
    required this.logoUrl,
    required this.isUploading,
    required this.error,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final label = logoUrl == null ? 'Ajouter un logo' : 'Changer le logo';
    return Column(
      children: [
        Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: isUploading ? null : onPick,
            customBorder: const CircleBorder(),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: AppColors.secondary,
                  child: logoUrl == null
                      ? const Icon(
                          Icons.store_outlined,
                          size: AppTheme.iconL,
                          color: AppColors.textTertiary,
                        )
                      : ClipOval(
                          child: TimedCachedImage(
                            imageUrl: logoUrl!,
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
                if (isUploading)
                  const SizedBox(
                    width: 88,
                    height: 88,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.primary,
                    child: Icon(
                      Icons.photo_camera_outlined,
                      size: AppTheme.iconXS,
                      color: AppColors.surface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacingXS),
        Text(label, style: AppTextStyles.bodySmall),
        if (onRemove != null)
          TextButton(
            onPressed: isUploading ? null : onRemove,
            child: const Text('Supprimer le logo'),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingXS),
            child: Text(
              error!,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}
