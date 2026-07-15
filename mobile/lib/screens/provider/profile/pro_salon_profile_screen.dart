import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/provider.dart' as models;
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_salon_profile_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/commune_picker_sheet.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';

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
    for (final c in [
      _name,
      _description,
      _address,
      _phone,
      _whatsapp,
    ]) {
      c.dispose();
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
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('Localisation désactivée');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _toast('Autorisez la localisation pour vous placer');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _pin = LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      _toast('Position indisponible');
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

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      return _toast('Le nom est requis', error: true);
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
      _toast('Profil enregistré');
      Navigator.of(context).pop();
    } else {
      _toast(profile.error ?? 'Enregistrement impossible', error: true);
    }
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
              AppTextField(label: 'Nom du salon', controller: _name),
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
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppTheme.spacingS),
              AppTextField(
                label: 'WhatsApp (optionnel)',
                controller: _whatsapp,
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
