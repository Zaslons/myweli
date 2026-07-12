import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Team access R3 §2.2 — the login « Invitations » step: an invited email
/// signs in with the NORMAL flow, sees the card instead of « compte
/// introuvable », joins with the proven identity, or declines back to the
/// classic register fallback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
  });

  setUp(() async {
    MockData.resetTeam();
    MockData.providerUsers.removeWhere((p) => p.businessName.isEmpty);
    await serviceLocator.authService.logoutProvider();
  });

  Widget app() {
    final router = GoRouter(
      initialLocation: '/pro/login',
      routes: [
        GoRoute(
          path: '/pro/login',
          builder: (_, __) => const ProLoginScreen(),
        ),
        GoRoute(
          path: '/pro/dashboard',
          builder: (_, __) => const Scaffold(body: Text('DASHBOARD')),
        ),
        GoRoute(
          path: '/pro/register',
          builder: (_, __) => const Scaffold(body: Text('REGISTER')),
        ),
      ],
    );
    return ChangeNotifierProvider(
      create: (_) => ProAuthProvider(),
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// Email login as the seeded invitee up to the invitations step.
  Future<void> reachInvitationsStep(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.enterText(
      find.byType(TextField).first,
      'invitee@myweli.test',
    );
    await tester.pump();
    await tester.tap(find.text('Continuer avec e-mail'));
    await settle(tester);

    await tester.enterText(
      find.byType(TextField).first,
      MockAuthService.demoOtp,
    );
    await tester.pump();
    await tester.tap(find.text('Se connecter'));
    await settle(tester);

    expect(find.text('Vous êtes invité(e)'), findsOneWidget);
  }

  testWidgets(
      'the 202 bridge: the invitations step renders the card '
      'instead of « compte introuvable »', (tester) async {
    await reachInvitationsStep(tester);

    expect(
      find.text('Rejoignez l\'équipe — aucun salon à créer.'),
      findsOneWidget,
    );
    expect(find.textContaining('Salon Excellence'), findsOneWidget);
    expect(find.textContaining('Collaborateur'), findsOneWidget);
    expect(find.text('Rejoindre'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);
    // No error banner, no register CTA on the bridge.
    expect(find.text('Créer un compte'), findsNothing);
  });

  testWidgets(
      '« Rejoindre » authenticates and lands on the dashboard with '
      'the welcome snackbar', (tester) async {
    await reachInvitationsStep(tester);

    await tester.tap(find.text('Rejoindre'));
    await settle(tester);

    expect(
      find.textContaining('Bienvenue dans l\'équipe de Salon Excellence'),
      findsOneWidget,
    );
    await settle(tester);
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets(
      '« Refuser » on the last card falls back to the classic '
      '« Créer un compte » path', (tester) async {
    await reachInvitationsStep(tester);

    await tester.tap(find.text('Refuser'));
    await settle(tester);

    // Back on the options step with the provider_not_found fallback.
    expect(find.text('Vous êtes invité(e)'), findsNothing);
    expect(find.text('Créer un compte'), findsOneWidget);
    expect(find.textContaining('Compte introuvable'), findsOneWidget);
  });

  testWidgets('« Retour » clears the step without touching the invitation',
      (tester) async {
    await reachInvitationsStep(tester);

    await tester.tap(find.text('Retour'));
    await settle(tester);

    expect(find.text('Vous êtes invité(e)'), findsNothing);
    expect(find.text('Continuer avec Google'), findsOneWidget);
    // The invitation is untouched — the owner still sees it pending.
    expect(
      MockData.teamMembers.any((m) => m.id == 'mem_staff1' && m.isPending),
      isTrue,
    );
  });
}
