import 'package:flutter/material.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/review.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_reviews_provider.dart';

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
        final reviewsProvider =
            Provider.of<ProReviewsProvider>(context, listen: false);
        reviewsProvider.loadReviews(_resolvedProviderId(context));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Avis'),
      ),
      body: Consumer2<ProAuthProvider, ProReviewsProvider>(
        builder: (context, authProvider, reviewsProvider, _) {
          if (!authProvider.isAuthenticated) {
            return const Center(child: Text('Veuillez vous connecter'));
          }

          if (reviewsProvider.isLoading && reviewsProvider.reviews.isEmpty) {
            return const Center(child: LoadingIndicator());
          }

          final reviews = reviewsProvider.reviews;

          // Calculate average rating
          double averageRating = 0;
          if (reviews.isNotEmpty) {
            averageRating =
                reviews.map((r) => r.rating).reduce((a, b) => a + b) /
                    reviews.length;
          }

          if (reviews.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_outline,
                      size: AppTheme.iconXL, color: AppColors.textSecondary),
                  const SizedBox(height: AppTheme.spacingM),
                  Text(
                    'Aucun avis',
                    style: AppTextStyles.titleLarge
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  Text(
                    'Les avis de vos clients apparaîtront ici',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            );
          }

          return BrandRefresh(
            onRefresh: () async {
              if (authProvider.provider != null) {
                await reviewsProvider.loadReviews(_resolvedProviderId(context));
              }
            },
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
                              const Icon(Icons.star,
                                  size: AppTheme.iconL,
                                  color: AppColors.starRating),
                              const SizedBox(width: AppTheme.spacingS),
                              Text(
                                averageRating.toStringAsFixed(1),
                                style: AppTextStyles.headlineMedium.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.spacingXS),
                          Text(
                            '${reviews.length} avis',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Rating distribution
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(5, (index) {
                          final rating = 5 - index;
                          final count =
                              reviews.where((r) => r.rating == rating).length;
                          final percentage =
                              reviews.isEmpty ? 0.0 : count / reviews.length;
                          return Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppTheme.spacingXS),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$rating',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: AppTheme.spacingXS),
                                const Icon(Icons.star,
                                    size: AppTheme.iconXS,
                                    color: AppColors.starRating),
                                const SizedBox(width: AppTheme.spacingS),
                                SizedBox(
                                  width: 100,
                                  child: LinearProgressIndicator(
                                    value: percentage,
                                    backgroundColor: AppColors.surface,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            AppColors.gold),
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
                    ],
                  ),
                ),
                // Reviews List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingM),
                    itemCount: reviews.length,
                    itemBuilder: (context, index) {
                      final review = reviews[index];
                      return _ReviewCard(review: review);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Review review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final initial =
        review.userName.isNotEmpty ? review.userName[0].toUpperCase() : '?';

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
                                i < review.rating
                                    ? Icons.star
                                    : Icons.star_border,
                                size: AppTheme.iconXS,
                                color: AppColors.starRating,
                              )),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
