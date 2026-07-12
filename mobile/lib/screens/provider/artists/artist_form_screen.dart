import 'package:flutter/material.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/artist.dart';
import '../../../models/availability.dart';
import '../../../providers/pro_artist_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';
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
  final _formKey = GlobalKey<FormState>();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Échec de l’envoi'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Employé enregistré'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(artistProvider.error ?? 'Erreur lors de la sauvegarde'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet employé ?'),
        content: const Text(
          'Êtes-vous sûr de vouloir supprimer cet employé ? Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final artistProvider =
        Provider.of<ProArtistProvider>(context, listen: false);
    final success = await artistProvider.deleteArtist(widget.artistId!);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Employé supprimé'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(artistProvider.error ?? 'Erreur lors de la suppression'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
            widget.artistId != null ? 'Modifier l\'employé' : 'Nouvel employé'),
      ),
      body: Consumer<ProArtistProvider>(
        builder: (context, artistProvider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Form(
              key: _formKey,
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
                                      size: 36, color: AppColors.textSecondary)
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
                                        size: 20, fast: true, onDark: true),
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
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Le nom est requis';
                      }
                      return null;
                    },
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
                    subtitle: const Text(
                        'Désactiver pour des horaires personnalisés'),
                    value: !_customHours,
                    onChanged: (followsSalon) =>
                        setState(() => _customHours = !followsSalon),
                  ),
                  if (_customHours) ...[
                    WeeklyHoursEditor(
                      hours: _workingHours,
                      onChanged: (hours) =>
                          setState(() => _workingHours = hours),
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
                      onPressed:
                          artistProvider.isLoading ? null : _handleDelete,
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.error),
                      child: const Text('Supprimer l\'employé'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
