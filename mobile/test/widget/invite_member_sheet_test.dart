import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/team_error_messages.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/team_invitation.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/team/invite_member_sheet.dart';
import 'package:myweli/services/interfaces/pro_team_service_interface.dart';
import 'package:myweli/services/interfaces/subscription_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

/// serviceLocator fields are late-final — swap scenarios via a delegate.
class _SwitchableTeam implements ProTeamServiceInterface {
  ProTeamServiceInterface inner = MockProTeamService();

  @override
  Future<ApiResponse<List<TeamMember>>> getMembers() => inner.getMembers();

  @override
  Future<ApiResponse<TeamMember>> inviteMember({
    required String email,
    required TeamRole role,
    String? artistId,
  }) => inner.inviteMember(email: email, role: role, artistId: artistId);

  @override
  Future<ApiResponse<TeamMember>> changeRole(
    String memberId, {
    required TeamRole role,
    String? artistId,
  }) => inner.changeRole(memberId, role: role, artistId: artistId);

  @override
  Future<ApiResponse<TeamMember>> revokeMember(String memberId) =>
      inner.revokeMember(memberId);

  @override
  Future<ApiResponse<TeamMember>> resendInvitation(String memberId) =>
      inner.resendInvitation(memberId);

  @override
  Future<ApiResponse<List<TeamInvitation>>> getMyInvitations() =>
      inner.getMyInvitations();

  @override
  Future<ApiResponse<TeamMember>> acceptInvitation(String invitationId) =>
      inner.acceptInvitation(invitationId);

  @override
  Future<ApiResponse<bool>> declineInvitation(String invitationId) =>
      inner.declineInvitation(invitationId);
}

/// The salon's offer state the sheet reads (« Équipe » loads it before the
/// sheet opens) — swapped per scenario like the team service.
class _SwitchableSubs implements SubscriptionServiceInterface {
  SubscriptionServiceInterface inner = MockSubscriptionService();

  @override
  Future<ApiResponse<SalonSubscription>> getSalonSubscription(
    String providerId,
  ) => inner.getSalonSubscription(providerId);
}

class _FailingSubs implements SubscriptionServiceInterface {
  @override
  Future<ApiResponse<SalonSubscription>> getSalonSubscription(
    String providerId,
  ) async => ApiResponse.error('Pas de connexion. Réessayez.');
}

/// The session's acting salon (GET /me/provider). Its publish status is what
/// the sheet falls back on when the offer state is unknown.
class _SessionAuth extends ProAuthProvider {
  _SessionAuth(this.salon);

  final models.Provider? salon;

  @override
  models.Provider? get activeSalon => salon;
}

/// The demo account's lock (the server refuses the invite before any gate).
class _DemoLockedTeam extends MockProTeamService {
  @override
  Future<ApiResponse<TeamMember>> inviteMember({
    required String email,
    required TeamRole role,
    String? artistId,
  }) async => ApiResponse.error(
    teamErrorMessage('demo_account_locked'),
    code: 'demo_account_locked',
  );
}

