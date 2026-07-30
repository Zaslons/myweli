import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/widgets/common/app_button.dart';
import 'package:myweli/widgets/common/empty_state.dart';

import '../support/fonts.dart';
import '_a11y.dart';

/// A button's label fits the button (A11 C8).
///
/// ## The device found this, and it is worth saying why nothing else did
///
/// `AppButton` put its label in a `Row` as a **non-flex** child, and a Row lays
/// those out with an unbounded main-axis constraint. So the `Text` measured its
/// full intrinsic width and the Row overflowed rather than the label shrinking.
///
/// Nothing already in this repo could see it:
///
/// * `layout_test.dart` has nine subjects and the pro **journal** is not one of
///   them — the screen where it was found.
/// * `expectNoUndeclaredTruncation` walks `RenderParagraph`s, and this
///   paragraph is not truncated: it is drawn at its full width, past the edge
///   of its parent. The paragraph is fine. The Row around it is not.
/// * The striped « RIGHT OVERFLOWED BY » banner is **debug-only**. In the
///   release build users install, the label is just cut off, silently.
///
/// It took running the pro app on a 360dp Android emulator at 200% text —
/// A11's floor, on the device class the PRD names — and looking at it.
void main() {
  setUpAll(loadRealFonts);

  /// Every non-null `actionText` in `lib/` — `grep -rn 'actionText:' lib/`.
  ///
  /// Listed rather than discovered, because the strings ARE the subject here: a
  /// test that globbed them would go quietly green the day the last one is
  /// deleted, and two of these are the strings that were wrong.
  const labels = <String>[
    '+ Ajouter un client',
    'Inviter un membre',
    'Réessayer',
    // 32px past the right edge at 360×2× before this slice.
    '+ Nouveau rendez-vous',
    // 65px past it — the worst in the app.
    'Voir toutes les communes',
  ];

  RenderParagraph paragraphOf(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text(text), matching: find.byType(RichText)),
      );

  for (final scale in [1.0, 2.0]) {
    for (final label in labels) {
      testWidgets('« $label » fits a 360dp screen at ${scale}x', (
        tester,
      ) async {
        await pumpAtWidth(
          tester,
          width: 360,
          scale: scale,
          home: Scaffold(
            body: EmptyState(
              icon: Icons.event_busy,
              title: 'Aucun rendez-vous ce jour',
              actionText: label,
              onAction: _noop,
            ),
          ),
        );

        // **The label fits inside its button.** This is the assertion, and the
        // obvious one — `button.right <= 360` — is NOT: `EmptyState` centres
        // the button inside `Padding(spacingXL)`, so its rect is ≤296dp wide
        // and centred no matter what the label does. It cannot fail, before or
        // after the fix.
        //
        // The defect was a `RenderFlex` overflow *inside* the button: the Row
        // still reports `constraints.constrain(...)` as its size, so the button
        // never left the screen — the paragraph left the BUTTON. That is what
        // is measured here.
        final button = tester.getSize(find.byType(ElevatedButton));
        final para = paragraphOf(tester, label);
        expect(
          para.size.width,
          lessThanOrEqualTo(button.width),
          reason:
              '« $label » is ${para.size.width.toStringAsFixed(1)}dp wide '
              'inside a ${button.width.toStringAsFixed(1)}dp button, so it is '
              'painted outside the control. In debug that is a striped banner; '
              'in the release build users install, it is silently clipped.',
        );

        // All of it is there — a fit achieved by ellipsis is not a fit.
        //
        // `didExceedMaxLines` alone does NOT say that: it is false whenever
        // `maxLines` is null, which it is here. So adding
        // `overflow: TextOverflow.ellipsis` — one of the two wrong fixes the
        // test below forbids — would leave it green, and
        // `expectNoUndeclaredTruncation` skips declared ellipsis by design.
        // Assert the render object's overflow directly.
        expect(
          para.overflow,
          isNot(TextOverflow.ellipsis),
          reason:
              '« $label » is set to ellipsize. A control has to say what '
              'it does; §13.3 allows a control label to WRAP, not to be cut.',
        );
        expect(
          para.didExceedMaxLines,
          isFalse,
          reason: '« $label » is truncated. A control has to say what it does.',
        );

        // …and it wraps between words, never inside one (§13.3).
        expectNoMidWordBreak(tester, label, '360dp @${scale}x');
      });
    }
  }

  testWidgets('the long label WRAPS — it is not shrunk to fit', (tester) async {
    // The other two ways to make this overflow go away are `FittedBox` and
    // `overflow: ellipsis`, and both are worse: §13.3 sets a floor on type SIZE,
    // and « Voir toutes les communes » is a control whose meaning is the whole
    // sentence. This pins the choice, so swapping Flexible for either goes red.
    await pumpAtWidth(
      tester,
      width: 360,
      scale: 2,
      home: const Scaffold(
        body: EmptyState(
          icon: Icons.location_city,
          title: 'Aucun salon',
          actionText: 'Voir toutes les communes',
          onAction: _noop,
        ),
      ),
    );
    final p = paragraphOf(tester, 'Voir toutes les communes');
    // One line, at this paragraph's own style and scaler — so the comparison
    // below is "taller than one line", not a guess at a pixel count.
    final oneLine = (TextPainter(
      text: TextSpan(text: 'Voir', style: p.text.style),
      textDirection: TextDirection.ltr,
      textScaler: p.textScaler,
    )..layout()).height;
    expect(
      p.size.height,
      greaterThan(oneLine * 1.5),
      reason:
          'the label is ${p.size.height.toStringAsFixed(1)}dp tall and one '
          'line is ${oneLine.toStringAsFixed(1)} — so it rendered on a SINGLE '
          'line inside a 360dp screen at 200% text, where it needs 329dp of a '
          '~280dp box. That means it is being scaled down, not wrapped.',
    );
  });

  // ---- what an unbounded width does to a flexible label ------------------
  //
  // A `Row` hands a NON-flex child an unbounded main-axis constraint, and
  // `RenderFlex` will not distribute an infinite space among flex children. So
  // making the label flexible put a condition on where a button may live — and
  // the exact condition matters, because the first version of it written down
  // here was wrong in both directions. It is measured, not reasoned about.
  //
  // `InvitationCard` is the one call site that was on the wrong side of it:
  // « Refuser » sits beside an `Expanded` « Rejoindre », i.e. unbounded. Six
  // widget tests went red the moment the label changed.

  Future<void> pumpInUnboundedRow(WidgetTester tester, Widget button) =>
      pumpAtWidth(
        tester,
        width: 360,
        scale: 2,
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(
                child: AppButton(text: 'Rejoindre', onPressed: _noop),
              ),
              const SizedBox(width: AppTheme.spacingM),
              button,
            ],
          ),
        ),
      );

  testWidgets('an intrinsic-width button survives an unbounded slot', (
    tester,
  ) async {
    // min + FlexFit.loose is what `isFullWidth: false` selects, and RenderFlex
    // permits exactly that under an unbounded main axis — it is the fix the
    // assertion text itself recommends. This is the InvitationCard shape as it
    // now ships.
    await pumpInUnboundedRow(
      tester,
      const AppButton(
        text: 'Refuser',
        type: AppButtonType.text,
        isFullWidth: false,
        onPressed: _noop,
      ),
    );
    // **Only « Rejoindre » is a meaningful subject here**, and the asymmetry is
    // the whole point of the test. « Refuser » is the NON-flex child, so the
    // Row hands it an unbounded width and its paragraph is laid out at full
    // intrinsic width — which is ≥ its widest word by definition. Asserting
    // `expectNoMidWordBreak` on it is arithmetically guaranteed, i.e. green
    // about nothing. « Rejoindre » is inside `Expanded`, where the squeeze
    // actually happens.
    expectNoMidWordBreak(tester, 'Rejoindre', 'the InvitationCard row @2x');

    // And the row as a whole stays on the screen. `Refuser` taking its
    // intrinsic width is exactly what could push it off.
    final row = tester.getRect(find.byType(Row).first);
    expect(
      row.right,
      lessThanOrEqualTo(360.0),
      reason:
          'the action row runs to ${row.right}dp on a 360dp screen — the '
          'unbounded child took more than what was left',
    );
    expect(find.text('Refuser'), findsOneWidget);
  });

  // The other half of the rule — `isFullWidth: true` in an unbounded slot — is
  // NOT pinned here, and deliberately so. It fails by assertion during layout,
  // which cascades: the surrounding subtree then throws "RenderBox was not laid
  // out" for every descendant, and `flutter_test` collapses the lot into a
  // single « Multiple exceptions (17) » aggregate that no matcher can read.
  //
  // It does not need a pin. A call site on the wrong side of it takes its own
  // screen's tests down instantly and unmissably — that is precisely how the
  // one offender was found, six red tests in `pro_invitations_screen_test.dart`
  // the moment the label became flexible. The rule is on `AppButton`'s doc.

  testWidgets('an intrinsic-width button still shrink-wraps when it fits', (
    tester,
  ) async {
    // The regression `Flexible` could plausibly have caused: `isFullWidth:
    // false` means "be as wide as your label", and a flex child that took the
    // whole row would quietly turn every intrinsic button into a full-width one
    // — a layout change on six screens that no other test would notice.
    await pumpAtWidth(
      tester,
      width: 360,
      scale: 1,
      home: const Scaffold(
        body: Center(
          child: AppButton(
            text: 'Réessayer',
            isFullWidth: false,
            onPressed: _noop,
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(ElevatedButton)).width,
      lessThan(360 * 0.6),
      reason:
          '« Réessayer » is one short word and its button should be short. '
          'A full-width button here means Flexible is behaving like Expanded.',
    );
  });
}

void _noop() {}
