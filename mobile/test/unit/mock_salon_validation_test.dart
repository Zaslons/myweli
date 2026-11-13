import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_membership_info.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/salon_validation.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

import '../support/web_created.dart';

/// B0.18 — the mock world's validation lifecycle
/// (docs/design/salon-go-live-approval.md §6.5): the publish is a request
/// that mirrors the server's branches (§3.1) and starts no trial; two test
/// hooks stand in for the admin (validate starts the trial, §3.6; refuse
/// takes a code and a note, §3.3); fixtures seed each state; and
/// `/me/provider` and `/me/salons` read ONE store — they disagreed before, a
/// salon added on the web reading `draft` in « Mes salons » and live on
/// `/me/provider`.
void main() {
  final pro = MockProService();
  final subs = MockSubscriptionService();

  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = pro;
    serviceLocator.subscriptionService = subs;
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    ProSalonScope.clear();
    subs.resetForTests(); // SETUP: no offer row anywhere
    await serviceLocator.authService.logoutProvider();
  });

  Future<ProAuthProvider> signIn(String email) async {
    final auth = ProAuthProvider();
    await auth.requestEmailOtp(email);
    final ok = await auth.verifyEmailOtp(email, auth.emailDevCode!);
    expect(ok, isTrue, reason: 'login failed for $email');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return auth;
  }

  Future<ProAuthProvider> signInOwner() => signIn('jean@salon-excellence.test');

  const p1 = SalonId('provider1');

  Future<MyProviderInfo> me([SalonId salon = p1]) async {
    final res = await pro.getMyProvider(salonId: salon);
    expect(res.success, isTrue, reason: res.error);
    return res.data!;
  }

  Future<SalonMembershipInfo> row(SalonId salon) async {
    final res = await pro.getMySalons();
    expect(res.success, isTrue, reason: res.error);
    return res.data!.items.firstWhere((r) => r.salonId == salon);
  }

  Future<ApiResponse<PublishOutcome>> publish([SalonId salon = p1]) =>
      pro.publishSalon(salon);

  group('the seeds, and the two reads agree', () {
    test('a seeded salon is live and validated (the 0044 backfill\'s mirror); '
        'both reads send the key', () async {
      await signInOwner();
      final info = await me();
      expect(info.salon.status, isNull, reason: 'null reads active');
      expect(info.validationSent, isTrue);
      expect(info.validation!.state, SalonValidationState.approved);
      expect(info.validation!.wentLive, isTrue);
      expect(info.validation!.submittedAt, isNull);

      final r = await row(p1);
      expect(r.salonStatus, 'active');
      expect(r.validationSent, isTrue);
      expect(r.validation, info.validation);
    });

    test('a salon added on the web is a draft that never asked — on BOTH '
        'reads', () async {
      final auth = await signInOwner();
      final added = seedWebAddedSalon(auth.provider!, name: 'Salon Trois');
      final info = await me(added);
      expect(info.salon.status, 'draft');
      expect(info.validationSent, isTrue);
      expect(info.validation, isNull);
      final r = await row(added);
      expect(r.salonStatus, 'draft');
      expect(r.validationSent, isTrue);
      expect(r.validation, isNull);
    });

    test('resetTeam clears every status and restores the seeded '
        'validations', () async {
      MockData.seedRefused(p1, code: 'photos', note: 'Floues');
      MockData.seedSuspended(const SalonId('provider2'));
      MockData.resetTeam();
      expect(MockData.salonStatuses, isEmpty);
      expect(
        MockData.salonValidations[p1],
        const SalonValidation(
          state: SalonValidationState.approved,
          wentLive: true,
        ),
      );
      expect(MockData.salonValidations.keys.toSet(), MockData.seededSalonIds);
    });
  });

  group('the publish is a request (§3.1) — no trial', () {
    test('never asked → 202 pending from now; both reads show it; no '
        'trial', () async {
      await signInOwner();
      MockData.seedNeverAsked(p1);
      final res = await publish();
      expect(res.success, isTrue);
      final out = res.data!;
      expect(out.isLive, isFalse);
      expect(out.validation!.state, SalonValidationState.pending);
      expect(out.validation!.submittedAt, isNotNull);
      expect(out.saysRequestSent, isTrue);

      expect((await me()).validation, out.validation);
      expect((await row(p1)).validation, out.validation);
      expect((await me()).salon.status, 'draft', reason: 'still a draft');
      expect((await subs.getSalonSubscription(p1)).code, 'no_offer');
    });

    test('already pending → 202, the same body (no second request)', () async {
      await signInOwner();
      final at = DateTime.utc(2026, 11, 12, 9);
      MockData.seedPendingRequest(p1, submittedAt: at);
      final out = (await publish()).data!;
      expect(out.validation!.state, SalonValidationState.pending);
      expect(out.validation!.submittedAt, at);
    });

    test('refused for a reason the salon can fix → a new request, the '
        'refusal cleared', () async {
      await signInOwner();
      MockData.seedRefused(p1, code: 'photos', note: 'Floues');
      final out = (await publish()).data!;
      expect(out.validation!.state, SalonValidationState.pending);
      expect(out.validation!.refusal, isNull);
    });

    test('refused for a final reason → 409 validation_refused_final, « Mise '
        'en ligne refusée », nothing written', () async {
      await signInOwner();
      MockData.seedRefused(p1, code: 'outside_ci');
      final before = MockData.salonValidations[p1];
      final res = await publish();
      expect(res.success, isFalse);
      expect(res.code, 'validation_refused_final');
      expect(res.error, 'Mise en ligne refusée');
      expect(MockData.salonValidations[p1], before);
    });

    test('approved, never live (the validation finishing) → 202, said as '
        'a request', () async {
      await signInOwner();
      MockData.seedFinishing(p1);
      final out = (await publish()).data!;
      expect(out.isLive, isFalse);
      expect(out.validation!.isFinishing, isTrue);
      expect(out.saysRequestSent, isTrue);
    });

    test('validated and live once, back to draft, a live offer → the '
        'republish: 200 and active', () async {
      await signInOwner();
      subs.startTrialIfAbsent(p1);
      MockData.seedOffline(p1);
      final res = await publish();
      expect(res.data, const PublishOutcome.live());
      expect((await me()).salon.status, isNull);
      expect((await row(p1)).salonStatus, 'active');
    });

    test(
      '… with no live offer row → 409 offer (the billing pointer)',
      () async {
        await signInOwner();
        MockData.seedOffline(p1);
        final res = await publish();
        expect(res.code, 'offer_required');
        expect(MockData.salonStatuses[p1], 'draft');
      },
    );

    test('already active → 200, idempotent', () async {
      await signInOwner();
      expect((await publish()).data, const PublishOutcome.live());
    });

    test('suspended → 403 provider_suspended, today\'s sentence, before '
        'anything else', () async {
      await signInOwner();
      MockData.seedNeverAsked(p1);
      MockData.seedSuspended(p1);
      final res = await publish();
      expect(res.code, 'provider_suspended');
      expect(
        res.error,
        'Votre salon est suspendu. Contactez MyWeli pour le réactiver — vos '
        'rendez-vous sont intacts.',
      );
      expect(MockData.salonValidations[p1], isNull, reason: 'nothing asked');
    });
  });

  group('the admin\'s hooks (§3.2, §3.3)', () {
    test('validate a pending request: the decision, the salon\'s ONE trial on '
        'Pro, then live', () async {
      await signInOwner();
      MockData.seedPendingRequest(p1);
      final res = await pro.validateSalonForTests(p1);
      expect(res.success, isTrue);
      expect(res.data!.state, SalonValidationState.approved);
      expect(res.data!.wentLive, isTrue);
      expect(res.data!.decidedAt, isNotNull);
      final offer = (await subs.getSalonSubscription(p1)).data!;
      expect(offer.status, SalonOfferStatus.trial);
      expect(offer.tier, SalonTier.pro);
      expect((await me()).salon.status, isNull);
      expect((await row(p1)).salonStatus, 'active');
    });

    test('validate from « Refusés », and finish an interrupted '
        'validation', () async {
      await signInOwner();
      MockData.seedRefused(p1, code: 'outside_ci');
      expect((await pro.validateSalonForTests(p1)).success, isTrue);
      MockData.seedFinishing(const SalonId('provider2'));
      final finished = await pro.validateSalonForTests(
        const SalonId('provider2'),
      );
      expect(finished.data!.wentLive, isTrue);
    });

    test('validate refuses what is not waiting, a suspension and a lapsed '
        'offer — nothing written', () async {
      await signInOwner();
      expect(
        (await pro.validateSalonForTests(p1)).code,
        'validation_not_pending',
        reason: 'already live',
      );
      MockData.seedNeverAsked(p1);
      expect(
        (await pro.validateSalonForTests(p1)).code,
        'validation_not_pending',
      );
      MockData.seedPendingRequest(p1);
      MockData.seedSuspended(p1);
      expect((await pro.validateSalonForTests(p1)).code, 'provider_suspended');
      expect(
        MockData.salonValidations[p1]!.state,
        SalonValidationState.pending,
      );
    });

    test('refuse a pending request: the code, the trimmed note, final by '
        'code; the salon stays a draft', () async {
      await signInOwner();
      MockData.seedPendingRequest(p1);
      final res = await pro.refuseSalonForTests(
        p1,
        code: 'test_salon',
        note: '  Salon de démonstration ',
      );
      expect(res.success, isTrue);
      expect(
        res.data!.refusal,
        const SalonRefusal(
          code: 'test_salon',
          note: 'Salon de démonstration',
          isFinal: true,
        ),
      );
      expect(MockData.salonStatuses[p1], 'draft');
      expect((await publish()).code, 'validation_refused_final');
    });

    test('refuse checks the input as the server does, and only a pending '
        'request', () async {
      await signInOwner();
      MockData.seedPendingRequest(p1);
      expect(
        (await pro.refuseSalonForTests(p1, code: 'other')).code,
        'note_required',
      );
      expect(
        (await pro.refuseSalonForTests(p1, code: 'nope')).code,
        'invalid_input',
      );
      expect(
        MockData.salonValidations[p1]!.state,
        SalonValidationState.pending,
      );
      MockData.seedFinishing(p1);
      expect(
        (await pro.refuseSalonForTests(p1, code: 'photos')).code,
        'validation_not_pending',
      );
    });
  });

  group('who reads what (backend salon_validation_view.dart)', () {
    test('the owner reads the note and `offerLive`; a member who is not the '
        'owner reads the state and the code only', () async {
      MockData.seedRefused(p1, code: 'photos', note: 'Floues');
      await signInOwner();
      expect((await me()).validation!.refusal!.note, 'Floues');
      await serviceLocator.authService.logoutProvider();

      await signIn('awa.manager@myweli.test');
      final member = await me();
      expect(member.validation!.state, SalonValidationState.refused);
      expect(member.validation!.refusal!.code, 'photos');
      expect(member.validation!.refusal!.note, isNull);
      expect((await row(p1)).validation!.refusal!.note, isNull);
    });

    test('`offerLive` only for a validated salon not live: true with a live '
        'offer, false without; never for a member who is not the '
        'owner', () async {
      MockData.seedOffline(p1);
      await signInOwner();
      expect((await me()).validation!.offerLive, isFalse);
      subs.startTrialIfAbsent(p1);
      expect((await me()).validation!.offerLive, isTrue);
      expect((await row(p1)).validation!.offerLive, isTrue);
      await serviceLocator.authService.logoutProvider();

      await signIn('awa.manager@myweli.test');
      expect((await me()).validation!.offerLive, isNull);
    });

    test('CONTROL: a live salon carries no `offerLive`', () async {
      await signInOwner();
      expect((await me()).validation!.offerLive, isNull);
    });
  });
}
