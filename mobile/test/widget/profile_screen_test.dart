import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/constants/app_constants.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/screens/profile/about_screen.dart';
import 'package:myweli/screens/profile/profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

/// L1 — the consumer profile, and the legal surface it must offer
/// (docs/design/legal-l1.md).
///
/// **This is the screen's first widget test.** `ProfileScreen` has shipped since
/// PR-0 with no coverage of any kind — no widget test, no golden — which is a
/// large part of why its « À propos » row has been rendering a chevron it does
/// not honour, and a hardcoded `'Version 1.0.0'` beside `AppConstants.appVersion`
/// saying the same thing in a second place.
///
/// **Everything here is pumped SIGNED OUT**, and that is the point rather than a
/// convenience: a store reviewer is never signed in. Legal has to be reachable
/// from a logged-out profile, with no `returnTo` bounce to the login screen —
/// which is why « À propos » sits in the always-visible group and not beside
/// « Exporter mes données ».
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    setupDependencyInjection();
  });

  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ],
        routerConfig: GoRouter(
          initialLocation: '/profile',
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, _) => const ProfileScreen(),
            ),
            GoRoute(
              path: '/a-propos',
              builder: (_, _) => const Scaffold(body: Text('À-PROPOS')),
            ),
            GoRoute(path: '/login', builder: (_, _) => const Scaffold()),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets('« À propos » is reachable, signed out', (tester) async {
    await pumpProfile(tester);

    expect(find.text('À propos'), findsOneWidget);
    await tester.tap(find.text('À propos'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(
      find.text('À-PROPOS'),
      findsOneWidget,
      reason: 'the row has rendered a chevron it does not honour since PR-0 — '
          '`onTap` is simply absent (profile_screen.dart:130-134), so it looks '
          'tappable and is not. A store reviewer taps it looking for the '
          'privacy policy.',
    );
  });

  testWidgets('the version comes from one place — on the About screen',
      (tester) async {
    // **The profile row no longer shows a version at all**, and that is the
    // fix: it printed « Version 1.0.0 » as a literal, a second copy of
    // `AppConstants.appVersion`, with `pubspec.yaml` holding a third. The
    // number now lives once, on the screen that is *about* the app.
    //
    // The first draft asserted this on the profile and went red the moment the
    // literal was removed — a test measuring the old shape rather than the
    // rule. Bump the constant and this still goes red, which is the whole
    // point of it being a constant.
    await tester.pumpWidget(wrapApp(home: const AboutScreen()));
    await tester.pump();

    expect(find.textContaining(AppConstants.appVersion), findsOneWidget);
    expect(
      find.text('Version 1.0.0'),
      findsOneWidget,
      reason: 'and it reads as a human expects — the constant interpolated, '
          'not printed raw',
    );
  });

  testWidgets('the About screen offers all four documents', (tester) async {
    await tester.pumpWidget(wrapApp(home: const AboutScreen()));
    await tester.pump();

    for (final title in [
      'Politique de confidentialité',
      'Conditions d’utilisation',
      'Mentions légales',
      'Supprimer mon compte',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '« $title » is missing');
    }
    // Every one leaves the app — there is no in-app copy of a legal document,
    // deliberately (docs/design/legal-l1.md §5: two copies drift, and a user
    // and a regulator would be reading different documents).
    expect(find.byIcon(Icons.open_in_new), findsNWidgets(4));
  });

  testWidgets('signing out does not hide the legal route', (tester) async {
    // The rows that are `if (user != null)` are the account rows. Legal is not
    // one of them, and must never become one: a `returnTo` bounce on a privacy
    // link is a rejected submission.
    await pumpProfile(tester);
    expect(find.text('Exporter mes données'), findsNothing);
    expect(find.text('Supprimer mon compte'), findsNothing);
    expect(find.text('À propos'), findsOneWidget);
    expect(find.text('Aide & Support'), findsOneWidget);
  });
}
