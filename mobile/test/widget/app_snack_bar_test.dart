import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/widgets/common/app_snack_bar.dart';

import '../support/pump_app.dart';

/// A6 — the single feedback entry point (SYSTEM.md §15, §21 row 17).
///
/// Before A6 there were 117 hand-built snackbar calls: 2s ×15, 1s ×4 and
/// Material's 4s default ×99 — §15's 3/6/10s appeared NOWHERE — and the tone
/// was picked per call site, which is how 30 of 61 errors ended up not red.
void main() {
  final key = GlobalKey<ScaffoldMessengerState>();

  Future<void> pumpHost(WidgetTester tester) => tester.pumpWidget(
        wrapApp(scaffoldMessengerKey: key, home: const Scaffold()),
      );

  /// Mount the bar and let its 250ms entrance finish, without `pumpAndSettle`
  /// (an infinite Lottie elsewhere in the app makes that unusable — the house
  /// rule).
  Future<void> settleIn(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('the kind is the API (§15)', () {
    for (final (kind, color, icon, seconds)
        in <(SnackKind, Color, IconData, int)>[
      (SnackKind.success, AppColors.success, Icons.check_circle_outline, 3),
      (SnackKind.info, AppColors.textPrimary, Icons.info_outline, 3),
      (SnackKind.error, AppColors.error, Icons.error_outline, 6),
    ]) {
      testWidgets('${kind.name}: colour, ${seconds}s, and the glyph',
          (tester) async {
        await pumpHost(tester);
        AppSnackBar.showOn(key.currentState!, 'Message', kind: kind);
        await settleIn(tester);

        final bar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(bar.backgroundColor, color);
        expect(bar.duration, Duration(seconds: seconds));
        // §13.6: success (#2D5016) and error (#8B0000) are the same shade in
        // greyscale — the glyph is the second cue, not decoration.
        expect(find.byIcon(icon), findsOneWidget);
      });
    }
  });

  testWidgets('the error really stays 6s — a duration you can measure',
      (tester) async {
    // The field assertion above proves what we ASKED for; this proves what the
    // messenger does. They are not the same claim.
    await pumpHost(tester);
    AppSnackBar.showOn(key.currentState!, 'Échec', kind: SnackKind.error);
    await settleIn(tester);

    await tester.pump(const Duration(milliseconds: 5500));
    expect(find.text('Échec'), findsOneWidget, reason: 'still up before 6s');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400)); // the exit
    expect(find.text('Échec'), findsNothing);
  });

  group('the action (§15, as amended by A6)', () {
    testWidgets('the only route back → 10s, and tapping it fires + closes',
        (tester) async {
      var undone = false;
      await pumpHost(tester);
      AppSnackBar.showOn(
        key.currentState!,
        'Photo supprimée',
        kind: SnackKind.success,
        action: SnackAction(label: 'Annuler', onPressed: () => undone = true),
      );
      await settleIn(tester);

      // The action wins over the kind's own 3s: the user needs time to reach it.
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        kSnackActionDuration,
      );

      await tester.tap(find.text('Annuler'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(undone, isTrue);
      expect(find.text('Photo supprimée'), findsNothing);
    });

    testWidgets(
        'when the SCREEN is the undo (a heart), the kind keeps its duration',
        (tester) async {
      // A6's §15 amendment: 10s of occlusion on a routine heart tap is a cost
      // with no benefit — the filled/outlined heart is already a one-tap undo.
      await pumpHost(tester);
      AppSnackBar.showOn(
        key.currentState!,
        'Ajouté aux favoris',
        kind: SnackKind.success,
        action: SnackAction(
          label: 'Annuler',
          onPressed: () {},
          isOnlyRouteBack: false,
        ),
      );
      await settleIn(tester);

      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 3),
      );
    });
  });

  testWidgets('outcome() picks the tone so a call site cannot get it wrong',
      (tester) async {
    await pumpHost(tester);
    AppSnackBar.outcomeOn(
      key.currentState!,
      ok: false,
      success: 'Enregistré',
      error: 'Échec de l’enregistrement',
    );
    await settleIn(tester);

    expect(find.text('Échec de l’enregistrement'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
      AppColors.error,
    );
  });

  testWidgets('the newest message REPLACES the old one — it never queues',
      (tester) async {
    // Mirrors the web's useToast: a re-show resets the timer. Queueing behind a
    // 6s error would show stale feedback after the user has moved on.
    await pumpHost(tester);
    AppSnackBar.showOn(key.currentState!, 'Premier', kind: SnackKind.error);
    await tester.pump();
    AppSnackBar.showOn(key.currentState!, 'Second', kind: SnackKind.success);
    await settleIn(tester);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Premier'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });
}
