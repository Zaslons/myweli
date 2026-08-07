import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/app_snack_bar.dart';

import '../support/pump_app.dart';
import '../support/surface.dart';

/// A6 — how feedback actually reaches a screen reader (SYSTEM.md §13.4).
///
/// **This file exists because the census got it backwards.** It reported that
/// ~107 of 117 snackbars were "silent to TalkBack/VoiceOver" because only the
/// 6 calls routed through `Helpers.showSnackBar` fired
/// `SemanticsService.sendAnnouncement`. The SDK says otherwise:
///
///   * `material/snack_bar.dart:831` wraps EVERY `SnackBar` in
///     `Semantics(container: true, liveRegion: true)`. A live region announces
///     itself on both platforms, with no help from the app.
///   * `ui/window.dart:986` — `AccessibilityFeatures.supportsAnnounce` is
///     **false on Android**, where the platform discourages direct
///     announcements; `announceForAccessibility` clears TalkBack's queue.
///
/// So the six announcing sites were the anomaly, not the 111 silent ones — on
/// iOS they double-spoke the live region's own text. A6 deleted them and gates
/// the real mechanism here instead.
void main() {
  final key = GlobalKey<ScaffoldMessengerState>();

  Future<void> settleIn(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a snackbar IS a live region — that is the announcement', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      wrapApp(scaffoldMessengerKey: key, home: const Scaffold()),
    );

    AppSnackBar.showOn(
      key.currentState!,
      'Rendez-vous accepté',
      kind: SnackKind.success,
    );
    await settleIn(tester);

    // The node that carries the flag is the one wrapping the CONTENT — the
    // `Semantics(container: true, liveRegion: true)` of snack_bar.dart:831
    // merges the message into itself.
    expect(
      tester.getSemantics(find.text('Rendez-vous accepté')),
      isSemantics(isLiveRegion: true, label: 'Rendez-vous accepté'),
      reason:
          'the live region is the mechanism TalkBack and VoiceOver both '
          'support — and the ONLY one on Android. If this goes red, the app '
          'stopped announcing feedback and no SemanticsService call will fix '
          'it (supportsAnnounce is false there).',
    );
    handle.dispose();
  });

  testWidgets('the action clears the 48px floor (§13.2)', (tester) async {
    await tester.pumpWidget(
      wrapApp(scaffoldMessengerKey: key, home: const Scaffold()),
    );
    AppSnackBar.showOn(
      key.currentState!,
      'Photo supprimée',
      kind: SnackKind.success,
      action: SnackAction(label: 'Annuler', onPressed: () {}),
    );
    await settleIn(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets(
    'a snackbar under an open sheet is PRUNED — feedback belongs inside the '
    'modal',
    (tester) async {
      // `ModalBarrier` renders `BlockSemantics(ExcludeSemantics(…))`, so a bar
      // raised while a sheet is open is invisible to a screen reader AND painted
      // under the scrim (§10). This is the mobile twin of the web's B5 finding
      // (`aria-modal` pruned the toast). A6 converted six such sites to inline
      // in-sheet errors; this gate keeps them converted.
      final handle = tester.ensureSemantics();
      pinSurface(tester, size: const Size(360, 1600));
      await tester.pumpWidget(
        wrapApp(
          scaffoldMessengerKey: key,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const SizedBox(height: 200),
                  ),
                  child: const Text('open sheet'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      AppSnackBar.showOn(
        key.currentState!,
        'Impossible d’ouvrir Wave',
        kind: SnackKind.error,
      );
      await settleIn(tester);

      // It is on screen…
      expect(find.text('Impossible d’ouvrir Wave'), findsOneWidget);
      // …and unreachable by semantics — which is the whole point.
      expect(
        find.bySemanticsLabel('Impossible d’ouvrir Wave'),
        findsNothing,
        reason:
            'BlockSemantics prunes it — so this message must be raised '
            'INSIDE the sheet, not through the messenger',
      );
      handle.dispose();
    },
  );
}
