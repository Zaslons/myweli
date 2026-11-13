import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/salon_validation_copy.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/router/pro_router.dart';
import 'package:myweli/core/utils/salon_go_live.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_membership_info.dart';
import 'package:myweli/models/salon_validation.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_onboarding_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

import '../support/rejoin.dart';

/// The session's copy of the acting salon's go-live state — what the home
/// card « Configurer mon profil » follows (B0.18 —
/// docs/design/salon-go-live-approval.md §6.2, §8.3; decision 136 items 1
/// and 10): taken with the salon from every GET /me/provider, replaced by a
/// switch, never cached, gone with the session — and, after a submit from
/// « Configuration », re-read so the card, the picker and the screen agree.
///
/// Runs on the MOCK world: jean@ owns `provider1` (the default) and
/// `provider2`.
const _owner = 'jean@salon-excellence.test';
const _p1 = SalonId('provider1');
const _p2 = SalonId('provider2');

/// GET /me/provider and /me/salons, steerable: [script] answers the next
/// /me/provider calls in order; [holdMe] / [holdSalons] keep the NEXT answer
/// — computed now, from the store as it is — until released, as a read the
/// server answered before a change and the network delivered after it.
class _Pro extends MockProService {
  final List<ApiResponse<MyProviderInfo>> script = [];
  bool meFails = false;

  ({Completer<void> computed, Completer<void> release})? holdMe;
  ({Completer<void> computed, Completer<void> release})? holdSalons;

  static ApiResponse<MyProviderInfo> serverError() =>
      ApiResponse.error('Erreur serveur.', code: 'server_error');

  static ApiResponse<MyProviderInfo> forbidden() => ApiResponse.error(
    'Action réservée aux membres du salon.',
    code: 'forbidden',
  );

  void reset() {
    script.clear();
    meFails = false;
    holdMe = null;
    holdSalons = null;
  }

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({SalonId? salonId}) async {
    if (script.isNotEmpty) return script.removeAt(0);
    if (meFails) return serverError();
    final res = await super.getMyProvider(salonId: salonId);
    final hold = holdMe;
    if (hold != null) {
      holdMe = null;
      hold.computed.complete();
      await hold.release.future;
    }
    return res;
  }

  @override
  Future<ApiResponse<MySalonsResult>> getMySalons() async {
    final res = await super.getMySalons();
    final hold = holdSalons;
    if (hold != null) {
      holdSalons = null;
      hold.computed.complete();
      await hold.release.future;
    }
    return res;
  }

