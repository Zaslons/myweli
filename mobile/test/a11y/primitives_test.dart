import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/text_styles.dart';

import '../support/fonts.dart';
import '_a11y.dart';

/// The gate's own gates (A12).
///
/// Every assertion in `_a11y.dart` is applied across the width matrix, where it
/// is expected to be **green**. Green is the right answer there and a useless
/// one here: a helper that cannot fail is indistinguishable from a helper that
/// passes, and this repo has shipped four of those in one commit (§21 row 41).
///
/// So each primitive gets one subject built to break it and one built not to.
/// A11's mutations proved the *fixes*; these prove the *instruments*.
void main() {
  setUpAll(loadRealFonts);

  // ---- expectNoVerticalClip ------------------------------------------------

  group('expectNoVerticalClip', () {
    testWidgets('fails on a fixed height that cuts the text off',
        (tester) async {
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
        reason: 'a 20dp box around three lines is the defect this exists for; '
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

    testWidgets('ignores a laid-out branch that is never painted',
        (tester) async {
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
    testWidgets('fails when a flexed label is squeezed to a few characters',
        (tester) async {
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
        reason: 'the label has ~30dp here. If this passes, the threshold is '
            'not measuring anything',
      );
    });

    testWidgets('ignores a flexed label that FITS — the CommunePill case',
        (tester) async {
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

    testWidgets('ignores a multi-line label that uses both its lines',
        (tester) async {
      // The false positive this primitive shipped with for one commit: the
      // predicate measured a SINGLE line, so a `maxLines: 2` header showing ~14
      // characters across two was reported as showing 7 and called a crush.
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
              SizedBox(width: 40, child: Icon(Icons.verified)),
            ],
          ),
        ),
      );
      expectNoLegibilityCrush(tester);
    });
  });
}
