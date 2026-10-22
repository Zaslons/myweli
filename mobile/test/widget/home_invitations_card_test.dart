import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/team_error_messages.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/journal_day.dart';
import 'package:myweli/models/salon_membership_info.dart';
import 'package:myweli/models/team_invitation.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/dashboard/dashboard_screen.dart';
import 'package:myweli/screens/provider/journal/pro_journal_screen.dart';
import 'package:myweli/screens/provider/team/pro_invitations_screen.dart';
import 'package:myweli/services/api/api_errors.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_notification_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:myweli/widgets/team/pro_invitations_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

TeamInvitation _invitation(String id, String salon) => TeamInvitation(
  id: id,
  providerId: 'p-$id',
  salonName: salon,
  role: TeamRole.staff,
  roleLabel: 'Collaborateur',
  expiresAt: DateTime.utc(2026, 11, 5),
);

/// The account's own invitations, scripted: what the list answers, what an
/// accept or a decline answers, and an accept a test can hold.
class _Team extends MockProTeamService {
  List<TeamInvitation> cards = const [];

  /// The list's read fails (the card stays silent, as on the web).
  bool failRead = false;
  int reads = 0;

  ApiResponse<TeamMember>? acceptAnswer;
  ApiResponse<bool>? declineAnswer;
  Completer<void>? holdAccept;

  void reset() {
    cards = const [];
    failRead = false;
    reads = 0;
    acceptAnswer = null;
    declineAnswer = null;
    holdAccept = null;
  }

  @override
  Future<ApiResponse<List<TeamInvitation>>> getMyInvitations() async {
    reads++;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (failRead) return networkError();
    return ApiResponse.success(cards);
  }

  @override
  Future<ApiResponse<TeamMember>> acceptInvitation(String invitationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final hold = holdAccept;
    if (hold != null) await hold.future;
    return acceptAnswer ??
        ApiResponse.success(
          TeamMember(
            id: invitationId,
            providerId: 'p-$invitationId',
            email: 'jean@salon-excellence.test',
            role: TeamRole.staff,
            status: TeamMemberStatus.active,
            invitedAt: DateTime.utc(2026, 10, 1),
          ),
        );
  }

  @override
  Future<ApiResponse<bool>> declineInvitation(String invitationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return declineAnswer ?? ApiResponse.success(true);
  }
}

/// Counts « Mes salons » reads — a join must reload the switcher's list. The
/// day is empty and answers at once: the week strip's prefetch chains seven
/// day reads, and the card is what these tests are about.
class _Pro extends MockProService {
  int salonReads = 0;

  /// Holds « Mes salons »' answer: a load still out when the join lands.
  Completer<void>? holdSalons;

  /// Answers at once (no mock delay): the sign-in's own load is done before
  /// a screen mounts, so a test sees only the loads it caused.
  @override
  Future<ApiResponse<MySalonsResult>> getMySalons() async {
    salonReads++;
    final hold = holdSalons;
    if (hold != null) await hold.future;
    return ApiResponse.success(
      const MySalonsResult(items: [], canAddSalon: false),
    );
  }

  @override
  Future<ApiResponse<JournalDay>> getJournalDay(
    String providerId,
    DateTime date,
  ) async => ApiResponse.success(
    const JournalDay(date: '2026-10-22', artists: [], appointments: []),
  );
}

const _title = 'Invitations d’équipe';

