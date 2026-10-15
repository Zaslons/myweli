import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/router/pro_router.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/team_invitation.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';

import '../support/rejoin.dart';

/// The rejoin gate (docs/design/pro-rejoin-gate.md §2): on `not_a_member`,
/// while the session is live, the app asks for the account's pending
/// invitations BEFORE signing out. One or more → « Invitations », session
/// kept. None, or the question fails → today's sign-out with the banner
/// (fail closed), after one re-check of GET /me/provider.
///
/// Runs on the MOCK world, through scripted wrappers that count and steer the
/// two calls the decision makes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final team = _ScriptedTeam();
  final pro = _ScriptedPro();
  final mockAuth = MockAuthService();

  setUpAll(() {
    serviceLocator.authService = mockAuth;
    serviceLocator.proService = pro;
    serviceLocator.proTeamService = team;
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    team.reset();
    pro.reset();
    await mockAuth.logoutProvider();
    // The provider navigates on its own (sign-out, the gate): start each
    // test somewhere neither of those is.
    ProRouter.router.go('/pro/splash');
  });

  String location() => ProRouter.router.routeInformationProvider.value.uri.path;

  /// A signed-in provider for [email], its membership loaded — the way the
  /// sign-in screen gets one.
  Future<ProAuthProvider> signIn(String email) async {
    final auth = ProAuthProvider();
    await auth.ready; // the constructor's (signed-out) load, out of the way
    await auth.requestEmailOtp(email);
    final ok = await auth.verifyEmailOtp(email, auth.emailDevCode!);
    expect(ok, isTrue, reason: 'login as $email failed');
    return auth;
  }

  test('the mock invitee side follows the SIGNED-IN account, falling back to '
      'invitationEmail with no session', () async {
    // No session: the fixed stand-in (what the R3 screen tests rely on).
    expect(
      (await team.getMyInvitations()).data!.single.id,
      'mem_staff1',
      reason: 'invitee@myweli.test holds the seeded card',
    );

    await signIn(kFatou);
    revokeMember(kFatouRow);
    await reinvite(team);
    final cards = (await team.getMyInvitations()).data!;
    expect(cards.map((c) => c.id), ['mem_reception2']);
    expect(cards.single.salonName, 'Salon Excellence');
  });

  group('mid-session (the guard probe)', () {
    test('a pending invitation keeps the session, drops the lost salon and '
        'opens « Invitations »', () async {
      final auth = await signIn(kFatou);
      expect(auth.salonName, 'Salon Excellence');
      final scoped = _Scoped();
      ProSalonScope.track(scoped);

      revokeMember(kFatouRow);
      await reinvite(team);
      await auth.checkMembershipAlive();

      expect(auth.isAuthenticated, isTrue, reason: 'the session is kept');
      expect(auth.membership, isNull, reason: 'the lost salon is dropped');
      expect(auth.selectedSalonId, isNull);
      expect(await mockAuth.getCachedProviderMembership(), isNull);
      expect(scoped.resets, 1, reason: 'no salon data outlives the salon');
      expect(auth.consumeRevokedNotice(), isNull, reason: 'not signed out');
      expect(location(), '/pro/invitations');
      expect(team.listCalls, 1);
      // The gate's own state: held, its cards, the salon it lost.
      expect(auth.rejoinPending, isTrue);
      expect(auth.rejoinInvitations.map((c) => c.id), [kFatouRow]);
      expect(auth.rejoinRevokedSalon, 'Salon Excellence');
    });

    test(
      'no invitation → signed out, the salon named, after asking once',
      () async {
        final auth = await signIn(kFatou);
        revokeMember(kFatouRow);

        await auth.checkMembershipAlive();

        expect(team.listCalls, 1, reason: 'the invitations are asked first');
        expect(auth.isAuthenticated, isFalse);
        expect(auth.consumeRevokedNotice(), 'Salon Excellence');
        expect(location(), '/pro/login');
      },
    );

    for (final (label, script) in <(String, void Function(_ScriptedTeam))>[
      (
        'offline',
        (t) => t.answer = ApiResponse.error('Pas de connexion. Réessayez.'),
      ),
      (
        'a 401',
        (t) =>
            t.answer = ApiResponse.error('Non connecté', code: 'unauthorized'),
      ),
      ('a throw', (t) => t.throws = true),
    ]) {
      test('the invitations check fails ($label) → signed out with the banner '
          '(fail closed)', () async {
        final auth = await signIn(kFatou);
        revokeMember(kFatouRow);
        await reinvite(team); // a card exists — the check never sees it
        script(team);

        await auth.checkMembershipAlive();

        expect(team.listCalls, 1);
        expect(auth.isAuthenticated, isFalse, reason: 'fail closed');
        expect(auth.consumeRevokedNotice(), 'Salon Excellence');
        expect(location(), '/pro/login');
      });
    }

    test('a refresh and a probe answering together make ONE check, and the '
        'banner keeps the salon name (C1)', () async {
      final auth = await signIn(kFatou);
      revokeMember(kFatouRow);

      await Future.wait([
        auth.refreshMembership(),
        auth.checkMembershipAlive(),
      ]);

      expect(team.listCalls, 1, reason: 'single-flight');
      expect(auth.isAuthenticated, isFalse);
      expect(
        auth.consumeRevokedNotice(),
        'Salon Excellence',
        reason: 'the second answer must not rename it « votre salon »',
      );
    });

    test(
      'an accept that crossed the check — the list came back empty because '
      'the row just became active — keeps the session (the re-check)',
      () async {
        final auth = await signIn(kFatou);
        revokeMember(kFatouRow);
        await reinvite(team);
        // Accepted elsewhere while the list was in flight: the row is active
        // again and its card gone, so the list answers [].
        team.beforeAnswer = () async => activateMember(kFatouRow);

        await auth.checkMembershipAlive();

        expect(team.listCalls, 1);
        expect(auth.isAuthenticated, isTrue, reason: 'not signed out');
        expect(auth.membership?.role, TeamRole.reception);
        expect(auth.consumeRevokedNotice(), isNull);
        expect(location(), isNot('/pro/login'));
      },
    );
  });

  group(
    'at sign-in (the main path — a former member was already signed out)',
    () {
      test('email: a revoked account with no invitation answers FALSE — the '
          'sign-in screen stays, with its banner (S11)', () async {
        revokeMember(kFatouRow);
        final auth = ProAuthProvider();
        await auth.ready;
        await auth.requestEmailOtp(kFatou);

        final ok = await auth.verifyEmailOtp(kFatou, auth.emailDevCode!);

        expect(ok, isFalse, reason: 'true sent the screen to the dashboard');
        expect(auth.isAuthenticated, isFalse);
        expect(auth.error, isNull, reason: 'a notice, not an error');
        expect(auth.consumeRevokedNotice(), 'votre salon');
      });

      test(
        'Google: a revoked account with no invitation answers FALSE',
        () async {
          bareRevokedAccount(MockAuthService.mockProGoogleEmail);
          final auth = ProAuthProvider();
          await auth.ready;

          final ok = await auth.signInWithGoogle();

          expect(ok, isFalse);
          expect(auth.isAuthenticated, isFalse);
          expect(auth.consumeRevokedNotice(), 'votre salon');
        },
      );

      // The Apple button is iOS-gated, so no widget test ever renders it
      // (`flutter test` reports android) — its path is held here.
      test(
        'Apple: a revoked account with no invitation answers FALSE',
        () async {
          bareRevokedAccount(MockAuthService.mockProAppleEmail);
          final auth = ProAuthProvider();
          await auth.ready;

          final ok = await auth.signInWithApple();

          expect(ok, isFalse);
          expect(auth.isAuthenticated, isFalse);
          expect(auth.consumeRevokedNotice(), 'votre salon');
        },
      );

      test(
        'a former member WITH an invitation signs in — onto « Invitations », '
        'the session kept',
        () async {
          // Sign in once to re-invite under the mock's session-keyed world.
          await signIn(kFatou);
          revokeMember(kFatouRow);
          await reinvite(team);
          await mockAuth.logoutProvider();
          team.reset();

          final auth = ProAuthProvider();
          await auth.ready;
          await auth.requestEmailOtp(kFatou);
          final ok = await auth.verifyEmailOtp(kFatou, auth.emailDevCode!);

          expect(ok, isTrue);
          expect(auth.isAuthenticated, isTrue);
          expect(auth.consumeRevokedNotice(), isNull);
          expect(location(), '/pro/invitations');
          expect(team.listCalls, 1);
          expect(auth.rejoinPending, isTrue);
          expect(
            auth.rejoinRevokedSalon,
            isNull,
            reason:
                'signed in from nothing: no salon is known to have been '
                'lost — « ce salon » above another salon\'s card misleads',
          );
        },
      );

      test('the seeded former member (mock demo) signs in onto her '
          'Beauté Divine invitation', () async {
        final auth = ProAuthProvider();
        await auth.ready;
        await auth.requestEmailOtp('ancien.membre@myweli.test');
        final ok = await auth.verifyEmailOtp(
          'ancien.membre@myweli.test',
          auth.emailDevCode!,
        );

        expect(ok, isTrue);
        expect(auth.rejoinPending, isTrue);
        expect(auth.rejoinInvitations.single.salonName, 'Beauté Divine');
        expect(auth.rejoinInvitations.single.roleLabel, 'Réception');
      });
    },
  );

  test('cold start: a restored former member with an invitation opens '
      '« Invitations », the session kept', () async {
    await signIn(kFatou); // caches the membership
    revokeMember(kFatouRow);
    await reinvite(team);
    team.reset();
    ProRouter.router.go('/pro/splash');

    final auth = ProAuthProvider(); // what main_pro builds
    await auth.ready;

    expect(auth.isAuthenticated, isTrue);
    expect(auth.membership, isNull);
    expect(auth.consumeRevokedNotice(), isNull);
    expect(location(), '/pro/invitations');
    expect(auth.rejoinPending, isTrue);
    expect(
      auth.rejoinRevokedSalon,
      'Salon Excellence',
      reason: 'the cached membership names the salon that was lost',
    );
  });

  group('on the gate', () {
    /// Fatou, revoked mid-session and invited again: held on the gate.
    Future<ProAuthProvider> gated({
      TeamRole role = TeamRole.reception,
      String? artistId,
    }) async {
      final auth = await signIn(kFatou);
      revokeMember(kFatouRow);
      await reinvite(team, role: role, artistId: artistId);
      await auth.checkMembershipAlive();
      expect(auth.rejoinPending, isTrue, reason: 'the premise: on the gate');
      team.reset();
      pro.reset();
      return auth;
    }

    test('a 403 meanwhile asks nothing: the gate already holds the answer, '
        'and the session stays held', () async {
      final auth = await gated();

      await auth.checkMembershipAlive();
      await auth.checkMembershipAlive();

      expect(pro.calls, 0, reason: 'the guard stands down on the gate');
      expect(team.listCalls, 0);
      expect(auth.rejoinPending, isTrue);
      expect(auth.isAuthenticated, isTrue);
    });

    test('« Rejoindre » lands in the joined salon even with a refresh from '
        'BEFORE the accept still in flight (C2)', () async {
      final auth = await gated();
      // A refresh that asked before the accept: it will answer not_a_member
      // — the row was still `invited` — but only after the accept landed.
      final held = Completer<void>();
      pro.holdNext = held;
      final stale = auth.refreshMembership();

      final joined = await auth.acceptRejoin(() async {
        final res = await team.acceptInvitation(kFatouRow);
        held.complete(); // the stale answer arrives now, mid-rejoin
        return res.data;
      });
      await stale;

      expect(joined?.status, TeamMemberStatus.active);
      expect(auth.rejoinPending, isFalse);
      expect(auth.isAuthenticated, isTrue, reason: 'not signed out');
      expect(auth.membership?.role, TeamRole.reception);
      expect(auth.consumeRevokedNotice(), isNull);
      expect(
        team.listCalls,
        0,
        reason: 'the stale not_a_member must not start another check',
      );
      expect(location(), '/pro/dashboard');
    });

    test('« Rejoindre » as a Collaborateur lands on the staff shell', () async {
      final auth = await gated(role: TeamRole.staff, artistId: 'artist2');

      await auth.acceptRejoin(
        () async => (await team.acceptInvitation(kFatouRow)).data,
      );

      expect(auth.isStaff, isTrue);
      expect(location(), '/pro/staff');
    });

    test('the gate lifts only once the router is in the joined salon — a '
        'notification tap held meanwhile replays above it (S10)', () async {
      final auth = await gated();
      final seen = <(bool, String)>[];
      void record() => seen.add((auth.rejoinPending, location()));
      auth.addListener(record);
      addTearDown(() => auth.removeListener(record));

      await auth.acceptRejoin(
        () async => (await team.acceptInvitation(kFatouRow)).data,
      );

      expect(seen, isNotEmpty);
      expect(
        seen.where((s) => !s.$1 && s.$2 == '/pro/invitations'),
        isEmpty,
        reason:
            'lifted while the router is still on the gate, a held tap '
            'replays on top of it and the gate\'s `go` then drops it: $seen',
      );
      expect(seen.last, (false, '/pro/dashboard'));
    });

    test('a refused « Rejoindre » keeps the gate', () async {
      final auth = await gated();
      var accepted = false;

      final joined = await auth.acceptRejoin(
        () async => null,
        onAccepted: () => accepted = true,
      );

      expect(joined, isNull);
      expect(accepted, isFalse);
      expect(auth.rejoinPending, isTrue);
      expect(location(), '/pro/invitations');
    });

    test('« Déconnexion » signs out with the lost salon named, and ends the '
        'gate', () async {
      final auth = await gated();

      await auth.signOutRevoked();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.rejoinPending, isFalse);
      expect(auth.rejoinInvitations, isEmpty);
      expect(auth.rejoinRevokedSalon, isNull);
      expect(auth.consumeRevokedNotice(), 'Salon Excellence');
      expect(location(), '/pro/login');
    });

    test('logout ends the gate', () async {
      final auth = await gated();

      await auth.logout();

      expect(auth.rejoinPending, isFalse);
      expect(auth.rejoinInvitations, isEmpty);
    });

    // Review findings 2/15/9: the session can end while an accept is out
    // (the server keeps the token the request was sent under, so the answer
    // is still a 200). Nothing after that may navigate a signed-out session.
    test('a sign-out while the accept is out: the late 200 neither enters '
        'the salon nor leaves the sign-in', () async {
      final auth = await gated();
      var leaving = false;

      final joined = await auth.acceptRejoin(() async {
        final served = await team.acceptInvitation(kFatouRow);
        await auth.signOutRevoked(); // she leaves while the answer travels
        return served.data;
      }, onAccepted: () => leaving = true);

      expect(joined?.status, TeamMemberStatus.active, reason: 'joined');
      expect(leaving, isFalse, reason: 'no « entering the salon » loader');
      expect(location(), '/pro/login');
      expect(auth.isAuthenticated, isFalse);
      expect(auth.rejoinPending, isFalse);
      expect(auth.consumeRevokedNotice(), 'Salon Excellence');
    });

    test('a session that ends while the rejoin asks for the new shape is not '
        'routed into the salon', () async {
      final auth = await gated();
      // The accept landed; logout finishes while GET /me/provider is out.
      pro.during = auth.logout;

      await auth.acceptRejoin(
        () async => (await team.acceptInvitation(kFatouRow)).data,
      );

      expect(auth.isAuthenticated, isFalse);
      expect(location(), isNot('/pro/dashboard'));
      expect(location(), isNot('/pro/staff'));
    });

    // Review finding 1: the gate's « no card left » exit (S3, S6) is a
    // sign-out decided on an empty list — §2.4 asks GET /me/provider first.
    test(
      'no card left, the row active again (accepted elsewhere): the '
      'salon, and the gate lifts only once the router is there (S10)',
      () async {
        final auth = await gated(role: TeamRole.staff, artistId: 'artist2');
        activateMember(kFatouRow);
        final seen = <(bool, String)>[];
        void record() => seen.add((auth.rejoinPending, location()));
        auth.addListener(record);
        addTearDown(() => auth.removeListener(record));

        final entered = await auth.leaveEmptiedRejoin();

        expect(entered, isTrue);
        expect(pro.calls, 1, reason: 'asked once');
        expect(auth.isAuthenticated, isTrue);
        expect(auth.isStaff, isTrue);
        expect(auth.consumeRevokedNotice(), isNull);
        expect(location(), '/pro/staff');
        expect(
          seen.where((s) => !s.$1 && s.$2 == '/pro/invitations'),
          isEmpty,
          reason: 'lifted above the gate, a held tap replays there: $seen',
        );
        expect(seen.last, (false, '/pro/staff'));
      },
    );

    test('no card left and no membership: signed out, the lost salon named, '
        'after asking once', () async {
      final auth = await gated();

      final entered = await auth.leaveEmptiedRejoin();

      expect(entered, isFalse);
      expect(pro.calls, 1);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.rejoinPending, isFalse);
      expect(auth.consumeRevokedNotice(), 'Salon Excellence');
      expect(location(), '/pro/login');
    });

    test('the dead-session exit: signed out to the sign-in, no « accès '
        'retiré » banner', () async {
      final auth = await gated();
      // A refused refresh clears the STORED session.
      await serviceLocator.authService.logoutProvider();

      final ended = await auth.endExpiredRejoin();

      expect(ended, isTrue);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.rejoinPending, isFalse);
      expect(auth.consumeRevokedNotice(), isNull);
      expect(location(), '/pro/login');
    });

    test('a 401 whose refresh failed in TRANSPORT is not a dead session: the '
        'stored session stands, so nothing is signed out', () async {
      final auth = await gated(); // the stored session is NOT cleared

      final ended = await auth.endExpiredRejoin();

      expect(ended, isFalse);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.rejoinPending, isTrue);
      expect(location(), isNot('/pro/login'));
    });

    test('completeRejoin off a live gate does nothing', () async {
      final auth = await gated();
      await auth.logout();

      await auth.completeRejoin(joinedRole: TeamRole.reception);

      expect(location(), isNot('/pro/dashboard'));
      expect(auth.isAuthenticated, isFalse);
    });

    test('completeRejoin off the gate asks the server nothing and goes '
        'nowhere', () async {
      final auth = await signIn(kFatou); // a member, never gated
      pro.reset();

      await auth.completeRejoin(joinedRole: TeamRole.reception);

      expect(pro.calls, 0, reason: 'no GET /me/provider for nothing');
      expect(location(), '/pro/splash');
    });

    test('acceptRejoin off the gate does nothing', () async {
      final auth = await signIn(kFatou);
      var called = false;

      final joined = await auth.acceptRejoin(() async {
        called = true;
        return null;
      });

      expect(joined, isNull);
      expect(called, isFalse);
    });
  });
}

