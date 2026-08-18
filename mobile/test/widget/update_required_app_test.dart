import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/screens/update/update_required_app.dart';

import '../a11y/_a11y.dart';
import '../support/surface.dart';

/// The blocking screen. Its whole job is to be a dead end with exactly one way
/// out, so most of these tests assert the ABSENCE of an escape.
void main() {
  testWidgets('states the block, in French, with one action', (t) async {
    await t.pumpWidget(
      const UpdateRequiredApp(updateUrl: 'https://play.google.com/x'),
    );
    expect(find.text('Mise à jour requise'), findsOneWidget);
    expect(find.textContaining('n’est plus prise en charge'), findsOneWidget);
    expect(find.textContaining('prendre vos rendez-vous'), findsOneWidget);
    expect(find.text('Mettre à jour'), findsOneWidget);
  });

  testWidgets('the pro copy names the pro job', (t) async {
    await t.pumpWidget(
      const UpdateRequiredApp(updateUrl: 'https://play/x', isPro: true),
    );
    expect(find.textContaining('gérer votre salon'), findsOneWidget);
  });

  testWidgets('offers NO way back — no AppBar, no dismiss, no retry', (
    t,
  ) async {
    await t.pumpWidget(const UpdateRequiredApp(updateUrl: 'https://play/x'));
    // An AppBar inside a route paints a back button, and would also drag in
    // §21 row 79's 200%-scale title ellipsis. There is deliberately none.
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    for (final word in const [
      'Plus tard',
      'Continuer',
      'Réessayer',
      'Annuler',
    ]) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  testWidgets('no updateUrl → the same screen with NO button', (t) async {
    // A dead button is worse than none (the web `OpenInAppButton` lesson: an
    // href="#" is a dead link wearing a CTA). The backend refuses to send
    // update_required without a URL, but the screen must not depend on that.
    await t.pumpWidget(const UpdateRequiredApp());
    expect(find.text('Mise à jour requise'), findsOneWidget);
    expect(find.text('Mettre à jour'), findsNothing);
  });

  testWidgets('the button opens the store URL it was given', (t) async {
    String? opened;
    await t.pumpWidget(
      UpdateRequiredApp(
        updateUrl:
            'https://play.google.com/store/apps/details?id=com.myweli.app',
        onOpen: (_, url) => opened = url,
      ),
    );
    await t.tap(find.text('Mettre à jour'));
    await t.pump();
    expect(opened, contains('com.myweli.app'));
  });

  // The a11y floor that matters most here: a user who cannot read or reach this
  // screen cannot act on it, and it is the one screen with no way around.
  //
  // **Which of these can actually fail today, stated rather than assumed.**
  // `takeException` cannot: `EmptyState` wraps its column in a
  // `LayoutBuilder`→`SingleChildScrollView`, so it scrolls rather than
  // overflows — verified by shrinking the viewport to 360×150, which still
  // passed. It stays as a regression guard against a future redesign that
  // drops the scroll, and it is labelled as such rather than left looking like
  // a live check.
  //
  // The two that CAN fail are `expectNoVerticalClip` (text cut by a fixed
  // height — the §13.3 class `takeException` is blind to) and the reachability
  // assertion: the one action on the screen must still be tappable at 2×.
  for (final scale in const [1.0, 2.0]) {
    testWidgets('is readable and actionable at ${scale}x on a floor phone', (
      t,
    ) async {
      t.view.physicalSize = kFloorPhone;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const UpdateRequiredApp(updateUrl: 'https://play/x'),
        ),
      );

      expect(t.takeException(), isNull, reason: 'regression guard only');
      expectNoVerticalClip(t, context: 'the update screen at ${scale}x');

      expect(find.text('Mise à jour requise'), findsOneWidget);
      // Reachable, not merely present: scroll it into view and tap it. On a
      // screen with exactly one way out, an unreachable button is the whole
      // failure.
      await t.scrollUntilVisible(find.text('Mettre à jour'), 100);
      await t.tap(find.text('Mettre à jour'));
      await t.pump();
    });
  }
}