/// docs/design/pro-app-batch7.md §2.6 (B7.6, decision 23) — the web's
/// « Invitations d'équipe » card, at the top of « Accueil » and of the
/// Collaborateur's « Journée »: nothing when there is none, « Rejoindre »
/// reloads « Mes salons », « Refuser » without a confirmation, an expired
/// card goes with the server's sentence, offline the card stays, and one
/// answer at a time.
void main() {
  final team = _Team();
  final pro = _Pro();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    // The push prompt asked already: its sheet would cover « Accueil ».
    SharedPreferences.setMockInitialValues({'myweli_push_asked': true});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = pro;
    serviceLocator.proTeamService = team;
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() {
    MockData.resetTeam();
    team.reset();
    pro.holdSalons = null;
    // Each test registers its own team store, as main_pro does for the app:
    // a salon switch reaches the stores through this registry.
    ProSalonScope.clear();
  });

  /// [teamStore]: a store the test already used — by default a fresh one.
  Future<ProAuthProvider> pumpAccueil(
    WidgetTester tester, {
    ProTeamProvider? teamStore,
  }) async {
    final auth = await signInPro(tester);
    final router = GoRouter(
      initialLocation: '/pro/dashboard',
      routes: [
        GoRoute(
          path: '/pro/dashboard',
          builder: (_, _) => const DashboardScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProDashboardProvider()),
          ChangeNotifierProvider(
            create: (_) =>
                NotificationsProvider(service: MockNotificationService()),
          ),
          if (teamStore != null)
            ChangeNotifierProvider<ProTeamProvider>.value(value: teamStore)
          else
            ChangeNotifierProvider(
              create: (_) => ProSalonScope.track(ProTeamProvider()),
            ),
        ],
        routerConfig: router,
      ),
    );
    await settleMocks(tester, rounds: 3);
    return auth;
  }

  Future<void> pumpJournee(WidgetTester tester, {required String as}) async {
    final auth = await signInPro(tester, email: as);
    final router = GoRouter(
      initialLocation: '/pro/journal',
      routes: [
        GoRoute(
          path: '/pro/journal',
          builder: (_, _) => const ProJournalScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProJournalProvider()),
          ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProTeamProvider()),
          ),
        ],
        routerConfig: router,
      ),
    );
    await settleMocks(tester, rounds: 3);
  }

  /// The button's own `onPressed` — null while it waits.
  bool enabled(WidgetTester tester, Finder button) {
    final b = tester.widget<ButtonStyleButton>(
      find.ancestor(of: button, matching: find.bySubtype<ButtonStyleButton>()),
    );
    return b.onPressed != null;
  }

  group('« Accueil »', () {
    testWidgets('no invitation → nothing at all, no title', (tester) async {
      await pumpAccueil(tester);
      expect(team.reads, greaterThan(0), reason: 'the list was never read');
      expect(find.text(_title), findsNothing);
      expect(find.text('Rejoindre'), findsNothing);
    });

    testWidgets('a list that cannot be read → nothing, silently', (
      tester,
    ) async {
      team
        ..cards = [_invitation('i1', 'Beauté Divine')]
        ..failRead = true;
      await pumpAccueil(tester);
      expect(find.text(_title), findsNothing);
      expect(find.text(kNoConnectionMessageForTest), findsNothing);
    });

    testWidgets('« Rejoindre »: the card goes, « Vous avez rejoint », and '
        '« Mes salons » is read again', (tester) async {
      team.cards = [_invitation('i1', 'Beauté Divine')];
      await pumpAccueil(tester);
      expect(find.text(_title), findsOneWidget);
      expect(find.textContaining('Beauté Divine'), findsOneWidget);
      final before = pro.salonReads;

      await tester.tap(find.text('Rejoindre'));
      await settleMocks(tester, rounds: 2);

      expect(find.text('Vous avez rejoint Beauté Divine'), findsOneWidget);
      expect(find.text(_title), findsNothing);
      expect(pro.salonReads, greaterThan(before), reason: 'no reload');
    });

    testWidgets('a join while « Mes salons » is loading still reloads it — '
        'the load out was answered before the join', (tester) async {
      team.cards = [_invitation('i1', 'Beauté Divine')];
      final auth = await pumpAccueil(tester);
      final held = pro.holdSalons = Completer<void>();
      unawaited(auth.loadMySalons());
      await tester.pump();
      final before = pro.salonReads;

      await tester.tap(find.text('Rejoindre'));
      await settleMocks(tester, rounds: 2);
      expect(find.text('Vous avez rejoint Beauté Divine'), findsOneWidget);

      pro.holdSalons = null;
      held.complete();
      await settleMocks(tester);
      expect(
        pro.salonReads,
        before + 1,
        reason: 'the join was dropped behind the load already out',
      );
    });

    testWidgets('« Refuser »: the card goes, no confirmation', (tester) async {
      team.cards = [_invitation('i1', 'Beauté Divine')];
      await pumpAccueil(tester);

      await tester.tap(find.text('Refuser'));
      await settleMocks(tester, rounds: 2);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('expired: the card goes, with the server’s sentence', (
      tester,
    ) async {
      team
        ..cards = [_invitation('i1', 'Beauté Divine')]
        ..acceptAnswer = ApiResponse.error('x', code: 'invitation_expired');
      await pumpAccueil(tester);

      await tester.tap(find.text('Rejoindre'));
      await settleMocks(tester, rounds: 2);

      expect(find.text(teamErrorMessage('invitation_expired')), findsOneWidget);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('offline: « Pas de connexion. Réessayez. », the card stays '
        'and answers again', (tester) async {
      team
        ..cards = [_invitation('i1', 'Beauté Divine')]
        ..acceptAnswer = networkError();
      await pumpAccueil(tester);

      await tester.tap(find.text('Rejoindre'));
      await settleMocks(tester, rounds: 2);

      expect(find.text(kNoConnectionMessageForTest), findsOneWidget);
      expect(find.text(_title), findsOneWidget);
      expect(enabled(tester, find.text('Rejoindre')), isTrue);
    });

    testWidgets('one answer at a time: every button waits while one is out', (
      tester,
    ) async {
      team
        ..cards = [
          _invitation('i1', 'Beauté Divine'),
          _invitation('i2', 'Institut Riviera'),
        ]
        ..holdAccept = Completer<void>();
      await pumpAccueil(tester);

      await tester.tap(find.text('Rejoindre').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The other card's two buttons wait too — not only the tapped one.
      expect(enabled(tester, find.text('Refuser').last), isFalse);
      expect(enabled(tester, find.text('Rejoindre').last), isFalse);

      team.holdAccept!.complete();
      await settleMocks(tester, rounds: 2);
      expect(enabled(tester, find.text('Rejoindre')), isTrue);
      expect(find.textContaining('Institut Riviera'), findsOneWidget);
    });

    testWidgets('mounting reads the list, even one another screen read', (
      tester,
    ) async {
      // Profil read it first (the staff shell mounts its three tabs at once):
      // « Accueil » still asks, for a list as fresh as the screen.
      final store = ProTeamProvider();
      addTearDown(store.dispose);
      await tester.runAsync(store.loadMyInvitations);
      final before = team.reads;

      await pumpAccueil(tester, teamStore: store);

      expect(team.reads, greaterThan(before), reason: 'not read on mount');
    });

    testWidgets('a pull on « Accueil » reads the list again', (tester) async {
      team.cards = [_invitation('i1', 'Beauté Divine')];
      await pumpAccueil(tester);
      final before = team.reads;

      await tester.fling(find.text(_title), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settleMocks(tester, rounds: 2);

      expect(team.reads, greaterThan(before), reason: 'the pull did not read');
    });

    // The reset itself, not the salon id: the id changes before the reset,
    // and a read that fell between the two was wiped by it.
    testWidgets('a reset with no salon change still reads the list again', (
      tester,
    ) async {
      team.cards = [_invitation('i1', 'Institut Riviera')];
      await pumpAccueil(tester);
      expect(find.text(_title), findsOneWidget);
      final before = team.reads;

      ProSalonScope.resetAll();
      await settleMocks(tester, rounds: 2);

      expect(team.reads, greaterThan(before), reason: 'emptied, not read');
      expect(find.text(_title), findsOneWidget);
    });

    testWidgets('a salon switch reads the list again — the switch empties it', (
      tester,
    ) async {
      team.cards = [_invitation('i1', 'Institut Riviera')];
      final auth = await pumpAccueil(tester);
      final before = team.reads;

      await tester.runAsync(() async {
        expect(await auth.switchSalon('provider2'), isTrue);
      });
      await settleMocks(tester, rounds: 3);

      expect(team.reads, greaterThan(before), reason: 'not read again');
      expect(find.text(_title), findsOneWidget);
    });
  });

  // The « Invitations » screen (Profil) joins through the session too, so
  // « Mes salons » reloads from there as well.
  testWidgets('Profil → Invitations: a join reloads « Mes salons »', (
    tester,
  ) async {
    team.cards = [_invitation('i1', 'Beauté Divine')];
    final auth = await signInPro(tester);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProTeamProvider()),
        ],
        home: const ProInvitationsScreen(),
      ),
    );
    await settleMocks(tester, rounds: 2);
    final before = pro.salonReads;

    await tester.tap(find.text('Rejoindre'));
    await settleMocks(tester, rounds: 2);

    expect(find.text('Vous avez rejoint Beauté Divine'), findsOneWidget);
    expect(pro.salonReads, greaterThan(before), reason: 'no reload');
  });

  group('« Journée »', () {
    testWidgets('the Collaborateur sees the card at the top of the day, and a '
        'pull reads it again', (tester) async {
      team.cards = [_invitation('i1', 'Beauté Divine')];
      await pumpJournee(tester, as: 'sonia.staff@myweli.test');

      expect(find.text(_title), findsOneWidget);
      final before = team.reads;
      await tester.fling(find.text(_title), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settleMocks(tester, rounds: 2);
      expect(team.reads, greaterThan(before), reason: 'the pull did not read');
    });

    // The own-mode golden caught it: a wrapper's padding kept an 8 dp strip
    // above the empty day when there was no invitation.
    testWidgets('no invitation → the card takes no room, its padding '
        'included', (tester) async {
      await pumpJournee(tester, as: 'sonia.staff@myweli.test');
      expect(find.text(_title), findsNothing);
      // `skipOffstage: false`: a list counts a zero-height child as offstage.
      final card = find.byType(ProInvitationsCard, skipOffstage: false);
      expect(card, findsOneWidget, reason: 'the card is on the day');
      expect(
        tester.getSize(card).height,
        0,
        reason: 'an empty card keeps a strip above the day',
      );
    });

    testWidgets('the salon’s own « Ma journée » does not repeat it — '
        '« Accueil » has it', (tester) async {
      team.cards = [_invitation('i1', 'Beauté Divine')];
      await pumpJournee(tester, as: 'jean@salon-excellence.test');
      expect(find.text(_title), findsNothing);
    });
  });
}

/// The offline sentence, spelled out: the test must fail if the card shows
/// any other.
const kNoConnectionMessageForTest = 'Pas de connexion. Réessayez.';
