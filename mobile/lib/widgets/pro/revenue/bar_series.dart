import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../common/label_value_row.dart';

/// One bucket of « Évolution »: its value, its name under the chart, and the
/// sentence the line above the chart says when it is selected
/// (« mar. 4 nov. · 45 000 FCFA · 2 rendez-vous »).
class BarSeriesPoint {
  const BarSeriesPoint({
    required this.value,
    required this.axisLabel,
    required this.sentence,
    required this.listLabel,
    required this.listValue,
  });

  final double value;
  final String axisLabel;
  final String sentence;

  /// The list form's two halves: « mar. 4 nov. » · « 45 000 FCFA · 2 rdv ».
  final String listLabel;
  final String listValue;
}

/// « Évolution » — the period's « Réalisé » per bucket
/// (docs/design/pro-revenue-analytics.md §4.6, §12.1; SYSTEM.md §11.3).
/// **No chart package** (the APK budget): bars are plain boxes in a `Row`,
/// nothing repaints per frame.
///
/// - **Tap or drag across the chart** selects the nearest bar, so a 10dp bar
///   (31 in 328dp) is still easy to reach; a tap outside the chart clears it.
/// - **Selection is a fill, not an outline**: the selected bar stays
///   `primary`, the others turn `borderStrong` (3.22:1, still visible). A
///   `borderFocus` outline would be black on a black bar.
/// - **One semantics node** for the whole chart — it passes the tap-target
///   guideline where 31 ten-dp buttons would fail it: its value is the
///   selected bucket's sentence (or the period's), and increase / decrease
///   move the selection, so a screen reader swipes through the buckets.
/// - The list form ([BarSeriesList]) is the one 200 % text and anyone who
///   prefers it read (« Voir en liste »).
class BarSeries extends StatefulWidget {
  const BarSeries({
    super.key,
    required this.points,
    required this.summary,
    this.label = 'Évolution du réalisé',
  });

  final List<BarSeriesPoint> points;

  /// What the line says with no bar selected: the period's total.
  final String summary;
  final String label;

  /// The chart's height: a drawing's own dimension (§5 « What §5 does not
  /// govern »), named once.
  static const double height = 160;

  /// The space between two bars, and the least a non-zero bar is drawn.
  static const double gap = AppTheme.spacingXS / 2;
  static const double minBar = AppTheme.spacingXS / 2;

  @override
  State<BarSeries> createState() => _BarSeriesState();
}

class _BarSeriesState extends State<BarSeries> {
  int? _selected;

  @override
  void didUpdateWidget(BarSeries old) {
    super.didUpdateWidget(old);
    // Another period: its buckets are other days.
    if (old.points.length != widget.points.length) _selected = null;
  }

  void _select(int? index) {
    if (index == _selected) return;
    setState(() => _selected = index);
  }

  void _selectAt(double dx, double width) {
    final n = widget.points.length;
    if (n == 0 || width <= 0) return;
    _select((dx / width * n).floor().clamp(0, n - 1));
  }

  String _lineOf(int? index) =>
      index == null ? widget.summary : widget.points[index].sentence;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final selected = _selected;
    final max = points.fold<double>(0, (m, p) => p.value > m ? p.value : m);
    final line = _lineOf(selected);
    final next = selected == null
        ? 0
        : (selected + 1 < points.length ? selected + 1 : null);
    final previous = selected == null
        ? points.length - 1
        : (selected > 0 ? selected - 1 : null);

    final axis = <String>[
      if (points.isNotEmpty) points.first.axisLabel,
      if (points.length > 2) points[points.length ~/ 2].axisLabel,
      if (points.length > 1) points.last.axisLabel,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Said by the chart's node as its value; drawn here for the eye.
        ExcludeSemantics(
          child: Text(
            line,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacingS),
        TapRegion(
          onTapOutside: (_) => _select(null),
          child: Semantics(
            container: true,
            label: widget.label,
            value: line,
            increasedValue: next == null ? null : _lineOf(next),
            decreasedValue: previous == null ? null : _lineOf(previous),
            onIncrease: next == null ? null : () => _select(next),
            onDecrease: previous == null ? null : () => _select(previous),
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _selectAt(d.localPosition.dx, box.maxWidth),
                onHorizontalDragStart: (d) =>
                    _selectAt(d.localPosition.dx, box.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _selectAt(d.localPosition.dx, box.maxWidth),
                child: SizedBox(
                  height: BarSeries.height,
                  width: double.infinity,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (i, p) in points.indexed) ...[
                        if (i > 0) const SizedBox(width: BarSeries.gap),
                        Expanded(
                          child: _Bar(
                            height: p.value <= 0 || max <= 0
                                ? 0
                                : (p.value / max * BarSeries.height).clamp(
                                    BarSeries.minBar,
                                    BarSeries.height,
                                  ),
                            color: selected == null || selected == i
                                ? AppColors.primary
                                : AppColors.borderStrong,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacingXS),
        ExcludeSemantics(
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: AppTheme.spacingXS,
              children: [
                for (final a in axis)
                  Text(
                    a,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusSmall),
        ),
      ),
    ),
  );
}

/// « Voir en liste »: the same buckets as rows — the date, then the amount
/// and the count. Wraps at 200 % (a `LabelValueRow` drops its value to its
/// own line when both do not fit).
class BarSeriesList extends StatelessWidget {
  const BarSeriesList({super.key, required this.points});

  final List<BarSeriesPoint> points;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (i, p) in points.indexed) ...[
        if (i > 0) const Divider(height: AppTheme.spacingM),
        MergeSemantics(
          child: LabelValueRow(
            label: p.listLabel,
            value: p.listValue,
            labelStyle: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            valueStyle: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    ],
  );
}
