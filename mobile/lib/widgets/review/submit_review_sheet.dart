import 'package:flutter/material.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/app_clock.dart';
import '../../models/artist.dart';
import '../../models/review.dart';
import '../../providers/auth_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../common/app_button.dart';
import '../common/app_text_field.dart';
import '../common/inline_feedback.dart';
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

  /// A6: a failure raised while this sheet is open cannot be a snackbar — the
  /// modal barrier prunes it from the semantics tree and paints it under the
  /// scrim. It belongs here, inside the sheet that owns the failure.
  String? _error;
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
    final providerProvider = Provider.of<ProviderProvider>(
      context,
      listen: false,
    );
    final url = await providerProvider.uploadReviewPhoto(source);
    if (!mounted) return;
    setState(() {
      _uploadingPhoto = false;
      if (url != null) _photoUrls.add(url);
    });
    if (url == null) {
      setState(() => _error = 'Échec de l’envoi de la photo');
    }
  }

  void _removePhoto(int index) => setState(() => _photoUrls.removeAt(index));

  Future<void> _submit() async {
    if (_selectedRating < 1) {
      // The stars are a SELECTION — no field to sit under — so the fault lands
      // form-level (§14's three-slot boundary). It used to be a dead « Publier »
      // and a silent `return`: two ways of saying nothing.
      setState(() => _error = 'Choisissez une note de 1 à 5 étoiles.');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user == null) return;

    final providerProvider = Provider.of<ProviderProvider>(
      context,
      listen: false,
    );
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
      createdAt: AppClock.now(),
    );

    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await providerProvider.submitReview(review);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      widget.onSubmitted?.call();
      // The snackbar below is a live region — announcing here as well
      // double-spoke it on iOS and cleared TalkBack's queue on Android.
      Navigator.pop(context);
      AppSnackBar.show(
        context,
        'Merci pour votre avis',
        kind: SnackKind.success,
      );
    } else {
      setState(
        () =>
            _error = providerProvider.error ?? 'Erreur lors de la publication',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final artists =
        context.watch<ProviderProvider>().selectedProvider?.artists ??
        const <Artist>[];
    // §14 rule 5: NOT gated on the rating. `_uploadingPhoto` and `_submitting`
    // are work in progress, which is the rule's one allowed reason to disable.
    final canSubmit = !_submitting && !_uploadingPhoto;
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
              return Semantics(
                selected: starIndex <= _selectedRating,
                child: IconButton(
                  tooltip: 'Noter $starIndex étoile${starIndex > 1 ? 's' : ''}',
                  onPressed: () {
                    setState(() => _selectedRating = starIndex);
                  },
                  icon: Icon(
                    starIndex <= _selectedRating
                        ? Icons.star
                        : Icons.star_border,
                    size: AppTheme.iconL,
                    color: AppColors.starRating,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingXS,
                  ),
                ),
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
                    padding: const EdgeInsets.only(right: AppTheme.spacingS),
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
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusMedium,
                      ),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: BrandLoader(size: AppTheme.iconS, fast: true),
                      ),
                    ),
                  ),
                if (_photoUrls.length < _maxReviewPhotos && !_uploadingPhoto)
                  Semantics(
                    button: true,
                    label: 'Ajouter une photo',
                    child: GestureDetector(
                      onTap: _addPhoto,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMedium,
                          ),
                          border: Border.all(color: AppColors.borderStrong),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.camera_alt_outlined,
                              size: AppTheme.iconS,
                              color: AppColors.textSecondary,
                            ),
                            Text(
                              '${_photoUrls.length}/$_maxReviewPhotos',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          InlineFeedback(_error),
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
            child: Semantics(
              button: true,
              label: 'Supprimer la photo',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: SizedBox(
                  // §13.2 48 hit area; Align keeps the badge at the (2,2) corner.
                  width: 48,
                  height: 48,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      padding: const EdgeInsets.all(AppTheme.spacingXS),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: AppTheme.iconXS,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
