import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/auth/open_sign_in.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/screens/profile/edit_profile_screen.dart';
import 'package:myweli/screens/profile/profile_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_favorites_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/sign_in.dart';

/// consumer-signin-push.md §2.6 (decision 208) and §2.7: where signing out
/// and deleting the account land — and only once they happened — and
/// Modifier le profil showing whoever signed in over it.
void main() {
  final auth = _Auth();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    serviceLocator
      ..authService = auth
      ..favoritesService = MockFavoritesService();
  });
  setUp(() => auth.failLogout = false);
  tearDown(SignInGate.reset);

  late GoRouter router;

  Future<AuthProvider> pump(
    WidgetTester tester, {
    String at = '/profile',
    bool signedIn = true,
    // A deletion needs an account with no booking ahead: the mock refuses
    // the others, as the API does (409 `future_bookings`).
    String phone = kConsumerPhone,
  }) async {
    late final AuthProvider authProvider;
    if (signedIn) {
      authProvider = await signInConsumer(tester, phoneNumber: phone);
    } else {
      // Signed OUT: an earlier test's session is still on the mock, and
      // AuthProvider restores it as it is built.
      await tester.runAsync(() async {
        await auth.logout();
        authProvider = AuthProvider();
        for (var i = 0; i < 60 && authProvider.isLoading; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
    }
    router = GoRouter(
      initialLocation: at,
      routes: [
        // A Scaffold, as the real Accueil: a snackbar needs one to show.
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('ACCUEIL')),
        ),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        GoRoute(
          path: '/profile/edit',
          builder: (_, _) => const EditProfileScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) => LoginScreen(
            reason: SignInReason.fromKey(state.uri.queryParameters['reason']),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        routerConfig: router,
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ],
      ),
    );
    await settle(tester);
    return authProvider;
  }

  String here() => router.state.uri.toString();

  group('Profil', () {
    testWidgets('a sign-out that happened lands on Accueil, and says it', (
      tester,
    ) async {
      final authProvider = await pump(tester);
      await tester.ensureVisible(find.text('Déconnexion'));
      await tester.tap(find.text('Déconnexion'));
      await tester.pump();
      await tester.tap(find.text('Se déconnecter'));
      await settle(tester);
      expect(authProvider.isAuthenticated, isFalse);
      expect(here(), '/home');
      expect(find.text('Vous êtes déconnecté·e.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a sign-out that failed stays on Profil, signed in, and says '
        'nothing of a sign-out', (tester) async {
      auth.failLogout = true;
      final authProvider = await pump(tester);
      await tester.ensureVisible(find.text('Déconnexion'));
      await tester.tap(find.text('Déconnexion'));
      await tester.pump();
      await tester.tap(find.text('Se déconnecter'));
      await settle(tester);
      expect(authProvider.isAuthenticated, isTrue);
      expect(here(), '/profile');
      expect(find.text('Vous êtes déconnecté·e.'), findsNothing);
    });

    testWidgets('a deletion lands on Accueil with « Compte supprimé »', (
      tester,
    ) async {
      final authProvider = await pump(tester, phone: '+2250102030405');
      await tester.ensureVisible(find.text('Supprimer mon compte'));
      await tester.tap(find.text('Supprimer mon compte'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).last, 'SUPPRIMER');
      await tester.pump();
      await tester.tap(find.text('Supprimer définitivement'));
      await settle(tester);
      expect(authProvider.isAuthenticated, isFalse);
      expect(here(), '/home');
      expect(find.text('Compte supprimé'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  testWidgets('Modifier le profil shows whoever signs in over it — not the '
      'previous account (the independent review of A3)', (tester) async {
    await pump(tester, at: '/profile/edit', signedIn: false);
    expect(
      find.text('Connectez-vous pour modifier votre profil'),
      findsOneWidget,
    );
    await tester.tap(find.text('Se connecter'));
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.text('Continuer avec Google'));
    await settle(tester);
    expect(find.byType(LoginScreen), findsNothing);
    final name = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(name.controller.text, 'Bintou Koné');
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

class _Auth extends MockAuthService {
  bool failLogout = false;

  @override
  Future<void> logout() async {
    if (failLogout) throw StateError('offline');
    await super.logout();
  }

  @override
  Future<ApiResponse<User>> signInWithGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return ApiResponse.success(
      User(
        id: 'u-bintou',
        name: 'Bintou Koné',
        email: 'bintou@test.com',
        phoneNumber: '+2250700000002',
        authProvider: 'google',
        createdAt: DateTime(2026),
      ),
    );
  }
}
