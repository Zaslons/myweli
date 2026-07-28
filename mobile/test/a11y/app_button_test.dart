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
      testWidgets('« $label » fits a 360dp screen at ${scale}x',
          (tester) async {
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

        // The overflow itself. A RenderFlex overflow is a reported FlutterError,
        // so `pumpAtWidth` already dies on it — but assert the button's own box
        // too, because a Row can also "fit" by being clipped to a parent that is
        // itself the wrong size, and that failure is silent.
        final button = tester.getRect(find.byType(ElevatedButton));
        expect(
          button.right,
          lessThanOrEqualTo(360.0),
          reason: 'the button runs to ${button.right}dp on a 360dp screen. '
              'This is what the Android device showed: a label that cannot '
              'shrink pushes the control off the edge, and in release there is '
              'no striped banner to tell anyone.',
        );

        // All of it is there — a fit achieved by ellipsis is not a fit.
        expect(
          paragraphOf(tester, label).didExceedMaxLines,
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
    )..layout())
        .height;
    expect(
      p.size.height,
      greaterThan(oneLine * 1.5),
      reason: 'the label is ${p.size.height.toStringAsFixed(1)}dp tall and one '
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
                  child: AppButton(text: 'Rejoindre', onPressed: _noop)),
              const SizedBox(width: AppTheme.spacingM),
              button,
            ],
          ),
        ),
      );

  testWidgets('an intrinsic-width button survives an unbounded slot',
      (tester) async {
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
    for (final label in ['Rejoindre', 'Refuser']) {
      expect(find.text(label), findsOneWidget, reason: '« $label » vanished');
      expectNoMidWordBreak(tester, label, 'the InvitationCard row, 360dp @2x');
    }
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

  testWidgets('an intrinsic-width button still shrink-wraps when it fits',
      (tester) async {
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
      reason: '« Réessayer » is one short word and its button should be short. '
          'A full-width button here means Flexible is behaving like Expanded.',
    );
  });
}

void _noop() {}
