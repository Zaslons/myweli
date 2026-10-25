import 'package:flutter/material.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/review_card.dart';
import '../../../models/review.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_reviews_provider.dart';
import '../../../widgets/common/app_async_view.dart';
import '../../../widgets/common/app_skeleton.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../../../widgets/common/empty_state.dart';

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  String _resolvedProviderId(BuildContext context) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    return authProvider.activeSalonId ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.provider != null) {
        final reviewsProvider = Provider.of<ProReviewsProvider>(
          context,
          listen: false,
        );
        reviewsProvider.loadReviews(_resolvedProviderId(context));
      }
    });
  }

  /// « Signaler » (B6.6 — App Store 1.2, decision 20): the client's dialog
  /// and words; the review goes to the moderators' queue, marked « Signalé
  /// par le salon ». Docs: docs/design/backend-integrity-batch6.md §2.6.
  Future<void> _report(String reviewId) async {
    final reason = await showInputDialog(
      context,
      title: 'Signaler cet avis ?',
      confirmLabel: 'Signaler',
      field: const ConfirmField(
        hint: 'Raison (optionnel)',
        isRequired: false,
        maxLength: 500,
      ),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await context.read<ProReviewsProvider>().reportReview(
      reviewId,
      reason: reason,
    );
    AppSnackBar.outcomeOn(
      messenger,
      ok: ok,
      success: 'Merci. Notre équipe va examiner cet avis.',
      error: 'Le signalement a échoué. Réessayez.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Avis')),
      body: Consumer2<ProAuthProvider, ProReviewsProvider>(
        builder: (context, authProvider, reviewsProvider, _) {
          if (!authProvider.isAuthenticated) {
            return const Center(child: Text('Veuillez vous connecter'));
          }

          Future<void> reload() async {
            if (authProvider.provider != null) {
              await reviewsProvider.loadReviews(_resolvedProviderId(context));
            }
          }

          // A failed list said « Aucun avis » (B9.8).
          return AppAsyncView<List<Review>>(
            isLoading: reviewsProvider.isLoading,
            error: reviewsProvider.loadError,
            data: reviewsProvider.reviews,
            isEmpty: (d) => d.isEmpty,
            loading: const SkeletonCardList(lead: SkeletonLead.avatar),
            empty: const EmptyState(
              icon: Icons.star_outline,
              title: 'Aucun avis',
              description: 'Les avis de vos clients apparaîtront ici',
            ),
            onRetry: reload,
            onRefresh: reload,
            builder: (context, reviews) =>
                _content(authProvider, reviewsProvider, reviews, reload),
          );
        },
      ),
    );
  }

  Widget _content(
    ProAuthProvider authProvider,
    ProReviewsProvider reviewsProvider,
    List<Review> reviews,
    Future<void> Function() reload,
  ) {
    // The whole salon's card when the server sends it — the first page
    // holds 50, and averaging it was wrong past 50
    // (docs/design/salon-reviews-summary.md).
    final card = reviewCard(reviews, reviewsProvider.summary);
    return BrandRefresh(
      onRefresh: reload,
      child: Column(
        children: [
          // Summary Card
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            margin: const EdgeInsets.all(AppTheme.spacingM),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(AppTheme.radiusXL),
              boxShadow: AppTheme.elevation1,
            ),
            child: Row(
              children: [
                Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.star,
                          size: AppTheme.iconL,
                          color: AppColors.starRating,
                        ),
                        const SizedBox(width: AppTheme.spacingS),
                        Text(
                          Formatters.formatRating(card.average),
                          style: AppTextStyles.headlineMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingXS),
                    Text(
                      '${card.count} avis',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppTheme.spacingM),
                // Rating distribution. `Expanded`, not a `Spacer` before a
                // hugging Column: the bars inside are flexed now, so this
                // side needs a definite width to divide. With a `Spacer`
                // the inner rows are `MainAxisSize.min` against unbounded
                // width and an `Expanded` bar has nothing to expand into.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(5, (index) {
                      final rating = 5 - index;
                      final count = card.countFor(rating);
                      final percentage = card.count == 0
                          ? 0.0
                          : count / card.count;
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppTheme.spacingXS,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '$rating',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: AppTheme.spacingXS),
                            const Icon(
                              Icons.star,
                              size: AppTheme.iconXS,
                              color: AppColors.starRating,
                            ),
                            const SizedBox(width: AppTheme.spacingS),
                            // A11 C5. `SizedBox(width: 100)` was the only
                            // hard-coded width among the app's four
                            // `LinearProgressIndicator`s — the other three
                            // are `Expanded` or full width — and the text on
                            // both sides of it grows with the scale while it
                            // did not, which is the 4.3dp overflow at 360×2×.
                            // `reports_analytics_screen.dart:233` is the
                            // house answer to this exact shape: the bar
                            // flexes, the numbers keep their intrinsic width.
                            // The `ClipRRect` + `minHeight` come with it —
                            // this bar alone shipped 4dp tall with square
                            // ends while its three siblings did not.
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSmall,
                                ),
                                child: LinearProgressIndicator(
                                  value: percentage,
                                  minHeight: AppTheme.spacingS,
                                  backgroundColor: AppColors.surface,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        AppColors.gold,
                                      ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppTheme.spacingS),
                            Text(
                              '$count',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          // Reviews List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingM,
              ),
              itemCount: reviews.length,
              itemBuilder: (context, index) {
                final review = reviews[index];
                return _ReviewCard(
                  review: review,
                  // The Propriétaire and the Gérant (`profile.manage`).
                  onReport: authProvider.can('profile.manage')
                      ? () => _report(review.id)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Review review;

  /// « Signaler », for a member who may (null: not offered).
  final VoidCallback? onReport;

  const _ReviewCard({required this.review, this.onReport});

  @override
  Widget build(BuildContext context) {
    final initial = review.userName.isNotEmpty
        ? review.userName[0].toUpperCase()
        : '?';

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
              child: Text(
                initial,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacingSM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          review.userName,
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ...List.generate(
                        5,
                        (i) => Icon(
                          i < review.rating ? Icons.star : Icons.star_border,
                          size: AppTheme.iconXS,
                          color: AppColors.starRating,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingXS),
                  Text(
                    Formatters.formatDateShort(review.createdAt),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  Text(
                    review.text,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  // The client's « Signaler » (review_tile.dart): compact and
                  // quiet — the action is rare, the review is the subject.
                  if (onReport != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onReport,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          // §13.2: the padded tap target keeps ≥48 of hit area.
                          minimumSize: const Size(0, 32),
                        ),
                        child: Text(
                          'Signaler',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