  /// [salonId]'s /me/provider as a server from before B0.18 answers it: no
  /// `validation` key.
  Future<ApiResponse<MyProviderInfo>> legacy(SalonId salonId) async {
    final info = (await super.getMyProvider(salonId: salonId)).data!;
    return ApiResponse.success(
      MyProviderInfo(salon: info.salon, membership: info.membership),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pro = _Pro();
  final auth = MockAuthService();

  setUpAll(() {
    serviceLocator.authService = auth;
    serviceLocator.proService = pro;
    serviceLocator.proTeamService = MockProTeamService();
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    pro.reset();
    (serviceLocator.subscriptionService as MockSubscriptionService)
        .resetForTests();
    await auth.logoutProvider();
    ProRouter.router.go('/pro/splash');
  });

  Future<ProAuthProvider> signIn([String email = _owner]) async {
    final p = ProAuthProvider();
    await p.ready; // the constructor's (signed-out) load, out of the way
    await p.requestEmailOtp(email);
    final ok = await p.verifyEmailOtp(email, p.emailDevCode!);
    expect(ok, isTrue, reason: 'login as $email failed');
    // The sign-in's own « Mes salons » load, landed.
    await p.rereadMySalons();
    return p;
  }

  Future<ProAuthProvider> restart() async {
    final p = ProAuthProvider();
    await p.ready;
    return p;
  }

  SalonValidation? rowOf(ProAuthProvider p, SalonId id) =>
      p.salons.firstWhere((s) => s.salonId == id).validation;

  group('the acting salon\'s state, from GET /me/provider', () {
    test('a sign-in reads it: a seeded salon is live and validated', () async {
      final p = await signIn();
      expect(p.salonGoLiveState, GoLiveState.live);
      expect(p.salonValidation?.state, SalonValidationState.approved);
      expect(
        homeCardSubtitle(p.salonGoLiveState),
        SalonValidationCopy.homeLive,
      );
    });

    test('a switch takes the NEW salon\'s state — the previous one\'s never '
        'survives it, a « never asked » null included', () async {
      MockData.seedPendingRequest(_p1);
      MockData.seedNeverAsked(_p2);
      final p = await signIn();
      expect(p.salonGoLiveState, GoLiveState.pending);
      expect(p.salonValidation?.state, SalonValidationState.pending);

      expect(await p.switchSalon(_p2), isTrue);
      expect(p.salonGoLiveState, GoLiveState.neverAsked);
      expect(
        p.salonValidation,
        isNull,
        reason: 'provider1\'s pending request is not provider2\'s',
      );

      expect(await p.switchSalon(_p1), isTrue);
      expect(p.salonGoLiveState, GoLiveState.pending);
    });

    test('a switch to a salon a server from before B0.18 answers (no key): '
        'today\'s screens — never the previous salon\'s refusal', () async {
      MockData.seedRefused(_p1, code: 'outside_ci');
      final p = await signIn();
      expect(p.salonGoLiveState, GoLiveState.refusedFinal);

      pro.script.add(await pro.legacy(_p2));
      expect(await p.switchSalon(_p2), isTrue);

      expect(p.salonGoLiveState, GoLiveState.legacy);
      expect(p.salonValidation, isNull);
    });

    test('a refused switch keeps the current salon\'s state', () async {
      MockData.seedPendingRequest(_p1);
      final p = await signIn();

      pro.script.add(_Pro.forbidden());
      expect(await p.switchSalon(_p2), isFalse);

      expect(p.activeSalonId, _p1);
      expect(p.salonGoLiveState, GoLiveState.pending);
    });

    test('an R6 fallback whose refetch fails: unknown — never the lost '
        'salon\'s state under the default salon\'s name', () async {
      MockData.seedPendingRequest(_p2);
      final p = await signIn();
      expect(await p.switchSalon(_p2), isTrue);
      expect(p.salonGoLiveState, GoLiveState.pending);

      // Revoked from provider2, and the default salon's /me then fails.
      pro.script.addAll([_Pro.forbidden(), _Pro.serverError()]);
      await p.checkMembershipAlive();

      expect(p.activeSalonId, _p1, reason: 'the selection fell back');
      expect(p.salonGoLiveState, isNull);
      expect(p.salonValidation, isNull);
      expect(
        homeCardSubtitle(p.salonGoLiveState),
        SalonValidationCopy.homeSetUp,
        reason: 'the card keeps its draft subtitle',
      );
    });

    test('never cached: a cold start whose /me fails knows no state — the '
        'card keeps its draft subtitle (§6.2)', () async {
      MockData.seedPendingRequest(_p1);
      await signIn();

      pro.meFails = true;
      final restarted = await restart();

      expect(restarted.isAuthenticated, isTrue);
      expect(restarted.salonKnown, isTrue, reason: 'the cached facts');
      expect(restarted.salonGoLiveState, isNull);
      expect(
        homeCardSubtitle(restarted.salonGoLiveState),
        SalonValidationCopy.homeSetUp,
      );
    });

    test('every way out clears it: a sign-out', () async {
      MockData.seedPendingRequest(_p1);
      final p = await signIn();
      await p.logout();

      expect(p.salonGoLiveState, isNull);
      expect(p.salonValidation, isNull);
    });

    test('every way out clears it: the rejoin gate', () async {
      final p = await signIn(kFatou);
      expect(p.salonGoLiveState, isNotNull);

      revokeMember(kFatouRow);
      await reinvite(serviceLocator.proTeamService);
      await p.checkMembershipAlive();

      expect(p.rejoinPending, isTrue);
      expect(p.salonGoLiveState, isNull);
      expect(p.salonValidation, isNull);
    });
  });

  // §6.2 « Refresh points »: after a submit, `refreshMembership` +
  // `loadMySalons` — from ONE place, `ProOnboardingProvider.publish`.
  group('a submit: « Configuration », the home card and « Mes salons » say '
      'the same thing', () {
    test(
      'a never-asked salon\'s request: all three read « pending »',
      () async {
        MockData.seedNeverAsked(_p1);
        final p = await signIn();
        expect(p.salonGoLiveState, GoLiveState.neverAsked);
        expect(rowOf(p, _p1), isNull);

        final onboarding = ProOnboardingProvider();
        final outcome = await onboarding.publish(_p1, session: p);
        await onboarding.publishSettled;

        expect(outcome?.saysRequestSent, isTrue);
        expect(onboarding.salonGoLiveState, GoLiveState.pending);
        expect(p.salonGoLiveState, GoLiveState.pending, reason: 'the card');
        expect(
          rowOf(p, _p1)?.state,
          SalonValidationState.pending,
          reason: 'the picker',
        );
      },
    );

    test('a /me/provider already out (answered before the submit) is not '
        'what the card keeps: it reads once more after it', () async {
      MockData.seedNeverAsked(_p1);
      final p = await signIn();

      final hold = (computed: Completer<void>(), release: Completer<void>());
      pro.holdMe = hold;
      final stale = p.refreshMembership();
      await hold.computed.future; // its answer: still never asked

      final onboarding = ProOnboardingProvider();
      await onboarding.publish(_p1, session: p);
      hold.release.complete();
      await stale;
      await onboarding.publishSettled;

      expect(p.salonGoLiveState, GoLiveState.pending);
    });

    test('a /me/salons already out (answered before the submit) is not what '
        'the picker keeps: it loads once more after it', () async {
      MockData.seedNeverAsked(_p1);
      final p = await signIn();

      final hold = (computed: Completer<void>(), release: Completer<void>());
      pro.holdSalons = hold;
      final stale = p.loadMySalons();
      await hold.computed.future; // its answer: still never asked

      final onboarding = ProOnboardingProvider();
      await onboarding.publish(_p1, session: p);
      hold.release.complete();
      await stale;
      await onboarding.publishSettled;

      expect(rowOf(p, _p1)?.state, SalonValidationState.pending);
    });
  });
}
