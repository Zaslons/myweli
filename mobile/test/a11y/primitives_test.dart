import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/text_styles.dart';

import '../support/fonts.dart';
import '_a11y.dart';

/// The gate's own gates (A12).
///
/// Every assertion in `_a11y.dart` is applied across the width matrix, where it
/// is expected to be **green**. Green is the right answer there and a useless
/// one here: a helper that cannot fail is indistinguishable from a helper that
/// passes, and this repo shipped six of those in a single slice (§21 row 67).
///
/// So each primitive gets one subject built to break it and one built not to.
/// A11's mutations proved the *fixes*; these prove the *instruments*.
void main() {
  setUpAll(loadRealFonts);

  // ---- expectNoVerticalClip ------------------------------------------------

  group('expectNoVerticalClip', () {
    testWidgets('fails on a fixed height that cuts the text off', (
      tester,
    ) async {
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 1,
        // 20dp around three lines of `bodyLarge` — the shape §13.3 forbids by
        // name: "a box that contains text may not have a fixed height".
        home: const Scaffold(
          body: SizedBox(
            height: 20,
            child: Text(
              'Les paiements encaissés sur cette période apparaîtront ici, '
              'dès que le salon aura encaissé un acompte.',
              style: AppTextStyles.bodyLarge,
            ),
          ),
        ),
      );
      expect(
        () => expectNoVerticalClip(tester),
        throwsA(isA<TestFailure>()),
        reason:
            'a 20dp box around three lines is the defect this exists for; '
            'if it passes, the sweep is decoration',
      );
    });

    testWidgets('passes when the box can grow', (tester) async {
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 1,
        home: Scaffold(
          // The §13.3 answer: a MINIMUM, which the text may exceed.
          // (`ConstrainedBox` is not a const constructor — its assert calls a
          // method — so this subtree cannot be `const`.)
          body: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 20),
            child: const Text(
              'Les paiements encaissés sur cette période apparaîtront ici, '
              'dès que le salon aura encaissé un acompte.',
              style: AppTextStyles.bodyLarge,
            ),
          ),
        ),
      );
      expectNoVerticalClip(tester);
    });

    testWidgets('ignores a laid-out branch that is never painted', (
      tester,
    ) async {
      // `IndexedStack` lays every child out at its own size and paints one.
      // `DropdownButton` builds all its items that way, which is how the three
      // form dropdowns first reported « Institut de manucure » clipped into a
      // 48dp box — true of a copy no user can see. Without `_isPainted` this
      // test fails, and the gate reports a defect that is not there.
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 1,
        home: const Scaffold(
          body: SizedBox(
            // 30dp: one line of `bodyLarge` is 24, so the VISIBLE child fits
            // and only the hidden one would report a clip. (At 20 the visible
            // child is clipped too, and the test passes for the wrong reason —
            // which is what it did first.)
            height: 30,
            child: IndexedStack(
              index: 0,
              children: [
                Text('court', style: AppTextStyles.bodyLarge),
                Text(
                  'Une phrase bien plus longue qui ne tiendrait jamais dans '
                  'vingt pixels de hauteur, et que personne ne voit.',
                  style: AppTextStyles.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      );
      expectNoVerticalClip(tester);
    });
  });

  // ---- expectNoLegibilityCrush ---------------------------------------------

  group('expectNoLegibilityCrush', () {
    testWidgets('fails when a flexed label is squeezed to a few characters', (
      tester,
    ) async {
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 1,
        home: const Scaffold(
          body: Row(
            children: [
              Expanded(
                child: Text(
                  'Salon Excellence',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall,
                ),
              ),
              // Unflexed and wide: the shape `CompactAppointmentTile` had.
              SizedBox(width: 320, child: Text('chip')),
            ],
          ),
        ),
      );
      expect(
        () => expectNoLegibilityCrush(tester),
        throwsA(isA<TestFailure>()),
        reason:
            'the label has ~30dp here. If this passes, the threshold is '
            'not measuring anything',
      );
    });

    testWidgets('ignores a flexed label that FITS — the CommunePill case', (
      tester,
    ) async {
      // The precondition that makes the whole primitive work: a `Flexible` in a
      // `mainAxisSize: min` row lays out at `min(intrinsic, available)`, so a
      // short label is narrow and entirely correct. Only `didExceedMaxLines`
      // separates that from a squeeze.
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 1,
        home: const Scaffold(
          body: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Cocody',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
      expectNoLegibilityCrush(tester);
    });

    testWidgets('ignores a multi-line label that uses both its lines', (
      tester,
    ) async {
      // The false positive this primitive shipped with for one commit: the
      // predicate measured a SINGLE line, so a `maxLines: 2` header showing ~14
      // characters across two was reported as showing 7 and called a crush.
      //
      // **270, not 40** — and the adversarial review is why. At 40 the label
      // gets a 320dp box, « Salon Excellence » fits on one line inside it, so
      // `didExceedMaxLines` is false and `expectNoLegibilityCrush` skips the
      // subject at its first guard: `_prefixFits` was never called, and this
      // test was green against the BUGGY predicate as happily as against the
      // fixed one. A regression test for a predicate that never runs the
      // predicate is §21 row 67's failure with a self-test's name on it.
      //
      // 270 leaves a 90dp box, which is the window that discriminates:
      // « Salon Ex… » is ~112dp on ONE line, so a single-line measurement
      // calls this a crush — and it wraps to « Salon » / « Ex… » well inside
      // 90dp, so the maxLines-aware one correctly does not.
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 1,
        home: const Scaffold(
          body: Row(
            children: [
              Expanded(
                child: Text(
                  'Salon Excellence Beauté',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headlineMedium,
                ),
              ),
              SizedBox(width: 270, child: Icon(Icons.verified)),
            ],
          ),
        ),
      );
      // C — without this the subject may simply not truncate, which is exactly
      // how the 40dp version passed.
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Salon Excellence Beauté'))
            .didExceedMaxLines,
        isTrue,
        reason:
            'the fixture does not truncate, so expectNoLegibilityCrush '
            'skips it before `_prefixFits` is ever called',
      );
      expectNoLegibilityCrush(tester);
    });
  });
  group('expectNoMidWordBreak', () {
    // A13. This helper took `tester.renderObject`, which throws
    // "Bad state: Too many elements" the moment its string renders twice — and
    // A13's own subject, « Salon Excellence », renders in the salon header AND
    // in every appointment tile on the same page. A11 C8 had dodged the same
    // edge by picking a string that appears once.
    //
    // Both renderings are here, and they are deliberately opposite: a WIDE
    // one-line tile that truncates, and a NARROW wrapping header that breaks.
    // If the helper checked only the first match it would pass; if it did not
    // skip one-line paragraphs it would red on the tile for the wrong reason.
    testWidgets('checks every rendering, not just the first', (tester) async {
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 1,
        home: const Scaffold(
          body: Column(
            children: [
              // Renders first, cannot break (maxLines: 1), and is wide enough
              // to pass anyway — the decoy.
              SizedBox(
                width: 300,
                child: Text(
                  'Salon Excellence',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall,
                ),
              ),
              // Renders second, wraps, and its box is far narrower than
              // « Excellence » — the real defect.
              SizedBox(
                width: 60,
                child: Text(
                  'Salon Excellence',
                  maxLines: 2,
                  style: AppTextStyles.headlineMedium,
                ),
              ),
            ],
          ),
        ),
      );
      expect(
        () => expectNoMidWordBreak(tester, 'Salon Excellence', '360dp × 1×'),
        throwsA(isA<TestFailure>()),
      );
    });

    // The mirror: a one-line label narrower than its longest word is NOT a
    // mid-word break — it truncates. Reporting it here would duplicate
    // `expectNoLegibilityCrush` and make this helper unusable as a by-name gate.
    testWidgets('ignores a one-line label that truncates instead of breaking', (
      tester,
    ) async {
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 1,
        home: const Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  'Salon Excellence',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headlineMedium,
                ),
              ),
              SizedBox(
                width: 200,
                child: Text(
                  'Salon Excellence',
                  maxLines: 2,
                  style: AppTextStyles.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
      // The 60dp one-liner is skipped; the 200dp wrapping one fits.
      expectNoMidWordBreak(tester, 'Salon Excellence', '360dp × 1×');
    });

    // ...and if EVERY rendering is one-line, the call measured nothing. A
    // helper that returns quietly in that case is §21 row 67's failure mode.
    testWidgets('fails loudly when every rendering is one-line', (
      tester,
    ) async {
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 1,
        home: const Scaffold(
          body: SizedBox(
            width: 60,
            child: Text(
              'Salon Excellence',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.headlineMedium,
            ),
          ),
        ),
      );
      expect(
        () => expectNoMidWordBreak(tester, 'Salon Excellence', '360dp × 1×'),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('expectTokensWhole', () {
    testWidgets('fails when a two-digit day is wider than its box', (
      tester,
    ) async {
      // 20dp around « 20 » at 2×: the shape row 73 measured, reproduced with a
      // `SizedBox` so the failure is arithmetic rather than Material's.
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 2,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 20,
              child: Text('20', style: AppTextStyles.bodyMedium),
            ),
          ),
        ),
      );
      expect(
        () => expectTokensWhole(tester, const ['20'], 'the falsifier'),
        throwsA(isA<TestFailure>()),
        reason:
            'a 20dp box cannot hold « 20 » at 2×. If this passes, the '
            'primitive is measuring nothing and row 67 has a seventh member',
      );
    });

    testWidgets(
      'ignores a day that FITS — the assertion is not "any narrow box"',
      (tester) async {
        await pumpAtWidth(
          tester,
          width: 360,
          scale: 2,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 80,
                child: Text('20', style: AppTextStyles.bodyMedium),
              ),
            ),
          ),
        );
        expectTokensWhole(tester, const ['20'], 'the control');
      },
    );

    testWidgets('fails LOUDLY when the day is not on screen at all', (
      tester,
    ) async {
      // The vacuity guard. A picker that never opened would otherwise sweep
      // nothing and report clean — which is the failure mode `layout_test.dart`
      // calls "the assertion most likely to be deleted".
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 1,
        home: const Scaffold(body: SizedBox.shrink()),
      );
      expect(
        () => expectTokensWhole(tester, const ['20'], 'the empty screen'),
        throwsA(isA<TestFailure>()),
        reason:
            'asserting about days that are not rendered must be an error, '
            'not a pass',
      );
    });
  });
}
