import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/artist.dart';
import '../../models/review.dart';
import '../../providers/auth_provider.dart';
import '../../providers/provider_provider.dart';
import '../common/app_button.dart';
import '../common/app_text_field.dart';
import '../common/timed_cached_image.dart';
import '../provider/image_picker_sheet.dart';
import '../provider/mock_image_picker_sheet.dart';

const _maxReviewPhotos = 3;

class SubmitReviewSheet extends StatefulWidget {
  final String providerId;

  /// The completed appointment being reviewed (one review per visit).
  final String appointmentId;
  final VoidCallback? onSubmitted;

  const SubmitReviewSheet({
    super.key,
    required this.providerId,
    required this.appointmentId,
    this.onSubmitted,
  });

  @override
  State<SubmitReviewSheet> createState() => _SubmitReviewSheetState();
}

class _SubmitReviewSheetState extends State<SubmitReviewSheet> {
  int _selectedRating = 0;
  String? _selectedArtistId;
  final _textController = TextEditingController();
  final List<String> _photoUrls = [];
  bool _uploadingPhoto = false;
  bool _submitting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_photoUrls.length >= _maxReviewPhotos) return;
    final String? source;
    if (AppConfig.useApiBackend) {
      source = await showImagePicker(context);
    } else {
      source = await showMockImagePicker(context);
    }
    if (source == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    final providerProvider =
        Provider.of<ProviderProvider>(context, listen: false);
    final url = await providerProvider.uploadReviewPhoto(source);
    if (!mounted) return;
    setState(() {
      _uploadingPhoto = false;
      if (url != null) _photoUrls.add(url);
    });
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Échec de l’envoi de la photo'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _removePhoto(int index) => setState(() => _photoUrls.removeAt(index));

  Future<void> _submit() async {
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
      appointmentId: widget.appointmentId,
      providerId: widget.providerId,
      userId: user.id,
      userName: user.name ?? 'Utilisateur',
      rating: _selectedRating,
      text: _textController.text.trim(),
      // Submission is gated on a completed booking, so it's a verified review.
      verified: true,
      artistId: _selectedArtistId,
      artistName: artistName,
      photoUrls: List<String>.from(_photoUrls),
      createdAt: DateTime.now(),
    );

    setState(() => _submitting = true);
    final ok = await providerProvider.submitReview(review);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      widget.onSubmitted?.call();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Merci pour votre avis'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(providerProvider.error ?? 'Erreur lors de la publication'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final artists =
        context.watch<ProviderProvider>().selectedProvider?.artists ??
            const <Artist>[];
    final canSubmit = _selectedRating >= 1 && !_submitting && !_uploadingPhoto;
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
                  color: AppColors.starRating,
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
            child: Text(
              'Photos (avant / après)',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                for (var i = 0; i < _photoUrls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _PhotoThumb(
                      url: _photoUrls[i],
                      onRemove: () => _removePhoto(i),
                    ),
                  ),
                if (_uploadingPhoto)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                if (_photoUrls.length < _maxReviewPhotos && !_uploadingPhoto)
                  GestureDetector(
                    onTap: _addPhoto,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.camera_alt_outlined,
                              size: 18, color: AppColors.textSecondary),
                          Text(
                            '${_photoUrls.length}/$_maxReviewPhotos',
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingL),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: AppButton(
                  text: 'Publier',
                  isLoading: _submitting,
                  onPressed: canSubmit ? _submit : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;

  const _PhotoThumb({required this.url, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            child: TimedCachedImage(imageUrl: url, fit: BoxFit.cover),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
