import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/team_invitation.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/team/invite_member_sheet.dart';
import 'package:myweli/services/interfaces/pro_team_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  }) =>
      inner.inviteMember(email: email, role: role, artistId: artistId);

  @override
  Future<ApiResponse<TeamMember>> changeRole(
    String memberId, {
    required TeamRole role,
    String? artistId,
  }) =>
      inner.changeRole(memberId, role: role, artistId: artistId);

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

/// Team access R3 §2.1 — the 3-step invite sheet: email validation, the
/// role cards' locked copy, the Collaborateur fiche step (+ inline create),
/// duplicate errors inline and the offer CTA.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final team = _SwitchableTeam();

  void useOffer({required bool live}) {
    final subs = live
        ? MockSubscriptionService(
            initial: SalonSubscription(
              tier: SalonTier.pro,
              status: SalonOfferStatus.trial,
              trialEndsAt: DateTime.now().add(const Duration(days: 60)),
              graceEndsAt: DateTime.now().add(const Duration(days: 67)),
              seats: const SalonSeats(cap: 5, used: 0),
            ),
          )
        : MockSubscriptionService();
    team.inner = MockProTeamService(subscriptions: subs);
  }

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.proArtistService = MockProArtistService();
    // ProArtistProvider's ctor resolves the upload service too.
    serviceLocator.imageUploadService = MockImageUploadService();
    serviceLocator.proTeamService = team;
    useOffer(live: true);
  });

  setUp(() {
    MockData.resetTeam();
    useOffer(live: true);
  });

  Widget app() {
    final router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(path: '/host', builder: (_, __) => const _SheetHost()),
        GoRoute(
          path: '/pro/subscription',
          builder: (_, __) => const Scaffold(body: Text('OFFRES')),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProTeamProvider()),
        ChangeNotifierProvider(create: (_) => ProArtistProvider()),
      ],
      child: MaterialApp.router(routerConfig: router),
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

  testWidgets('step 1 gates on a valid email', (tester) async {
    await openSheet(tester);

    expect(
      find.text('À quelle adresse e-mail envoyer l\'invitation ?'),
      findsOneWidget,
    );
    // Invalid email keeps « Continuer » disabled.
    await tester.enterText(find.byType(TextField).first, 'pas-un-email');
    await tester.pump();
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Continuer'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'step 2 shows the three role cards with the locked French '
      'summaries', (tester) async {
    await reachRoleStep(tester);

    expect(find.text('Manager'), findsOneWidget);
    expect(find.text('Réception'), findsOneWidget);
    expect(find.text('Collaborateur'), findsOneWidget);
    expect(
      find.text('Gère les rendez-vous, le catalogue et les disponibilités. '
          'Ne voit pas les revenus.'),
      findsOneWidget,
    );
    expect(
      find.text('Gère le planning et le fichier clients. Pas de catalogue '
          'ni de réglages.'),
      findsOneWidget,
    );
    expect(
      find.text('Voit uniquement son propre planning.'),
      findsOneWidget,
    );
  });

  testWidgets('Manager invite completes from step 2 with the snackbar',
      (tester) async {
    await reachRoleStep(tester);

    await tester.tap(find.text('Manager'));
    await tester.pump();
    await tester.tap(find.text('Envoyer l\'invitation'));
    await settle(tester);

    expect(find.text('Invitation envoyée à ama@b.com'), findsOneWidget);
    expect(
      MockData.teamMembers.any((m) => m.email == 'ama@b.com'),
      isTrue,
    );
  });

  testWidgets(
      'Collaborateur requires the fiche step: picker + inline '
      '« Créer une fiche » auto-selects the new employee', (tester) async {
    await reachRoleStep(tester);

    await tester.tap(find.text('Collaborateur'));
    await tester.pump();
    await tester.tap(find.text('Continuer'));
    await settle(tester);

    expect(find.text('Associer à un membre de l\'équipe'), findsOneWidget);
    expect(find.text('Kouassi Jean'), findsOneWidget); // seeded fiche

    // Inline create.
    await tester.tap(find.text('Créer une fiche'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Fatou');
    await tester.pump();
    await tester.tap(find.text('Créer la fiche'));
    await settle(tester);

    await tester.tap(find.text('Envoyer l\'invitation'));
    await settle(tester);
    expect(find.text('Invitation envoyée à ama@b.com'), findsOneWidget);
    final row = MockData.teamMembers.singleWhere((m) => m.email == 'ama@b.com');
    expect(row.artistName, 'Fatou');
  });

  testWidgets('a duplicate shows the inline member_exists copy',
      (tester) async {
    await reachRoleStep(tester, email: 'awa.manager@myweli.test');

    await tester.tap(find.text('Manager'));
    await tester.pump();
    await tester.tap(find.text('Envoyer l\'invitation'));
    await settle(tester);

    expect(
      find.text('Cette personne est déjà dans l\'équipe.'),
      findsOneWidget,
    );
  });

  testWidgets('offer_required renders the CTA to the offer picker',
      (tester) async {
    useOffer(live: false); // setup state — invites gated
    await reachRoleStep(tester);

    await tester.tap(find.text('Manager'));
    await tester.pump();
    await tester.tap(find.text('Envoyer l\'invitation'));
    await settle(tester);

    expect(
      find.text('Choisissez d\'abord votre offre pour inviter votre '
          'équipe.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Choisir mon offre'));
    await settle(tester);
    expect(find.text('OFFRES'), findsOneWidget);
  });
}

/// Hosts the sheet behind a button so it opens as a REAL modal bottom
/// sheet (production presents it with showModalBottomSheet — popping it
/// must not pop a router page).
class _SheetHost extends StatelessWidget {
  const _SheetHost();

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
