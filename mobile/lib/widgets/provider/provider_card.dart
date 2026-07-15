import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart' as provider_package;

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/provider.dart' as models;
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../common/timed_cached_image.dart';

class ProviderCard extends StatelessWidget {
  final models.Provider provider;
  final bool isGrid;
  final VoidCallback onTap;

  const ProviderCard({
    super.key,
    required this.provider,
    this.isGrid = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isGrid) {
      return _buildGridCard(context);
    }
    return _buildListCard(context);
  }

  Widget _buildGridCard(BuildContext context) {
    return provider_package.Consumer2<FavoritesProvider, AuthProvider>(
      builder: (context, favoritesProvider, authProvider, _) {
        final isFavorite = authProvider.isAuthenticated
            ? favoritesProvider.isFavorite(provider.id)
            : false;
        final userId = authProvider.user?.id ?? '';

        return GestureDetector(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasBoundedHeight = constraints.hasBoundedHeight &&
                  constraints.maxHeight != double.infinity;
              final maxH = hasBoundedHeight ? constraints.maxHeight : 280.0;

              // When used inside a tight grid cell, avoid fixed 180px image height
              // which can overflow the card content vertically.
              final compact = maxH < 260;
              final imageHeight =
                  compact ? (maxH * 0.56).clamp(110.0, 150.0) : 180.0;
              final contentPadding =
                  compact ? AppTheme.spacingS : AppTheme.spacingM;

              final hasBoundedWidth = constraints.hasBoundedWidth &&
                  constraints.maxWidth != double.infinity;
              // Horizontal carousels often provide an unbounded width; in that case,
              // keep a fixed width so layout constraints stay valid.
              final cardWidth = hasBoundedWidth ? double.infinity : 280.0;

              return Container(
                width: cardWidth,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                  boxShadow: AppTheme.elevation1,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(AppTheme.radiusXL),
                          ),
                          child: TimedCachedImage(
                            imageUrl: provider.imageUrls.isNotEmpty
                                ? provider.imageUrls.first
                                : 'https://via.placeholder.com/400x300',
                            height: imageHeight,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              if (!authProvider.isAuthenticated) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Connectez-vous pour ajouter aux favoris'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                final currentPath =
                                    GoRouterState.of(context).uri.toString();
                                context.go(
                                    '/login?returnTo=${Uri.encodeComponent(currentPath)}');
                                return;
                              }

                              await favoritesProvider.toggleFavorite(
                                  userId, provider.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isFavorite
                                          ? 'Retiré des favoris'
                                          : 'Ajouté aux favoris',
                                    ),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                            child: SizedBox(
                              // §13.2 48 hit area; Align keeps the visible 36px
                              // circle at the original top-right corner (8,8).
                              width: 48,
                              height: 48,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Container(
                                  padding:
                                      const EdgeInsets.all(AppTheme.spacingS),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary
                                        .withValues(alpha: 0.9),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: isFavorite
                                        ? AppColors.favorite
                                        : AppColors.textPrimary,
                                    size: AppTheme.iconS,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.all(contentPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  provider.name,
                                  style: AppTextStyles.titleMedium.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (provider.verified) ...[
                                const SizedBox(width: AppTheme.spacingXS),
                                const Icon(
                                  Icons.verified,
                                  size: AppTheme.iconXS,
                                  color: AppColors.info,
                                  semanticLabel: 'Salon vérifié',
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: AppTheme.spacingXS),
                          Row(
                            children: [
                              const Icon(Icons.star,
                                  size: AppTheme.iconXS,
                                  color: AppColors.starRating),
                              const SizedBox(width: AppTheme.spacingXS),
                              Text(
                                provider.rating.toStringAsFixed(1),
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: AppTheme.spacingS),
                              Text(
                                '(${provider.reviewCount})',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.spacingXS),
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: AppTheme.iconXS,
                                  color: AppColors.textTertiary),
                              const SizedBox(width: AppTheme.spacingXS),
                              Expanded(
                                child: Text(
                                  provider.city ?? provider.address,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildListCard(BuildContext context) {
    return provider_package.Consumer2<FavoritesProvider, AuthProvider>(
      builder: (context, favoritesProvider, authProvider, _) {
        final isFavorite = authProvider.isAuthenticated
            ? favoritesProvider.isFavorite(provider.id)
            : false;
        final userId = authProvider.user?.id ?? '';

        return GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(AppTheme.radiusXL),
              boxShadow: AppTheme.elevation1,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(AppTheme.radiusXL),
                      ),
                      child: TimedCachedImage(
                        imageUrl: provider.imageUrls.isNotEmpty
                            ? provider.imageUrls.first
                            : 'https://via.placeholder.com/400x300',
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          if (!authProvider.isAuthenticated) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Connectez-vous pour ajouter aux favoris'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            final currentPath =
                                GoRouterState.of(context).uri.toString();
                            context.go(
                                '/login?returnTo=${Uri.encodeComponent(currentPath)}');
                            return;
                          }

                          await favoritesProvider.toggleFavorite(
                              userId, provider.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isFavorite
                                      ? 'Retiré des favoris'
                                      : 'Ajouté aux favoris',
                                ),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                        child: SizedBox(
                          // §13.2 48 hit area; Align keeps the 24px circle at the
                          // original (4,4) corner on the 80px thumbnail.
                          width: 48,
                          height: 48,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Container(
                              padding: const EdgeInsets.all(AppTheme.spacingXS),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.secondary.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isFavorite
                                    ? AppColors.favorite
                                    : AppColors.textPrimary,
                                size: AppTheme.iconXS,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingM),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.name,
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppTheme.spacingXS),
                        Row(
                          children: [
                            const Icon(Icons.star,
                                size: AppTheme.iconXS,
                                color: AppColors.starRating),
                            const SizedBox(width: AppTheme.spacingXS),
                            Text(
                              provider.rating.toStringAsFixed(1),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: AppTheme.spacingS),
                            Text(
                              '(${provider.reviewCount})',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spacingXS),
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                size: AppTheme.iconXS,
                                color: AppColors.textTertiary),
                            const SizedBox(width: AppTheme.spacingXS),
                            Expanded(
                              child: Text(
                                provider.city ?? provider.address,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
