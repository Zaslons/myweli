import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart' as provider_package;

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/provider.dart' as models;
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../widgets/common/app_snack_bar.dart';
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

  /// The image's share of a grid card — constant chrome; it must NOT track the
  /// font (SYSTEM.md §13.3).
  static const double _imageHeight = 180.0;

  /// The text block's own height at 1×: title row 24 (`titleMedium`, or the
  /// 16px verified glyph — whichever is taller) + 4 + rating row 16 + 4 +
  /// location row 16. Measured, and pinned by `test/a11y/text_scale_test.dart`
  /// so it can't rot silently when a row is added.
  static const double _textBlockHeight = 68.0;

  /// The text block at the current OS text scale — **the only part of a card
  /// that moves with the font**, since the image and the padding are chrome.
  ///
  /// Extracted in A12 because it is the one term [carouselHeight], [gridHeight]
  /// and the compact branch in [_buildGridCard] all have to agree on. They did
  /// not, and the card overflowed by 54dp inside a box this same file had
  /// measured for it — see the branch's own comment.
  static double _textBlock(BuildContext context) =>
      AppTheme.textScaledBound(context, constant: 0, text: _textBlockHeight);

  /// The height a horizontal carousel must give a grid card at the current OS
  /// text scale. Callers used to hard-code `280`, which clipped the card's text
  /// at 200% — and which no caller could fix without knowing this file's image
  /// height, so the decomposition lives here (SYSTEM.md §13.3).
  ///
  /// 280 at 1× and at every scale below it (the floor — see
  /// [AppTheme.textScaledBound]); 348 at 200%.
  ///
  /// It is also **the definition of a roomy card**: exactly the room the
  /// full-size layout needs, which is what [_buildGridCard] now tests against.
  static double carouselHeight(BuildContext context) =>
      _imageHeight + AppTheme.spacingM * 2 + _textBlock(context);

  /// The smallest image a compact (grid) card will draw — `_buildGridCard`
  /// derives its image from the height it is given and clamps there.
  static const double _compactImageFloor = 110.0;

  /// The height a two-column GRID must give a card at the current OS text scale
  /// (A12, §21 row 68).
  ///
  /// [carouselHeight]'s twin, and it needs its own constant because a grid card
  /// is *compact*: the picture absorbs a shorter box, so the **text block is
  /// the part that cannot shrink**. The bound is therefore the image FLOOR plus
  /// padding, with only the text tracking the scale.
  ///
  /// `provider_list_screen.dart` used `childAspectRatio: 0.75` instead — a
  /// height derived from the tile's WIDTH, which does not move when the font
  /// does. 210 at 1× (the 208 that ratio produced at 360dp, within 2dp) and
  /// 278 at 200%, where the old grid stayed at 208 and clipped.
  static double gridHeight(BuildContext context) =>
      _compactImageFloor + AppTheme.spacingM * 2 + _textBlock(context);

  /// `kMinLegibleChars` characters of `titleMedium` plus an ellipsis, measured
  /// in Roboto at 1×: **75.6dp** for « Beauté D… », the widest 8-character
  /// prefix in the salon catalogue. Rounded up.
  ///
  /// It is the catalogue's worst, not every possible name's — a salon called
  /// « WWWWWWWW » would want more. The gate re-measures what it actually
  /// renders, so this constant is the design input, not the guarantee.
  static const double _minNameWidth = 76.0;

  /// The narrowest cell that can still **name** a salon at the current OS text
  /// scale — a card whose title reads « Sal… » identifies nothing (§13.3).
  ///
  /// A12: a 360dp screen's two-column cell is 156dp, of which the name gets
  /// 140. That holds 8 characters until **1.90×** — and the contract point is
  /// ≈1.95×, so the real device is on the wrong side of it. The crossing moves
  /// with the width (375dp holds out to 2.00×, 390dp past it), which is why
  /// this is a rule about the CELL and not a text-scale constant like the
  /// dashboard's: a scale threshold would be wrong at two of §10's three
  /// widths.
  static double minGridCellWidth(BuildContext context) =>
      AppTheme.textScaledBound(
        context,
        constant: AppTheme.spacingS * 2,
        text: _minNameWidth,
      );

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
              final hasBoundedHeight =
                  constraints.hasBoundedHeight &&
                  constraints.maxHeight != double.infinity;
              // Unbounded → the card has all the room there is, so it is the
              // roomy layout by definition. This was a bare `280.0`, which is
              // that number only at 1×.
              final maxH = hasBoundedHeight
                  ? constraints.maxHeight
                  : carouselHeight(context);

              final textBlock = _textBlock(context);

              // **A card is compact exactly when its box cannot hold the roomy
              // layout** — and `carouselHeight` *is* the roomy layout's height,
              // so the two can no longer disagree.
              //
              // A12 device-confirmed: this was `maxH < 260`, a raw dp
              // threshold, and A12's own `gridHeight` (142 + 68 × scale)
              // crosses 260 at ≈1.74×. Above that the card drew the 180dp
              // ROOMY image inside a box measured for the 110dp compact one —
              // « BOTTOM OVERFLOWED BY 55 PIXELS » on a 360×780pt iPhone at
              // ≈1.95×, and 54 in the gate at 2×. A constant that gates a
              // text-dependent branch has to move with the text (§13.3).
              final compact = maxH < carouselHeight(context);
              final contentPadding = compact
                  ? AppTheme.spacingS
                  : AppTheme.spacingM;
              // Compact means the PICTURE absorbs the shorter box, because the
              // text block is the part that cannot shrink — so the image takes
              // what is LEFT, not a fraction of the total. `(maxH * 0.56)` was
              // the same mistake one layer down: a height derived from
              // something that does not track the font.
              final imageHeight = compact
                  ? (maxH - contentPadding * 2 - textBlock).clamp(
                      _compactImageFloor,
                      _imageHeight,
                    )
                  : _imageHeight;

              final hasBoundedWidth =
                  constraints.hasBoundedWidth &&
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
                          child: Semantics(
                            button: true,
                            toggled: isFavorite,
                            label: isFavorite
                                ? 'Retirer des favoris'
                                : 'Ajouter aux favoris',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () async {
                                if (!authProvider.isAuthenticated) {
                                  AppSnackBar.show(
                                    context,
                                    'Connectez-vous pour ajouter aux favoris',
                                  );
                                  final currentPath = GoRouterState.of(
                                    context,
                                  ).uri.toString();
                                  context.go(
                                    '/login?returnTo=${Uri.encodeComponent(currentPath)}',
                                  );
                                  return;
                                }

                                final messenger = ScaffoldMessenger.of(context);
                                // The toggle can fail — a green snackbar on a failed
                                // toggle would also arm an « Annuler » that performs it.
                                final ok = await favoritesProvider
                                    .toggleFavorite(userId, provider.id);
                                AppSnackBar.outcomeOn(
                                  messenger,
                                  ok: ok,
                                  success: isFavorite
                                      ? 'Retiré des favoris'
                                      : 'Ajouté aux favoris',
                                  error:
                                      favoritesProvider.error ??
                                      'Une erreur est survenue. Réessayez.',
                                  action: !ok
                                      ? null
                                      : SnackAction(
                                          label: 'Annuler',
                                          onPressed: () =>
                                              favoritesProvider.toggleFavorite(
                                                userId,
                                                provider.id,
                                              ),
                                          isOnlyRouteBack: false,
                                        ),
                                );
                              },
                              child: SizedBox(
                                // §13.2 48 hit area; Align keeps the visible 36px
                                // circle at the original top-right corner (8,8).
                                width: 48,
                                height: 48,
                                child: Align(
                                  alignment: Alignment.topRight,
                                  child: Container(
                                    padding: const EdgeInsets.all(
                                      AppTheme.spacingS,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.secondary.withValues(
                                        alpha: 0.9,
                                      ),
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
                              const Icon(
                                Icons.star,
                                size: AppTheme.iconXS,
                                color: AppColors.starRating,
                              ),
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
                              const Icon(
                                Icons.location_on,
                                size: AppTheme.iconXS,
                                color: AppColors.textTertiary,
                              ),
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
                      child: Semantics(
                        button: true,
                        toggled: isFavorite,
                        label: isFavorite
                            ? 'Retirer des favoris'
                            : 'Ajouter aux favoris',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            if (!authProvider.isAuthenticated) {
                              AppSnackBar.show(
                                context,
                                'Connectez-vous pour ajouter aux favoris',
                              );
                              final currentPath = GoRouterState.of(
                                context,
                              ).uri.toString();
                              context.go(
                                '/login?returnTo=${Uri.encodeComponent(currentPath)}',
                              );
                              return;
                            }

                            final messenger = ScaffoldMessenger.of(context);
                            // The toggle can fail — a green snackbar on a failed
                            // toggle would also arm an « Annuler » that performs it.
                            final ok = await favoritesProvider.toggleFavorite(
                              userId,
                              provider.id,
                            );
                            AppSnackBar.outcomeOn(
                              messenger,
                              ok: ok,
                              success: isFavorite
                                  ? 'Retiré des favoris'
                                  : 'Ajouté aux favoris',
                              error:
                                  favoritesProvider.error ??
                                  'Une erreur est survenue. Réessayez.',
                              action: !ok
                                  ? null
                                  : SnackAction(
                                      label: 'Annuler',
                                      onPressed: () => favoritesProvider
                                          .toggleFavorite(userId, provider.id),
                                      isOnlyRouteBack: false,
                                    ),
                            );
                          },
                          child: SizedBox(
                            // §13.2 48 hit area; Align keeps the 24px circle at the
                            // original (4,4) corner on the 80px thumbnail.
                            width: 48,
                            height: 48,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Container(
                                padding: const EdgeInsets.all(
                                  AppTheme.spacingXS,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.secondary.withValues(
                                    alpha: 0.9,
                                  ),
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
                            const Icon(
                              Icons.star,
                              size: AppTheme.iconXS,
                              color: AppColors.starRating,
                            ),
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
                            const Icon(
                              Icons.location_on,
                              size: AppTheme.iconXS,
                              color: AppColors.textTertiary,
                            ),
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
