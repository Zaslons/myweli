import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/access/pro_access_guard.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/team_error_messages.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/screens/provider/team/pro_invitations_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/widgets/common/app_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../a11y/_a11y.dart';
import '../support/fonts.dart';
import '../support/pump_app.dart';
import '../support/rejoin.dart';

/// The rejoin gate, as a person meets it (docs/design/pro-rejoin-gate.md §3–4):
/// a former member signs in and finds their invitation instead of being
/// thrown out — or, with none, stays on the sign-in screen under the banner —
/// and every way off the gate: « Rejoindre », « Refuser », « Déconnexion ».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final team = _GateTeam();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts(); // the 200% check measures text
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = MockProService();
    serviceLocator.proTeamService = team;
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    team.acceptAnswer = null;
    await serviceLocator.authService.logoutProvider();
  });

  /// The app's routes the gate leads to — the shells as plain labels.
  GoRouter routerAt(String initial) => GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/pro/login', builder: (_, _) => const ProLoginScreen()),
      GoRoute(
        path: '/pro/invitations',
        builder: (_, _) => const ProInvitationsScreen(),
      ),
      for (final (path, label) in [
        ('/pro/dashboard', 'DASHBOARD'),
        ('/pro/staff', 'STAFF_SHELL'),
        ('/pro/register', 'REGISTER'),
      ])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text(label)),
        ),
    ],
  );

  /// The session navigates on its own (the gate, a sign-out) — on THIS
  /// router, as it does on the app's.
  Widget app() {
    final router = routerAt('/pro/login');
    return wrapApp(
      providers: [
        ChangeNotifierProvider(create: (_) => ProAuthProvider(router: router)),
        ChangeNotifierProvider(create: (_) => ProTeamProvider()),
      ],
      routerConfig: router,
    );
  }

  /// [steps] × 400 ms of fake time: the mock calls chain (login, membership,
  /// invitations, the re-check, the sign-out), each a mock delay.
  Future<void> settle(WidgetTester tester, {int steps = 8}) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> signInByEmail(WidgetTester tester, String email) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, email);
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
  }

  /// Fatou revoked, invited again (as [role]), signing in: the gate.
  Future<void> reachGate(
    WidgetTester tester, {
    TeamRole role = TeamRole.reception,
    String? artistId,
    void Function()? alsoInvite,
  }) async {
    revokeMember(kFatouRow);
    await tester.runAsync(() => reinvite(team, role: role, artistId: artistId));
    alsoInvite?.call();
    await signInByEmail(tester, kFatou);
    expect(find.text('Vous êtes invité(e)'), findsOneWidget);
  }

  const banner = 'Votre accès à ce salon a été retiré.';

  testWidgets('S11 — a revoked account with no invitation stays on the '
      'sign-in screen, the banner shown in place', (tester) async {
    revokeMember(kFatouRow);

    await signInByEmail(tester, kFatou);

    expect(find.text('DASHBOARD'), findsNothing);
    expect(find.text(banner), findsOneWidget);
    // Back on the options — the e-mail code was spent by the sign-in.
    expect(find.text('Continuer avec Google'), findsOneWidget);
    expect(find.text('Se connecter'), findsNothing);
  });

  testWidgets('S1 — a former member re-invited signs in onto « Invitations »: '
      'the card, no way back, « Déconnexion »', (tester) async {
    await reachGate(tester);

    expect(find.text('DASHBOARD'), findsNothing);
    expect(find.textContaining('Salon Excellence'), findsOneWidget);
    expect(find.textContaining('Réception'), findsOneWidget);
    expect(find.text('Rejoindre'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byTooltip('Déconnexion'), findsOneWidget);
    // Signed in from nothing: no salon is known to have been lost, so no
    // banner above another salon's card.
    expect(find.textContaining('a été retiré'), findsNothing);
    expect(find.text('Aucune invitation en attente'), findsNothing);
  });

  testWidgets('S2 — « Rejoindre » as a Collaborateur: the staff shell, and '
      '« Vous avez rejoint Salon Excellence »', (tester) async {
    await reachGate(tester, role: TeamRole.staff, artistId: 'artist2');
    expect(find.textContaining('Collaborateur'), findsOneWidget);

    await tester.tap(find.text('Rejoindre'));
    await settle(tester, steps: 3);

    expect(find.text('STAFF_SHELL'), findsOneWidget);
    expect(find.text('Vous avez rejoint Salon Excellence'), findsOneWidget);
    expect(
      MockData.teamMembers.singleWhere((m) => m.id == kFatouRow).status,
      TeamMemberStatus.active,
    );
  });

  testWidgets('S2 — the seeded former member joins Beauté Divine as '
      'Réception: the dashboard', (tester) async {
    await signInByEmail(tester, 'ancien.membre@myweli.test');
    expect(find.textContaining('Beauté Divine'), findsOneWidget);

    await tester.tap(find.text('Rejoindre'));
    await settle(tester, steps: 3);

    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.text('Vous avez rejoint Beauté Divine'), findsOneWidget);
  });

  testWidgets('S6 — « Refuser » on the last card: signed out, the sign-in '
      'banner, the row revoked again', (tester) async {
    await reachGate(tester);

    await tester.tap(find.text('Refuser'));
    await settle(tester);

    expect(find.text('Espace Pro'), findsWidgets, reason: 'the sign-in');
    expect(find.text(banner), findsOneWidget);
    expect(
      MockData.teamMembers.singleWhere((m) => m.id == kFatouRow).status,
      TeamMemberStatus.revoked,
    );
  });

  testWidgets('S7 — « Refuser » one card of two: the gate stays, with the '
      'other', (tester) async {
    await reachGate(tester, alsoInvite: inviteFromBeauteDivine);
    expect(find.text('Rejoindre'), findsNWidgets(2));

    await tester.tap(find.text('Refuser').first);
    await settle(tester, steps: 3);

    expect(find.text('Vous êtes invité(e)'), findsOneWidget);
    expect(find.textContaining('Beauté Divine'), findsOneWidget);
    expect(find.textContaining('Salon Excellence'), findsNothing);
    expect(find.text(banner), findsNothing);
  });

  testWidgets('S3 → S6 — « Rejoindre » on a card that expired meanwhile: '
      'signed out, the banner, and why', (tester) async {
    await reachGate(tester);
    expireInvitations();

    await tester.tap(find.text('Rejoindre'));
    await settle(tester, steps: 5);

    expect(find.text(banner), findsOneWidget);
    expect(find.text(teamErrorMessage('invitation_expired')), findsOneWidget);
    expect(find.text('Vous êtes invité(e)'), findsNothing);
  });

  testWidgets('S8 — « Déconnexion »: signed out to the sign-in banner', (
    tester,
  ) async {
    await reachGate(tester);

    await tester.tap(find.byTooltip('Déconnexion'));
    await settle(tester, steps: 3);

    expect(find.text(banner), findsOneWidget);
    expect(find.text('Continuer avec Google'), findsOneWidget);
  });

  testWidgets('S4 — « Rejoindre » offline: « Pas de connexion. Réessayez. », '
      'the card stays and answers again', (tester) async {
    await reachGate(tester);
    team.acceptAnswer = ApiResponse.error('Pas de connexion. Réessayez.');

    await tester.tap(find.text('Rejoindre'));
    await settle(tester, steps: 2);

    expect(find.text('Pas de connexion. Réessayez.'), findsOneWidget);
    expect(find.text('Vous êtes invité(e)'), findsOneWidget);
    final rejoin = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Rejoindre'),
    );
    expect(rejoin.onPressed, isNotNull, reason: 'the button answers again');
  });

  testWidgets('S5 — « Rejoindre » refused (forbidden): the invitee\'s '
      'sentence, not the owner\'s', (tester) async {
    await reachGate(tester);
    team.acceptAnswer = ApiResponse.error(
      teamErrorMessage('forbidden'),
      code: 'forbidden',
    );

    await tester.tap(find.text('Rejoindre'));
    await settle(tester, steps: 2);

    expect(find.text('Invitation impossible à accepter.'), findsOneWidget);
    expect(find.text(teamErrorMessage('forbidden')), findsNothing);
    expect(find.text('Vous êtes invité(e)'), findsOneWidget);
  });

  /// Fatou, signed in and working, revoked and invited again — the guard's
  /// probe holds her on the gate. Built in real async (the mock delays),
  /// then mounted where the session already sent its router.
  Future<(ProAuthProvider, GoRouter)> gatedMidSession(
    WidgetTester tester,
  ) async {
    final router = routerAt('/pro/dashboard');
    late ProAuthProvider auth;
    await tester.runAsync(() async {
      final mock = serviceLocator.authService as MockAuthService;
      await mock.requestProviderEmailOtp(kFatou);
      await mock.verifyProviderEmailOtp(kFatou, MockAuthService.demoOtp);
      auth = ProAuthProvider(router: router);
      await auth.ready; // her membership: Salon Excellence
      revokeMember(kFatouRow);
      await reinvite(team);
      ProAccessGuard.report('forbidden'); // her next request, refused
      for (var i = 0; i < 60 && !auth.rejoinPending; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    expect(auth.rejoinPending, isTrue, reason: 'the premise: on the gate');
    return (auth, router);
  }

  testWidgets('mid-session — the gate names the salon that was lost', (
    tester,
  ) async {
    final (auth, router) = await gatedMidSession(tester);

    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProTeamProvider()),
        ],
        routerConfig: router,
      ),
    );
    // S1: the cards are there on the FIRST frame — the list the decision
    // fetched, not a load of its own (no spinner, no empty frame).
    expect(find.text('Rejoindre'), findsOneWidget);
    expect(find.text('Aucune invitation en attente'), findsNothing);
    await settle(tester, steps: 1);

    expect(
      find.text('Votre accès à Salon Excellence a été retiré.'),
      findsOneWidget,
    );
    expect(find.text('Vous êtes invité(e)'), findsOneWidget);
    expect(find.text('Rejoindre'), findsOneWidget);
  });

  testWidgets('the gate at 360dp and 200% text: whole, every target ≥48 and '
      'labelled', (tester) async {
    final semantics = tester.ensureSemantics();
    final (auth, router) = await gatedMidSession(tester);

    await pumpAtWidth(
      tester,
      width: 360,
      scale: 2,
      routerConfig: router,
      providers: [
        ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => ProTeamProvider()),
      ],
    );

    expect(find.text('Rejoindre'), findsOneWidget, reason: 'the gate is up');
    // §13.3: a control's label may wrap between words, never inside one. The
    // first Linux golden of this screen showed « Rejoind/re » — the card's
    // two actions side by side leave « Rejoindre » too little width at 2×.
    expectNoMidWordBreak(tester, 'Rejoindre', 'the gate at 360 × 2');
    expectNoMidWordBreak(tester, 'Refuser', 'the gate at 360 × 2');
    expectNoUndeclaredTruncation(tester, context: 'the gate at 360 × 2');
    expectAppBarTitleWhole(tester, at: 'the gate at 360 × 2');
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
}

/// The mock, with an accept a test can script (offline, refused).
class _GateTeam extends MockProTeamService {
  ApiResponse<TeamMember>? acceptAnswer;

  @override
  Future<ApiResponse<TeamMember>> acceptInvitation(String invitationId) async {
    final scripted = acceptAnswer;
    if (scripted == null) return super.acceptInvitation(invitationId);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return scripted;
  }
}
