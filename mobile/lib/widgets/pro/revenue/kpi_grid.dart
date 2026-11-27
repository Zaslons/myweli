import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/revenue_wording.dart';
import '../../../core/utils/text_fit.dart';
import '../../common/app_card.dart';
import 'delta_badge.dart';

/// The figure tiles, two across — or one per row, ALL of them, when a tile's
/// texts would not fit a half-width tile (docs/design/amounts-that-fit.md §2;
/// SYSTEM.md §11.3).
///
/// **`_StatBlock` moved out of the Accueil unchanged** (pro-revenue-analytics
/// §12.1), so the Accueil and « Revenus » share one rule:
///
/// **Measured, not a text-size constant.** At 360dp a half tile has 126dp:
/// « 114 000 » at 2× needs 171 and was broken inside the number, while the
/// same amount at 430dp, or a smaller one at 360dp, fits. The shape depends on
/// the width, the text size AND the amount, so all three are asked. One
/// decision for every tile: a two-across row above a stacked one would read as
/// two different screens.
///
/// A row's tiles are as tall as its tallest (« 114 000 FCFA » wraps its unit
/// in one tile and not its neighbour — pro-screenshot-shoot-fixes.md §2.4).
///
/// A [KpiTile.fullWidth] tile (« Prévu », §4.5) takes a row of its own and
/// is left out of the two-across measure: it never shares its width.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.tiles});

  final List<KpiTile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = TextFit.of(context).columns(
          candidates: const [2, 1],
          cellWidth: (n) =>
              (box.maxWidth - (n - 1) * AppTheme.spacingSM) / n -
              2 * KpiTile.padding,
          texts: [
            for (final tile in tiles)
              if (!tile.fullWidth) ...tile.texts,
          ],
        );
        final rows = <List<KpiTile>>[];
        for (final tile in tiles) {
          final last = rows.isEmpty ? null : rows.last;
          if (tile.fullWidth ||
              last == null ||
              last.first.fullWidth ||
              last.length == columns) {
            rows.add([tile]);
          } else {
            last.add(tile);
          }
        }
        return Column(
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) const SizedBox(height: AppTheme.spacingSM),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (k, tile) in row.indexed) ...[
                      if (k > 0) const SizedBox(width: AppTheme.spacingSM),
                      Expanded(child: tile),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One figure: its title (and an optional glyph beside it), the value, a
/// delta, a caption under it. The Accueil's card, as it was (§12.1).
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.title,
    required this.value,
    this.caption,
    this.icon,
    this.iconColor,
    this.delta,
    this.onTap,
    this.semanticsLabel,
    this.fullWidth = false,
  });

  final String title;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color? iconColor;
  final RevenueDelta? delta;

  /// The whole tile is the target, announced as a button (`AppCard`).
  final VoidCallback? onTap;

  /// One sentence for a screen reader in place of the texts read one by one
  /// (« Réalisé : 1 250 000 FCFA, en hausse de 12 % par rapport à … »).
  final String? semanticsLabel;
  final bool fullWidth;

  static const double padding = AppTheme.spacingM;
  static const TextStyle _labelStyle = AppTextStyles.bodySmall;
  static const TextStyle _valueStyle = AppTextStyles.headlineSmall;

  /// What this tile draws, with the styles it draws them in — for
  /// [KpiGrid]'s measure. Colour does not change a width.
  List<FitText> get texts => [
    (text: title, style: _labelStyle),
    (text: value, style: _valueStyle),
    if (delta case final d?) (text: d.text, style: DeltaBadge.textStyle),
    if (caption case final c?) (text: c, style: _labelStyle),
  ];

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A12 — §21 row 68's finding #3: **an icon does not text-scale.**
        // The glyph drops to its own line rather than squeezing a title that
        // cannot help it — « Aujourd'hui » is ONE word. `double.infinity` is
        // load-bearing: a Wrap shrink-wraps, so `spaceBetween` inside one
        // has nothing to distribute and the icon would sit against the title.
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: AppTheme.spacingXS,
            children: [
              Text(
                title,
                style: _labelStyle.copyWith(color: AppColors.textSecondary),
              ),
              if (icon case final glyph?)
                Icon(
                  glyph,
                  color: iconColor ?? AppColors.primary,
                  size: AppTheme.iconS,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingS),
        Text(value, style: _valueStyle.copyWith(color: AppColors.textPrimary)),
        if (delta case final d?) ...[
          const SizedBox(height: AppTheme.spacingXS),
          DeltaBadge(d),
        ],
        if (caption case final c?)
          Text(c, style: _labelStyle.copyWith(color: AppColors.textTertiary)),
      ],
    );
    final label = semanticsLabel;
    return AppCard(
      // The same constant [KpiGrid]'s measure reads.
      padding: const EdgeInsets.all(padding),
      onTap: onTap,
      child: label == null
          ? body
          : Semantics(label: label, excludeSemantics: true, child: body),
    );
  }
}
