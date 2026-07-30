import 'package:flutter/material.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';

import '../../../core/forms/field_errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../models/artist.dart';
import '../../../models/availability.dart';
import '../../../providers/pro_artist_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../../../widgets/common/timed_cached_image.dart';
import '../../../widgets/provider/mock_image_picker_sheet.dart';
import '../../../widgets/provider/weekly_hours_editor.dart';

class ArtistFormScreen extends StatefulWidget {
  final String? artistId;

  const ArtistFormScreen({super.key, this.artistId});

  @override
  State<ArtistFormScreen> createState() => _ArtistFormScreenState();
}

class _ArtistFormScreenState extends State<ArtistFormScreen> {
  // A7/§14 — the form's faults, in the form's reading order.
  late final _errors = FieldErrors({'name': Validators.name});
  final _nameFocus = FocusNode();
  final _nameController = TextEditingController();
  final _specializationController = TextEditingController();
  bool _prefillDone = false;
  bool _customHours = false;
  Map<int, List<TimeSlot>> _workingHours = {};
  String? _avatarUrl;

  String _resolvedProviderId(BuildContext context) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    return authProvider.activeSalonId ?? '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.artistId != null && !_prefillDone) {
      final artistProvider =
          Provider.of<ProArtistProvider>(context, listen: false);
      Artist? artist;
      for (final a in artistProvider.artists) {
        if (a.id == widget.artistId) {
          artist = a;
          break;
        }
      }
      if (artist != null) {
        _nameController.text = artist.name;
        _specializationController.text = artist.specialization ?? '';
        _avatarUrl = artist.imageUrl;
        if (artist.workingHours.isNotEmpty) {
          _customHours = true;
          _workingHours = {
            for (final e in artist.workingHours.entries)
              e.key: List<TimeSlot>.from(e.value)
          };
        }
      }
      _prefillDone = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _specializationController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(ProArtistProvider provider) async {
    final source = await showMockImagePicker(context);
    if (source == null || !mounted) return;
    final url = await provider.uploadAvatar(source);
    if (!mounted) return;
    if (url != null) {
      setState(() => _avatarUrl = url);
    } else {
      AppSnackBar.show(context, provider.error ?? 'Échec de l’envoi',
          kind: SnackKind.error);
    }
  }

  Future<void> _handleSave() async {
    // §14 rule 5: submit is never disabled for validity — pressing it answers.
    final ok = _errors.validate({'name': _nameController.text});
    setState(() {});
    if (!ok) {
      focusFirstError(_errors, {'name': _nameFocus});
      return;
    }

    final artistProvider =
        Provider.of<ProArtistProvider>(context, listen: false);
    final providerId = _resolvedProviderId(context);

    final data = {
      'name': _nameController.text.trim(),
      'specialization': _specializationController.text.trim().isNotEmpty
          ? _specializationController.text.trim()
          : null,
      'imageUrl': _avatarUrl,
      'workingHours': _customHours ? _workingHours : <int, List<TimeSlot>>{},
    };

    final success = widget.artistId != null
        ? await artistProvider.updateArtist(widget.artistId!, data)
        : await artistProvider.createArtist(providerId, data);

    if (!mounted) return;

    if (success) {
      AppSnackBar.show(context, 'Employé enregistré', kind: SnackKind.success);
      Navigator.pop(context);
    } else {
      AppSnackBar.show(
          context, artistProvider.error ?? 'Erreur lors de la sauvegarde',
          kind: SnackKind.error);
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Supprimer cet employé ?',
      message: 'Sa fiche et ses créneaux disparaîtront. Cette action est '
          'irréversible.',
      confirmLabel: 'Supprimer l’employé',
    );

    if (!confirmed || !mounted) return;

    final artistProvider =
        Provider.of<ProArtistProvider>(context, listen: false);
    final success = await artistProvider.deleteArtist(widget.artistId!);

    if (!mounted) return;

    if (success) {
      AppSnackBar.show(context, 'Employé supprimé', kind: SnackKind.success);
      Navigator.pop(context);
    } else {
      AppSnackBar.show(
          context, artistProvider.error ?? 'Erreur lors de la suppression',
          kind: SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
            widget.artistId != null ? 'Modifier l’employé' : 'Nouvel employé'),
      ),
      body: Consumer<ProArtistProvider>(
        builder: (context, artistProvider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: AppColors.surface,
                            child: _avatarUrl == null
                                ? const Icon(Icons.person_outline,
                                    size: AppTheme.iconL,
                                    color: AppColors.textSecondary)
                                : ClipOval(
                                    child: TimedCachedImage(
                                      imageUrl: _avatarUrl!,
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                          ),
                          if (artistProvider.isUploadingAvatar)
                            const Positioned.fill(
                              child: CircleAvatar(
                                radius: 40,
                                backgroundColor: Colors.black45,
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: BrandLoader(
                                      size: AppTheme.iconS,
                                      fast: true,
                                      onDark: true),
                                ),
                              ),
                            ),
                        ],
                      ),
                      TextButton(
                        onPressed: artistProvider.isUploadingAvatar
                            ? null
                            : () => _pickAvatar(artistProvider),
                        child: Text(_avatarUrl == null
                            ? 'Ajouter une photo'
                            : 'Changer la photo'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.spacingS),
                AppTextField(
                  label: 'Nom',
                  hint: 'Ex: Kouassi Jean',
                  controller: _nameController,
                  focusNode: _nameFocus,
                  errorText: _errors['name'],
                  onChanged: (v) =>
                      setState(() => _errors.revalidate('name', v)),
                ),
                const SizedBox(height: AppTheme.spacingM),
                AppTextField(
                  label: 'Spécialisation',
                  hint: 'Ex: Barbier, Coiffeur, Esthéticienne',
                  controller: _specializationController,
                ),
                const SizedBox(height: AppTheme.spacingS),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Suit les horaires du salon'),
                  subtitle:
                      const Text('Désactiver pour des horaires personnalisés'),
                  value: !_customHours,
                  onChanged: (followsSalon) =>
                      setState(() => _customHours = !followsSalon),
                ),
                if (_customHours) ...[
                  WeeklyHoursEditor(
                    hours: _workingHours,
                    onChanged: (hours) => setState(() => _workingHours = hours),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  Text(
                    'Les clients ne verront que les créneaux où ce membre '
                    'travaille (dans la limite des horaires du salon).',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
                const SizedBox(height: AppTheme.spacingL),
                AppButton(
                  text: 'Enregistrer',
                  onPressed: artistProvider.isLoading ? null : _handleSave,
                  isLoading: artistProvider.isLoading,
                ),
                if (widget.artistId != null) ...[
                  const SizedBox(height: AppTheme.spacingM),
                  TextButton(
                    onPressed: artistProvider.isLoading ? null : _handleDelete,
                    style:
                        TextButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('Supprimer l’employé'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
