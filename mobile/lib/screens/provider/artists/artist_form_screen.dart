import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../models/artist.dart';
import '../../../providers/pro_artist_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';

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

  String _resolvedProviderId(BuildContext context) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    return authProvider.provider?.providerId ?? authProvider.provider?.id ?? '';
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