/// The invitations the gate check asks for — the mock's own answer unless a
/// test scripts another, counted.
class _ScriptedTeam extends MockProTeamService {
  // Most tests here re-invite once; the daily cap is not what they test.
  _ScriptedTeam() : super(maxInvitesPerDay: 1000);

  int listCalls = 0;
  ApiResponse<List<TeamInvitation>>? answer;
  bool throws = false;

  /// Runs while the list is in flight — an accept crossing it.
  Future<void> Function()? beforeAnswer;

  void reset() {
    listCalls = 0;
    answer = null;
    throws = false;
    beforeAnswer = null;
  }

  @override
  Future<ApiResponse<List<TeamInvitation>>> getMyInvitations() async {
    listCalls++;
    await beforeAnswer?.call();
    if (throws) throw StateError('the network went away');
    return answer ?? super.getMyInvitations();
  }
}

/// GET /me/provider, counted.
class _ScriptedPro extends MockProService {
  int calls = 0;

  /// The next call answers what the server said BEFORE an accept —
  /// not_a_member — but only once this completes: a stale answer, late.
  Completer<void>? holdNext;

  /// Runs once while the next call is out — before it answers.
  Future<void> Function()? during;

  void reset() {
    calls = 0;
    holdNext = null;
    during = null;
  }

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({String? salonId}) async {
    calls++;
    final meanwhile = during;
    during = null;
    await meanwhile?.call();
    final hold = holdNext;
    if (hold == null) return super.getMyProvider(salonId: salonId);
    holdNext = null;
    await hold.future;
    return ApiResponse.error(
      'Votre accès à ce salon a été retiré.',
      code: 'not_a_member',
    );
  }
}

class _Scoped implements SalonScoped {
  int resets = 0;

  @override
  void resetForSalonSwitch() => resets++;
}
