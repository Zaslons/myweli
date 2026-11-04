import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import 'app_card.dart';

/// The loading shape of content whose shape is known (SYSTEM.md §12) — a
/// list, a card, a page of facts. B9.8 (docs/design/hygiene-batch9.md
/// §2.7.2, decision Q11).
///
/// **Still, on purpose.** A pulse is a `repeat()` loop: it would have to read
/// the reduced-motion setting (§9.1) and run on a duration none of the five
/// motion tokens names. If one is wanted later, it is a token decision —
/// the doc, the Dart and the web mirror together.
///
/// **On a card, always.** The bars are `surfaceVariant`, the darkest surface;
/// on the page's `background` they all but vanish (§2's contrast note), on a
/// `secondary` card they read. Screen readers hear one « Chargement… » and
/// nothing of the shapes — the idiom of the Profil card's skeleton.

const _bar = 16.0;
const _avatar = 40.0;

/// Wraps a loading shape: one label, the shapes excluded.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({super.key, required this.child, this.label});

  final Widget child;

  /// Defaults to « Chargement… »; a screen may say what is loading.
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label ?? 'Chargement…',
    child: ExcludeSemantics(child: child),
  );
}

/// A line of text that is not there yet.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({super.key, this.widthFactor = 1, this.height = _bar});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: widthFactor,
    alignment: AlignmentDirectional.centerStart,
    child: SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
      ),
    ),
  );
}

/// An avatar or an icon that is not there yet.
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, this.size = _avatar});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// An image that is not there yet — a photo, a map.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({super.key, this.height = 160, this.aspectRatio});

  final double height;

  /// When set, the block keeps this ratio instead of [height] (a grid tile).
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
    );
    final ratio = aspectRatio;
    return ratio == null
        ? SizedBox(height: height, width: double.infinity, child: box)
        : AspectRatio(aspectRatio: ratio, child: box);
  }
}

/// The lines of one card: each a bar of a given width, `spacingS` apart.
class _Lines extends StatelessWidget {
  const _Lines(this.widths);

  final List<double> widths;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, w) in widths.indexed) ...[
        if (i > 0) const SizedBox(height: AppTheme.spacingS),
        SkeletonBar(widthFactor: w),
      ],
    ],
  );
}

/// What a card of a [SkeletonCardList] leads with, as the real card does.
enum SkeletonLead {
  none,

  /// A person: the team, a client.
  avatar,

  /// A photo beside the text: a salon in a list, a booking.
  thumbnail,
}

/// A list of cards — bookings, the team, services, reviews, salons. Each card
/// holds [lines] (widths as fractions) after its [lead], or under an image
/// [block] when the real card opens on a photo.
class SkeletonCardList extends StatelessWidget {
  const SkeletonCardList({
    super.key,
    this.count = 4,
    this.lines = const [0.55, 0.85, 0.35],
    this.lead = SkeletonLead.none,
    this.block = false,
    this.padding = const EdgeInsets.all(AppTheme.spacingM),
    this.label,
  });

  final int count;
  final List<double> lines;
  final SkeletonLead lead;
  final bool block;
  final EdgeInsetsGeometry padding;
  final String? label;

  static const _thumbnail = 64.0;

  @override
  Widget build(BuildContext context) => AppSkeleton(
    label: label,
    child: ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spacingS),
      itemBuilder: (_, _) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (block) ...[
              const SkeletonBlock(height: 120),
              const SizedBox(height: AppTheme.spacingM),
            ],
            switch (lead) {
              SkeletonLead.none => _Lines(lines),
              SkeletonLead.avatar || SkeletonLead.thumbnail => Row(
                children: [
                  if (lead == SkeletonLead.avatar)
                    const SkeletonCircle()
                  else
                    const SizedBox.square(
                      dimension: _thumbnail,
                      child: SkeletonBlock(aspectRatio: 1),
                    ),
                  const SizedBox(width: AppTheme.spacingM),
                  Expanded(child: _Lines(lines)),
                ],
              ),
            },
          ],
        ),
      ),
    ),
  );
}

/// A list of rows in one card — notifications, clients, preferences: a
/// circle and two lines each, divided.
class SkeletonTileList extends StatelessWidget {
  const SkeletonTileList({
    super.key,
    this.count = 6,
    this.leading = true,
    this.padding = const EdgeInsets.all(AppTheme.spacingM),
    this.label,
  });

  final int count;
  final bool leading;
  final EdgeInsetsGeometry padding;
  final String? label;

  @override
  Widget build(BuildContext context) => AppSkeleton(
    label: label,
    child: ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.divider),
                Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  child: Row(
                    children: [
                      if (leading) ...[
                        const SkeletonCircle(),
                        const SizedBox(width: AppTheme.spacingM),
                      ],
                      const Expanded(child: _Lines([0.6, 0.35])),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// A page of facts — a detail screen, a settings form: an optional image
/// [block] on top, then [sections] cards, each a label and its values.
class SkeletonDetail extends StatelessWidget {
  const SkeletonDetail({
    super.key,
    this.block = false,
    this.sections = 3,
    this.padding = const EdgeInsets.all(AppTheme.spacingM),
    this.label,
  });

  final bool block;
  final int sections;
  final EdgeInsetsGeometry padding;
  final String? label;

  @override
  Widget build(BuildContext context) => AppSkeleton(
    label: label,
    child: ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      children: [
        if (block) ...[
          const AppCard(padding: EdgeInsets.zero, child: SkeletonBlock()),
          const SizedBox(height: AppTheme.spacingM),
        ],
        for (var i = 0; i < sections; i++) ...[
          if (i > 0) const SizedBox(height: AppTheme.spacingM),
          const AppCard(child: _Lines([0.3, 0.8, 0.65, 0.5])),
        ],
      ],
    ),
  );
}

/// A grid of photos — the salon's gallery, its before / after pairs.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({
    super.key,
    this.count = 6,
    this.crossAxisCount = 3,
    this.padding = const EdgeInsets.all(AppTheme.spacingM),
    this.label,
  });

  final int count;
  final int crossAxisCount;
  final EdgeInsetsGeometry padding;
  final String? label;

  @override
  Widget build(BuildContext context) => AppSkeleton(
    label: label,
    child: Padding(
      padding: padding,
      child: AppCard(
        padding: const EdgeInsets.all(AppTheme.spacingS),
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: AppTheme.spacingS,
          crossAxisSpacing: AppTheme.spacingS,
          children: [
            for (var i = 0; i < count; i++) const SkeletonBlock(aspectRatio: 1),
          ],
        ),
      ),
    ),
  );
}

/// A row of choices that is not there yet — the day's slots, the operators.
///
/// These sit where the chips sit, on the page rather than on a card, so each
/// is the chip's own silhouette — `secondary` with the `border` hairline —
/// not a `surfaceVariant` bar, which the page's `background` would swallow.
class SkeletonPills extends StatelessWidget {
  const SkeletonPills({super.key, this.count = 6, this.label});

  final int count;
  final String? label;

  static const _width = 72.0;
  static const _height = 40.0;

  @override
  Widget build(BuildContext context) => AppSkeleton(
    label: label,
    child: Wrap(
      spacing: AppTheme.spacingS,
      runSpacing: AppTheme.spacingS,
      children: [
        for (var i = 0; i < count; i++)
          SizedBox(
            width: _width,
            height: _height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.secondary,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              ),
            ),
          ),
      ],
    ),
  );
}
