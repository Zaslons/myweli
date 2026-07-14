import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';

import '../support/golden.dart';
import '../support/wcag.dart';

/// Every color token, with its MEASURED contrast ratio against the background it
/// has to survive (docs/design/SYSTEM.md §3).
///
/// This is the golden A1 exists for. Six token lines move ~370 render sites, and
/// this sheet is where that becomes visible in one glance — including the three
/// current failures, which are labelled ✗ right in the image:
///   textTertiary 3.22:1 · border 1.44:1 · starRating 1.62:1.
void main() {
  group('goldens', () {
    setUpAll(loadGoldenFonts);

    testWidgets('the color tokens', (tester) async {
      await pumpGolden(
        tester,
        const _ColorSheet(),
        size: const Size(470, 1660),
      );
      await expectGolden(tester, 'tokens_color');
    });
  }, skip: kGoldensSkip);
}

/// A token, and the floor it is REQUIRED to clear — not the one it happens to
/// pass. `null` = exempt (decoration, or a disabled control).
class _Tok {
  const _Tok(this.name, this.color, {this.floor, this.note});
  final String name;
  final Color color;
  final double? floor;
  final String? note;
}

class _ColorSheet extends StatelessWidget {
  const _ColorSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          GoldenSection(
            title: 'Brand & surface',
            child: _Swatches([
              _Tok('primary', AppColors.primary,
                  note: 'brand fill — never text'),
              _Tok('primaryLight', AppColors.primaryLight, note: 'hover'),
              _Tok('secondary', AppColors.secondary, note: 'card'),
              _Tok('background', AppColors.background),
              _Tok('surface', AppColors.surface),
              _Tok('surfaceVariant', AppColors.surfaceVariant),
            ]),
          ),
          GoldenSection(
            title: 'Text',
            child: _Swatches([
              _Tok('textPrimary', AppColors.textPrimary, floor: kFloorText),
              _Tok('textSecondary', AppColors.textSecondary, floor: kFloorText),
              _Tok('textTertiary', AppColors.textTertiary, floor: kFloorText),
              _Tok('textDisabled', AppColors.textDisabled, note: 'exempt'),
            ]),
          ),
          GoldenSection(
            title: 'Borders',
            child: _Swatches([
              _Tok('divider', AppColors.divider, note: 'decorative'),
              _Tok('border', AppColors.border, floor: kFloorNonText),
              _Tok('borderFocus', AppColors.borderFocus, floor: kFloorNonText),
            ]),
          ),
          GoldenSection(
            title: 'Semantic',
            child: _Swatches([
              _Tok('success', AppColors.success, floor: kFloorText),
              _Tok('successLight', AppColors.successLight, floor: kFloorText),
              _Tok('error', AppColors.error, floor: kFloorText),
              _Tok('errorLight', AppColors.errorLight, floor: kFloorText),
              _Tok('warning', AppColors.warning, floor: kFloorText),
              _Tok('warningLight', AppColors.warningLight, note: 'tint only'),
              _Tok('info', AppColors.info, floor: kFloorText),
              _Tok('infoLight', AppColors.infoLight, floor: kFloorText),
            ]),
          ),
          GoldenSection(
            title: 'Accents',
            child: _Swatches([
              _Tok('starRating', AppColors.starRating, floor: kFloorNonText),
              _Tok('favorite', AppColors.favorite, floor: kFloorNonText),
              _Tok('gold', AppColors.gold, floor: kFloorNonText),
            ]),
          ),
          GoldenSection(
            title: 'Category (sanctioned exception)',
            child: _Swatches([
              _Tok('categorySpa', AppColors.categorySpa, floor: kFloorText),
              _Tok('categoryBarber', AppColors.categoryBarber,
                  floor: kFloorText),
              _Tok('categorySalon', AppColors.categorySalon, floor: kFloorText),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches(this.tokens);
  final List<_Tok> tokens;

  @override
  Widget build(BuildContext context) => Column(
        children: [for (final t in tokens) _SwatchRow(t)],
      );
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow(this.token);
  final _Tok token;

  @override
  Widget build(BuildContext context) {
    final ratio = contrastRatio(token.color, AppColors.background);
    final floor = token.floor;
    final passes = floor == null || ratio >= floor;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: token.color,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(color: AppColors.divider),
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(token.name, style: _mono(13, FontWeight.w500)),
                Text(
                  '${_hex(token.color)}${token.note == null ? '' : '  · ${token.note}'}',
                  style: _mono(11, FontWeight.w400)
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          // The verdict, rendered INTO the image: a reviewer never has to
          // recompute a ratio to know whether a token is legal.
          Text(
            floor == null
                ? ratioLabel(ratio)
                : '${ratioLabel(ratio)} / ${floor.toStringAsFixed(1)}',
            style: _mono(12, FontWeight.w700).copyWith(
              color: floor == null
                  ? AppColors.textTertiary
                  : (passes ? AppColors.success : AppColors.error),
            ),
          ),
          const SizedBox(width: AppTheme.spacingXS),
          Icon(
            floor == null
                ? Icons.remove
                : (passes ? Icons.check_circle : Icons.cancel),
            size: 16,
            color: floor == null
                ? AppColors.textTertiary
                : (passes ? AppColors.success : AppColors.error),
          ),
        ],
      ),
    );
  }
}

TextStyle _mono(double size, FontWeight weight) => TextStyle(
      fontFamily: kGoldenFont,
      fontSize: size,
      fontWeight: weight,
      color: AppColors.textPrimary,
    );

String _hex(Color c) {
  String h(double v) =>
      (v * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${h(c.r)}${h(c.g)}${h(c.b)}';
}
