import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/artist.dart';
import '../../models/review.dart';
import '../../providers/auth_provider.dart';
import '../../providers/provider_provider.dart';
import '../common/app_button.dart';
import '../common/app_text_field.dart';

class SubmitReviewSheet extends StatefulWidget {
  final String providerId;
  final VoidCallback? onSubmitted;

  const SubmitReviewSheet({
    super.key,
    required this.providerId,
    this.onSubmitted,
  });

  @override
  State<SubmitReviewSheet> createState() => _SubmitReviewSheetState();
}

class _SubmitReviewSheetState extends State<SubmitReviewSheet> {
  int _selectedRating = 0;
  String? _selectedArtistId;
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedRating < 1) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user == null) return;

    final providerProvider =
        Provider.of<ProviderProvider>(context, listen: false);
    final artists =
        providerProvider.selectedProvider?.artists ?? const <Artist>[];
    String? artistName;
    if (_selectedArtistId != null) {
      for (final a in artists) {
        if (a.id == _selectedArtistId) {
          artistName = a.name;
          break;
        }
      }
    }

    final review = Review(
      id: const Uuid().v4(),
      providerId: widget.providerId,
      userId: user.id,
      userName: user.name ?? 'Utilisateur',
      rating: _selectedRating,
      text: _textController.text.trim(),
      // Submission is gated on a completed booking, so it's a verified review.
      verified: true,
      artistId: _selectedArtistId,
      artistName: artistName,
      createdAt: DateTime.now(),
    );

    providerProvider.addReviewLocally(review);
    widget.onSubmitted?.call();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Merci pour votre avis'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _comingSoonPhotos() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("L'ajout de photos arrive bientôt"),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final artists =
        context.watch<ProviderProvider>().selectedProvider?.artists ??
            const <Artist>[];
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Donner mon avis',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starIndex = index + 1;
              return IconButton(
                onPressed: () {
                  setState(() => _selectedRating = starIndex);
                },
                icon: Icon(
                  starIndex <= _selectedRating ? Icons.star : Icons.star_border,
                  size: 40,
                  color: Colors.amber,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            }),
          ),
          if (artists.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingM),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Avec quel professionnel ?',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
            Wrap(
              spacing: AppTheme.spacingS,
              runSpacing: AppTheme.spacingS,
              children: [
                for (final a in artists)
                  ChoiceChip(
                    label: Text(a.name),
                    selected: _selectedArtistId == a.id,
                    onSelected: (_) => setState(() => _selectedArtistId = a.id),
                  ),
                ChoiceChip(
                  label: const Text('Sans préférence'),
                  selected: _selectedArtistId == null,
                  onSelected: (_) => setState(() => _selectedArtistId = null),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppTheme.spacingM),
          AppTextField(
            hint: 'Votre avis (optionnel)',
            controller: _textController,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: AppTheme.spacingM),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _comingSoonPhotos,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Ajouter des photos'),
            ),
          ),
          const SizedBox(height: AppTheme.spacingL),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: AppButton(
                  text: 'Publier',
                  onPressed: _selectedRating >= 1 ? _submit : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
