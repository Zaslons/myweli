import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/widgets/common/app_chip.dart';

import '../support/pump_app.dart';
import '../support/wcag.dart';

/// docs/design/hygiene-batch9.md §2.7.4 (B9.8 F3, Q16–Q18) — the chip
/// SYSTEM.md §11.3 specified: filled when chosen, outlined otherwise, tinted
/// for a status, `radiusPill`.
void main() {
  Future<void> pump(WidgetTester tester, Widget chip) => pumpApp(
    tester,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: chip),
    ),
  );

  group('AppChip.choice', () {
    testWidgets('chosen: filled primary, a white label and the ✓ (Q16)', (
      tester,
    ) async {
      await pump(
        tester,
        AppChip.choice(label: 'Wave', selected: true, onSelected: (_) {}),
      );
      final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
      expect(chip.selected, isTrue);
      expect(chip.showCheckmark, isTrue);
      final theme = Theme.of(tester.element(find.byType(ChoiceChip))).chipTheme;
      expect(chip.selectedColor ?? theme.selectedColor, AppColors.primary);
      expect(chip.labelStyle, isNull, reason: 'the theme draws the label');
      expect(chip.backgroundColor, isNull, reason: 'the theme draws the fill');
      expect(chip.shape, isNull, reason: 'radiusPill is the theme\'s');
    });

    testWidgets('said « selected », and the tap chooses', (tester) async {
      final handle = tester.ensureSemantics();
      bool? chosen;
      await pump(
        tester,
        AppChip.choice(
          label: 'Orange Money',
          selected: false,
          onSelected: (v) => chosen = v,
        ),
      );
      expect(
        tester.getSemantics(find.text('Orange Money')),
        isSemantics(
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.text('Orange Money'));
      expect(chosen, isTrue);
      handle.dispose();
    });

    testWidgets('a target of 48 (SYSTEM §13.2)', (tester) async {
      await pump(
        tester,
        AppChip.choice(label: '1 h', selected: false, onSelected: (_) {}),
      );
      expect(tester.getSize(find.byType(ChoiceChip)).height, 48);
    });

    testWidgets('an icon leads; chosen, the ✓ takes its place (Q16)', (
      tester,
    ) async {
      Future<ChoiceChip> chip({required bool selected}) async {
        await pump(
          tester,
          AppChip.choice(
            label: 'Barbier',
            icon: Icons.content_cut,
            selected: selected,
            onSelected: (_) {},
          ),
        );
        return tester.widget<ChoiceChip>(find.byType(ChoiceChip));
      }

      final idle = await chip(selected: false);
      expect((idle.avatar! as Icon).icon, Icons.content_cut);
      // Material paints its check OVER an avatar: kept, the icon showed
      // through and no ✓ could be seen.
      final chosen = await chip(selected: true);
      expect(chosen.avatar, isNull);
      expect(chosen.showCheckmark, isTrue);
    });
  });

  group('AppChip.tag and AppChip.action', () {
    testWidgets('a tag: outlined, and nothing to do', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, const AppChip.tag(label: 'VIP'));
      expect(
        tester
            .getSemantics(find.text('VIP'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('an action: a button that acts', (tester) async {
      var taps = 0;
      await pump(
        tester,
        AppChip.action(
          label: '+ Tags',
          icon: Icons.add,
          onPressed: () => taps++,
        ),
      );
      await tester.tap(find.text('+ Tags'));
      expect(taps, 1);
    });
  });

  group('AppChip.status — one tinted pill (Q18)', () {
    for (final (tone, label) in [
      (AppChipTone.success, AppColors.success),
      (AppChipTone.warning, AppColors.warning),
      (AppChipTone.error, AppColors.error),
      (AppChipTone.info, AppColors.info),
      (AppChipTone.neutral, AppColors.textSecondary),
      (AppChipTone.strong, AppColors.textPrimary),
      // Gold is a state, never a text (B7.1): its label is ink.
      (AppChipTone.gold, AppColors.textPrimary),
    ]) {
      testWidgets('$tone: its 12% tint, its label, and ≥ 4.5:1 on the page', (
        tester,
      ) async {
        await pump(tester, AppChip.status(label: 'Confirmé', tone: tone));
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(AppChip),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final d = box.decoration as BoxDecoration;
        expect(d.borderRadius, BorderRadius.circular(AppTheme.radiusPill));
        final text = tester.widget<Text>(find.text('Confirmé'));
        expect(text.style!.color, label);
        // The tint over the page — the worse of the two surfaces it sits on.
        final tint = Color.alphaBlend(d.color!, AppColors.background);
        expect(contrastRatio(label, tint), greaterThanOrEqualTo(4.5));
        expect(d.color!.a, closeTo(0.12, 0.005));
      });
    }

    testWidgets('a label for a screen reader, no action', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        const AppChip.status(label: 'Annulé', tone: AppChipTone.error),
      );
      final node = tester.getSemantics(find.text('Annulé'));
      expect(node.label, 'Annulé');
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });
}