/// Team access R3 §2.1 — the 3-step invite sheet: email validation, the
/// role cards' locked copy, the Collaborateur fiche step (+ inline create),
/// duplicate errors inline — and the refusals, which are a neutral sentence
/// and nothing else: the Pro app never sells (App Store 3.1.3(f),
/// docs/design/pro-companion-path.md §2.2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final team = _SwitchableTeam();
  final subs = _SwitchableSubs();
  // The refusals are what App Review meets on an iPhone: run them on BOTH
  // platforms — no platform branch may exist (pro-companion-path §8), and
  // `flutter test` alone only ever renders Android.
  final bothPlatforms = TargetPlatformVariant(const {
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  /// The sheet's salon with a given lifecycle (`draft` · `active`).
  models.Provider salonIn(String status, {String id = 'provider1'}) => MockData
      .providers
      .firstWhere((p) => p.id == 'provider1')
      .copyWith(id: id, status: status);

  /// The session's acting salon for the next pump — online by default.
  models.Provider? sessionSalon;

  SalonSubscription offer({
    SalonTier tier = SalonTier.business,
    SalonOfferStatus status = SalonOfferStatus.trial,
  }) => SalonSubscription(
    tier: tier,
    status: status,
    trialEndsAt: DateTime.now().add(const Duration(days: 60)),
    graceEndsAt: DateTime.now().add(const Duration(days: 67)),
    seats: const SalonSeats(cap: 15, used: 0),
  );

  /// One offer world for BOTH the team gate and the sheet's own read — the
  /// way production shares one server.
  void useOffer(MockSubscriptionService state) {
    subs.inner = state;
    team.inner = MockProTeamService(subscriptions: state);
  }

  // Business cap: the R4b seeds already occupy 5 of a Pro offer's seats.
  void useLiveOffer() => useOffer(MockSubscriptionService(initial: offer()));

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    // ProAuthProvider's ctor resolves the auth service (no one signed in).
    serviceLocator.authService = MockAuthService();
    serviceLocator.proArtistService = MockProArtistService();
    // ProArtistProvider's ctor resolves the upload service too.
    serviceLocator.imageUploadService = MockImageUploadService();
    serviceLocator.proTeamService = team;
    serviceLocator.subscriptionService = subs;
    useLiveOffer();
  });

  setUp(() {
    MockData.resetTeam();
    useLiveOffer();
    sessionSalon = salonIn('active');
  });

  Widget app() {
    final router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(path: '/host', builder: (_, _) => const _SheetHost()),
        GoRoute(
          path: '/pro/subscription',
          builder: (_, _) => const Scaffold(body: Text('OFFRES')),
        ),
      ],
    );
    return wrapApp(
      providers: [
        ChangeNotifierProvider(create: (_) => ProTeamProvider()),
        ChangeNotifierProvider(create: (_) => ProArtistProvider()),
        ChangeNotifierProvider(create: (_) => ProSubscriptionProvider()),
        ChangeNotifierProvider<ProAuthProvider>(
          create: (_) => _SessionAuth(sessionSalon),
        ),
      ],
      routerConfig: router,
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// Present the sheet exactly like production (a modal bottom sheet).
  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.text('OUVRIR'));
    await settle(tester);
  }

  Future<void> reachRoleStep(WidgetTester tester, {String? email}) async {
    await openSheet(tester);
    await tester.enterText(find.byType(TextField).first, email ?? 'ama@b.com');
    await tester.pump();
    await tester.tap(find.text('Continuer'));
    await tester.pump();
  }

  testWidgets('step 1 ANSWERS an invalid email instead of going dead', (
    tester,
  ) async {
    // A7 rewrote this test with the code it guards. It used to assert
    // `button.onPressed == null` — that a bad e-mail left « Continuer »
    // disabled — which is precisely §14 rule 5's anti-pattern: a dead end with
    // no explanation. Worse, the disabled button was what made this sheet's
    // `errorText` unreachable: the only field-anchored error in the product,
    // and it could never render.
    await openSheet(tester);

    expect(
      find.text('À quelle adresse e-mail envoyer l’invitation ?'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).first, 'pas-un-email');
    await tester.pump();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Continuer'),
    );
    expect(
      button.onPressed,
      isNotNull,
      reason: 'rule 5: never disabled to express "invalid"',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Continuer'));
    await tester.pump();

    expect(
      find.text('Saisissez une adresse e-mail valide.'),
      findsOneWidget,
      reason: 'the press must answer, under the field',
    );
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: '§14 rule 3 — a field fault is never a bar',
    );
    expect(
      find.text('À quelle adresse e-mail envoyer l’invitation ?'),
      findsOneWidget,
      reason: 'and it must not advance to the role step',
    );

    // Rule 2: fixing it clears the message without another submit.
    await tester.enterText(find.byType(TextField).first, 'ama@b.com');
    await tester.pump();
    expect(find.text('Saisissez une adresse e-mail valide.'), findsNothing);
  });

  testWidgets('step 2 shows the three role cards with the locked French '
      'summaries', (tester) async {
    await reachRoleStep(tester);

    expect(find.text('Manager'), findsOneWidget);
    expect(find.text('Réception'), findsOneWidget);
    expect(find.text('Collaborateur'), findsOneWidget);
    expect(
      find.text(
        'Gère les rendez-vous, le catalogue et les disponibilités. '
        'Ne voit pas les revenus.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Gère le planning et le fichier clients. Pas de catalogue '
        'ni de réglages.',
      ),
      findsOneWidget,
    );
    expect(find.text('Voit uniquement son propre planning.'), findsOneWidget);
  });

  testWidgets('Manager invite completes from step 2 with the snackbar', (
    tester,
  ) async {
    await reachRoleStep(tester);

    await tester.tap(find.text('Manager'));
    await tester.pump();
    await tester.tap(find.text('Envoyer l’invitation'));
    await settle(tester);

    expect(find.text('Invitation envoyée à ama@b.com'), findsOneWidget);
    expect(MockData.teamMembers.any((m) => m.email == 'ama@b.com'), isTrue);
  });

  testWidgets('Collaborateur requires the fiche step: picker + inline '
      '« Créer une fiche » auto-selects the new employee', (tester) async {
    await reachRoleStep(tester);

    await tester.tap(find.text('Collaborateur'));
    await tester.pump();
    await tester.tap(find.text('Continuer'));
    await settle(tester);

    expect(find.text('Associer à un membre de l’équipe'), findsOneWidget);
    expect(find.text('Kouassi Jean'), findsOneWidget); // seeded fiche

    // Inline create.
    await tester.tap(find.text('Créer une fiche'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Fatou');
    await tester.pump();
    await tester.tap(find.text('Créer la fiche'));
    await settle(tester);

    await tester.tap(find.text('Envoyer l’invitation'));
    await settle(tester);
    expect(find.text('Invitation envoyée à ama@b.com'), findsOneWidget);
    final row = MockData.teamMembers.singleWhere((m) => m.email == 'ama@b.com');
    expect(row.artistName, 'Fatou');
  });

  testWidgets('a duplicate shows the inline member_exists copy', (
    tester,
  ) async {
    await reachRoleStep(tester, email: 'awa.manager@myweli.test');

    await tester.tap(find.text('Manager'));
    await tester.pump();
    await tester.tap(find.text('Envoyer l’invitation'));
    await settle(tester);

    expect(find.text('Cette personne est déjà dans l’équipe.'), findsOneWidget);
  });

  /// Submits a Manager invite and returns how many buttons the sheet had
  /// before and after the refusal — a refusal may add a sentence, never a
  /// control.
  Future<({int before, int after})> submitManager(WidgetTester tester) async {
    await reachRoleStep(tester);
    await tester.tap(find.text('Manager'));
    await tester.pump();
    int buttons() =>
        find.byWidgetPredicate((w) => w is ButtonStyleButton).evaluate().length;
    final before = buttons();
    await tester.tap(find.text('Envoyer l’invitation'));
    await settle(tester);
    return (before: before, after: buttons());
  }

  /// What no refusal may say or offer (§2.1).
  void expectNoSalesPath() {
    for (final f in [
      find.textContaining('Choisir'),
      find.textContaining('Choisissez'),
      find.textContaining('Changer d’offre'),
      find.textContaining('mois offerts'),
      find.textContaining('Contactez'),
      find.textContaining('myweli.com'),
      find.text('OFFRES'), // the stubbed offer route — nothing navigates
    ]) {
      expect(f, findsNothing, reason: '$f');
    }
  }

  const setupSentence =
      'Vous pourrez inviter votre équipe une fois votre salon en ligne.';
  const expiredSentence =
      'Les invitations sont indisponibles : l’offre de votre salon n’est '
      'plus active.';

  testWidgets('offer_required on a SETUP salon (no offer row): the invites '
      'open once the salon is online — no button', (tester) async {
    useOffer(MockSubscriptionService()); // setup — the GET is a 404
    sessionSalon = salonIn('draft');
    final buttons = await submitManager(tester);

    expect(find.text(setupSentence), findsOneWidget);
    expect(find.text(expiredSentence), findsNothing);
    expect(
      buttons.after,
      buttons.before,
      reason: 'the refusal added a control',
    );
    expectNoSalesPath();
  }, variant: bothPlatforms);

  testWidgets('offer_required on an EXPIRED offer: the invites are '
      'unavailable — no button', (tester) async {
    useOffer(
      MockSubscriptionService(
        initial: offer(tier: SalonTier.pro, status: SalonOfferStatus.expired),
      ),
    );
    final buttons = await submitManager(tester);

    expect(find.text(expiredSentence), findsOneWidget);
    expect(find.text(setupSentence), findsNothing);
    expect(
      buttons.after,
      buttons.before,
      reason: 'the refusal added a control',
    );
    expectNoSalesPath();
  }, variant: bothPlatforms);

  testWidgets('offer_required while the offer state FAILED to load, on a '
      'DRAFT salon: the setup sentence — never claim an offer expired without '
      'a sign of one', (tester) async {
    useOffer(MockSubscriptionService()); // the server: no live offer
    subs.inner = _FailingSubs(); // the sheet: no state to read
    sessionSalon = salonIn('draft');
    await submitManager(tester);

    expect(find.text(setupSentence), findsOneWidget);
    expect(find.text(expiredSentence), findsNothing);
    expectNoSalesPath();
  }, variant: bothPlatforms);

  testWidgets('offer_required while the offer state FAILED to load, on an '
      'ONLINE salon: its offer expired — never « une fois votre salon en '
      'ligne » to a salon that is online', (tester) async {
    // Publishing creates the row, so an online salon refused by the offer
    // gate has an expired one — and with enforcement off it stays online.
    useOffer(
      MockSubscriptionService(
        initial: offer(tier: SalonTier.pro, status: SalonOfferStatus.expired),
      ),
    );
    subs.inner = _FailingSubs();
    final buttons = await submitManager(tester);

    expect(find.text(expiredSentence), findsOneWidget);
    expect(find.text(setupSentence), findsNothing);
    expect(
      buttons.after,
      buttons.before,
      reason: 'the refusal added a control',
    );
    expectNoSalesPath();
  }, variant: bothPlatforms);

  testWidgets('offer_required, state FAILED to load, and the session holds '
      'ANOTHER salon: its status says nothing about this one — the setup '
      'sentence', (tester) async {
    useOffer(MockSubscriptionService());
    subs.inner = _FailingSubs();
    sessionSalon = salonIn('active', id: 'another-salon');
    await submitManager(tester);
    expect(find.text(setupSentence), findsOneWidget);
    expect(find.text(expiredSentence), findsNothing);
  });

  testWidgets('seat_limit: the places are taken — the sentence, no « change '
      'offer » button', (tester) async {
    // Pro cap = 5 and the R4b seeds already occupy exactly 5 seats.
    useOffer(MockSubscriptionService(initial: offer(tier: SalonTier.pro)));
    final buttons = await submitManager(tester);

    expect(
      find.text('Toutes les places de votre offre sont occupées.'),
      findsOneWidget,
    );
    expect(
      buttons.after,
      buttons.before,
      reason: 'the refusal added a control',
    );
    expectNoSalesPath();
  }, variant: bothPlatforms);

  testWidgets('demo_account_locked: the demo sentence, not « Une erreur est '
      'survenue »', (tester) async {
    team.inner = _DemoLockedTeam();
    final buttons = await submitManager(tester);

    expect(
      find.text('Compte de démonstration — cette action est désactivée.'),
      findsOneWidget,
    );
    expect(find.textContaining('Une erreur est survenue'), findsNothing);
    expect(
      buttons.after,
      buttons.before,
      reason: 'the refusal added a control',
    );
    expectNoSalesPath();
  }, variant: bothPlatforms);
}

/// Hosts the sheet behind a button so it opens as a REAL modal bottom
/// sheet (production presents it with showModalBottomSheet — popping it
/// must not pop a router page).
class _SheetHost extends StatefulWidget {
  const _SheetHost();

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  @override
  void initState() {
    super.initState();
    // « Équipe » loads the salon's offer state before the sheet can open.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ProSubscriptionProvider>().load('provider1'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const InviteMemberSheet(providerId: 'provider1'),
          ),
          child: const Text('OUVRIR'),
        ),
      ),
    );
  }
}
