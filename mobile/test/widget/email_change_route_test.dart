import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/router/app_router.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/screens/profile/email_change_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';

/// The consumer router's OWN « Changer d’adresse e-mail » route (B16.3b,
/// account-email-change.md §5.4): `route_literals_test` proves the pushed
/// paths exist; this proves what the route builds from them — « Vérifier »'s
/// `?verifier=1` is the screen's [EmailChangeScreen.verifyCurrent], and
/// « Modifier »'s bare path is not. The screen tests mount their own router.
void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    serviceLocator.authService = MockAuthService();
  });

  GoRoute realRoute() {
    GoRoute? found;
    void walk(List<RouteBase> routes) {
      for (final r in routes) {
        if (r is GoRoute && r.name == 'profile-edit-email') found = r;
        walk(r.routes);
      }
    }

    walk(AppRouter.router.configuration.routes);
    expect(found, isNotNull, reason: 'the consumer router lost the route');
    expect(found!.path, 'email');
    return found!;
  }

  Future<EmailChangeScreen> built(WidgetTester tester, String query) async {
    late final AuthProvider auth;
    await tester.runAsync(() async {
      auth = AuthProvider();
      for (var i = 0; i < 60 && auth.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    final router = GoRouter(
      initialLocation: '/profile/edit/email$query',
      routes: [
        GoRoute(
          path: '/profile/edit',
          builder: (_, _) => const SizedBox(),
          routes: [realRoute()],
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        providers: [ChangeNotifierProvider<AuthProvider>.value(value: auth)],
        routerConfig: router,
      ),
    );
    await tester.pump();
    return tester.widget<EmailChangeScreen>(find.byType(EmailChangeScreen));
  }

  testWidgets('« Modifier »: the change screen, not a verification', (
    tester,
  ) async {
    expect((await built(tester, '')).verifyCurrent, isFalse);
  });

  testWidgets('« Vérifier » (?verifier=1): the verification', (tester) async {
    expect((await built(tester, '?verifier=1')).verifyCurrent, isTrue);
  });
}
