import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/before_after_pair.dart';
import '../common/timed_cached_image.dart';

/// Consumer salon-profile "Avant / Après" section (FR-DISC-006): a drag-to-reveal
/// slider for the selected pair, an optional caption, and a thumbnail strip to
/// switch pairs. Design: docs/design/provider-before-after.md §6.
class BeforeAfterSection extends StatefulWidget {
  const BeforeAfterSection({super.key, required this.pairs});

  final List<BeforeAfterPair> pairs;

  @override
  State<BeforeAfterSection> createState() => _BeforeAfterSectionState();
}

class _BeforeAfterSectionState extends State<BeforeAfterSection> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pair = widget.pairs[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The slider (below) is the semantic control — it carries its own
        // Semantics(slider, value). Wrapping it in a second Semantics(button)
        // fuses into one contradictory button+slider node, so the tap-to-enlarge
        // stays a plain gesture on top of the slider.
        GestureDetector(
          onTap: () => _openFullscreen(context, pair),
          child: BeforeAfterSlider(before: pair.before, after: pair.after),
        ),
        if (pair.caption != null) ...[
          const SizedBox(height: AppTheme.spacingS),
          Text(pair.caption!,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
        ],
        if (widget.pairs.length > 1) ...[
          const SizedBox(height: AppTheme.spacingM),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.pairs.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppTheme.spacingS),
              itemBuilder: (context, i) {
                final active = i == _index;
                return Semantics(
                  button: true,
                  selected: active,
                  label: 'Comparaison ${i + 1}',
                  child: GestureDetector(
                    onTap: () => setState(() => _index = i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      child: Container(
                        width: 72,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSmall),
                          border: Border.all(
                            color: active
                                ? AppColors.primary
                                : AppColors.borderStrong,
                            width: active ? 2 : 1,
                          ),
                        ),
                        child: TimedCachedImage(
                          imageUrl: widget.pairs[i].after,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: AppTheme.spacingS),
        Text('Glisser pour comparer · toucher pour agrandir',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textTertiary)),
      ],
    );
  }

  void _openFullscreen(BuildContext context, BeforeAfterPair pair) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BeforeAfterSlider(
              before: pair.before,
              after: pair.after,
              height: 420,
            ),
            if (pair.caption != null) ...[
              const SizedBox(height: AppTheme.spacingS),
              Text(pair.caption!,
                  textAlign: TextAlign.center,
                  style:
                      AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
            ],
            const SizedBox(height: AppTheme.spacingS),
            IconButton(
              tooltip: 'Fermer',
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// A drag-to-reveal before/after comparison. A draggable handle wipes between the
/// two images; cheap (a clip-rect, no compositing). Tap is handled by the parent.
class BeforeAfterSlider extends StatefulWidget {
  const BeforeAfterSlider({
    super.key,
    required this.before,
    required this.after,
    this.height = 240,
  });

  final String before;
  final String after;
  final double height;

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  double _pos = 0.5; // 0..1 reveal fraction

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return Semantics(
              slider: true,
              label: 'Comparateur avant/après',
              value: '${(_pos * 100).round()} %',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => setState(
                  () => _pos = (d.localPosition.dx / w).clamp(0.0, 1.0),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TimedCachedImage(imageUrl: widget.after, fit: BoxFit.cover),
                    ClipRect(
                      clipper: _LeftClipper(_pos),
                      child: TimedCachedImage(
                          imageUrl: widget.before, fit: BoxFit.cover),
                    ),
                    const Positioned(bottom: 8, left: 8, child: _Tag('Avant')),
                    const Positioned(bottom: 8, right: 8, child: _Tag('Après')),
                    Positioned(
                      left: (_pos * w) - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: Colors.white),
                    ),
                    Positioned(
                      left: (_pos * w) - 17,
                      top: widget.height / 2 - 17,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ).copyWith(boxShadow: AppTheme.elevation2),
                        child: const Icon(Icons.compare_arrows,
                            size: AppTheme.iconS, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    // Decorative overlay caption — the slider's own label already says
    // "avant/après", so exclude these so they don't leak into its spoken name.
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingS, vertical: AppTheme.spacingXS),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        child: Text(label,
            style: AppTextStyles.labelSmall.copyWith(color: Colors.white)),
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.fraction != fraction;
}
