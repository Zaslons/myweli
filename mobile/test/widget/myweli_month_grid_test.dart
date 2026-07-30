import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/widgets/common/myweli_month_grid.dart';

/// What the shared month grid guarantees, as opposed to what the pickers built
/// on it happen to render (A14c, §16).
///
/// **Why this file exists at all.** A14b extracted the grid so three surfaces
/// could compose it, and A14c is the slice that adds the third. Everything
/// asserting anything about it until now went through
/// `myweli_date_picker_test.dart` — i.e. through a *page*. The grid's own
/// contract had no subject, which is how §16's three defects survived being
/// read past twice.
void main() {
  // `weekdayInitials()` and every cell's semantics label ask `intl` for French
  // names, and a bare widget test has no locale data.
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  /// Pumps one month at [scaler] and returns the tester, ready to measure.
  Future<void> pumpMonth(
    WidgetTester tester, {
    required TextScaler scaler,
    DateTime? selected,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Material(
            child: SingleChildScrollView(
              child: MyweliMonthGrid(
                month: DateTime(2026, 3),
                selectedDay: selected,
                onDayTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The height Flutter actually gives one day number at [scaler] — measured
  /// from a bare `Text`, not computed, because the computation is the thing
  /// under test.
  Future<double> lineHeightOf(WidgetTester tester, TextScaler scaler) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: Text('15', style: AppTextStyles.bodyLarge)),
        ),
      ),
    );
    return tester.getSize(find.text('15')).height;
  }

  /// The painted cell box — the `DecoratedBox` `Container` builds inside its
  /// margin, so this is `_cellHeight` itself rather than the cell plus gutters.
  double cellHeightOf(WidgetTester tester, String day) => tester
      .getSize(
        find
            .ancestor(of: find.text(day), matching: find.byType(DecoratedBox))
            .first,
      )
      .height;

  group('§16.1 — the cell holds its line at ANY text scale, not just linear', () {
    testWidgets('linear 2× — green today, and that is the problem', (
      tester,
    ) async {
      const scaler = TextScaler.linear(2);
      final line = await lineHeightOf(tester, scaler);
      await pumpMonth(tester, scaler: scaler);

      expect(
        cellHeightOf(tester, '15'),
        greaterThanOrEqualTo(line + AppTheme.spacingS),
        reason:
            'the whole existing instrument — layout_test.dart 3 widths × 2 '
            'scales, date_picker_test, both goldens — uses TextScaler.linear, '
            'and under a linear scaler scale(a × b) == scale(a) × b. This '
            'assertion passes before and after the fix, by construction. It is '
            'here so the next reader can see that it CANNOT be the gate.',
      );
    });

    testWidgets('non-linear — the cell is short of the line it must hold', (
      tester,
    ) async {
      const scaler = _NonLinearScaler();
      final line = await lineHeightOf(tester, scaler);
      await pumpMonth(tester, scaler: scaler);
      final cell = cellHeightOf(tester, '15');

      // The contract `_cellHeight`'s own docstring states: "the scaled line
      // plus breathing room".
      expect(
        cell,
        greaterThanOrEqualTo(line + AppTheme.spacingS),
        reason:
            '_cellHeight computes scale(fontSize × height) — scale(24) for '
            'bodyLarge — but Flutter\'s line box is scale(fontSize) × height, '
            'i.e. scale(16) × 1.5. TextScaler does not promise linearity; that '
            'is the entire reason it replaced the old textScaleFactor double. '
            'Under any non-linear platform curve the two diverge and the cell '
            'under-provisions.',
      );

      // And the user-visible half: the number must not paint outside its cell.
      expect(
        cell,
        greaterThanOrEqualTo(line),
        reason:
            'short of even the bare line, the day number paints outside the '
            'cell and overlaps the week above and below — `Container` does not '
            'clip, so this is overlap rather than truncation and no overflow '
            'banner would appear',
      );
    });
  });

  group('§16.2 — a chosen day is painted chosen', () {
    testWidgets('the selected day reports isSelected to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpMonth(
        tester,
        scaler: TextScaler.noScaling,
        selected: DateTime(2026, 3, 15),
      );

      expect(
        tester.getSemantics(
          find
              .ancestor(of: find.text('15'), matching: find.byType(Semantics))
              .first,
        ),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          label: 'dimanche 15 mars 2026',
        ),
        reason:
            'A14a shipped selection with no assertion on it: the six tests in '
            'myweli_date_picker_test cover tap→pop, dismiss→null, '
            'out-of-range-inert, clamping, the year jump and the today label — '
            'not this. §17.1 changes the selection parameter\'s TYPE, and a '
            'migration that painted nothing selected would have left every one '
            'of them green.',
      );

      // Falsifiability (§21 row 67: six helpers shipped unable to fail). The
      // same tree with nothing selected must NOT satisfy the matcher above.
      await pumpMonth(tester, scaler: TextScaler.noScaling);
      expect(
        tester.getSemantics(
          find
              .ancestor(of: find.text('15'), matching: find.byType(Semantics))
              .first,
        ),
        isNot(
          matchesSemantics(
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            isEnabled: true,
            hasEnabledState: true,
            hasTapAction: true,
            label: 'dimanche 15 mars 2026',
          ),
        ),
        reason:
            'the assertion above must be able to fail — otherwise it certifies '
            'nothing about selection, only that a cell exists',
      );
      handle.dispose();
    });
  });
}

/// A text scaler that is **not a multiplication**.
///
/// This is a model of one property, not a transcription of a vendor curve, and
/// the distinction matters for what the gate above is allowed to claim. The
/// claim is *not* "Android 14 produces these numbers". It is that
/// `TextScaler.scale` is a **function**, not a factor — which is the entire
/// reason Flutter deprecated `textScaleFactor` in its favour — and that
/// `_cellHeight` multiplies before scaling as though it were a factor.
///
/// Platforms really do this: Android 14's non-linear font scaling compresses
/// large sizes so headlines do not run away while body text still grows. The
/// shape below (grow small text hard, flatten above `bodyLarge`'s 16sp) is that
/// behaviour exaggerated until the arithmetic error is unambiguous rather than
/// a rounding difference:
///
///   Flutter needs  scale(16) × 1.5 = 48 × 1.5 = **72.0**
///   the grid gives max(48, scale(24) + 4) = max(48, 57.6 + 4) = **61.6**
///
/// — a 10.4dp shortfall, i.e. the day number painting over its neighbours.
class _NonLinearScaler extends TextScaler {
  const _NonLinearScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 16 ? fontSize * 3 : 48 + (fontSize - 16) * 1.2;

  /// Only consulted by code that still thinks in factors — which, after this
  /// slice, `_cellHeight` no longer does.
  @override
  double get textScaleFactor => 3;
}
