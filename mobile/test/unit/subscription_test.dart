import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/services/api/api_pro_subscription_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/interfaces/subscription_service_interface.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

class _MockSubscriptionService extends Mock
    implements SubscriptionServiceInterface {}

/// Team access R3 (docs/design/team-access-r3-app.md §2.4): the salon offer
/// model, the mock's setup → first-publish trial arc (ONE trial per salon,
/// insert-if-absent — docs/design/pro-companion-path.md §3.1), grace/expired
/// states and the API path/status mapping. The app reads the offer and never
/// writes it: the choose/switch tests left with the picker.
void main() {
  SalonSubscription sample({
    SalonTier tier = SalonTier.pro,
    SalonOfferStatus status = SalonOfferStatus.trial,
    bool unpublished = false,
  }) => SalonSubscription(
    tier: tier,
    status: status,
    trialEndsAt: DateTime.now().add(const Duration(days: 30)),
    graceEndsAt: DateTime.now().add(const Duration(days: 37)),
    unpublishedForBilling: unpublished,
    seats: const SalonSeats(cap: 5, used: 2),
  );

  group('SalonSubscription model', () {
    test('parses the full DTO', () {
      final s = SalonSubscription.fromJson(const {
        'tier': 'business',
        'status': 'grace',
        'trialEndsAt': '2026-09-01T00:00:00.000Z',
        'paidUntil': null,
        'graceEndsAt': '2026-09-08T00:00:00.000Z',
        'unpublishedForBilling': false,
        'seats': {'cap': 15, 'used': 4},
      });
      expect(s.tier, SalonTier.business);
      expect(s.status, SalonOfferStatus.grace);
      expect(s.isLive, isTrue); // grace still operates
      expect(s.seats.cap, 15);
      expect(s.seats.used, 4);
      expect(s.tierLabel, 'Business');
    });

    test('unknown enums fall back safely; expired is not live', () {
      final s = SalonSubscription.fromJson(const {
        'tier': 'galaxy',
        'status': 'wat',
        'seats': <String, dynamic>{},
      });
      expect(s.tier, SalonTier.pro);
      expect(s.status, SalonOfferStatus.expired);
      expect(s.isLive, isFalse);
      expect(s.seats.cap, 0);
    });

    test('trialDaysLeft derives and clamps at zero', () {
      expect(sample().trialDaysLeft, greaterThan(0));
      final past = SalonSubscription(
        tier: SalonTier.pro,
        status: SalonOfferStatus.expired,
        trialEndsAt: DateTime.now().subtract(const Duration(days: 10)),
        graceEndsAt: DateTime.now().subtract(const Duration(days: 3)),
        seats: const SalonSeats(cap: 5, used: 1),
      );
      expect(past.trialDaysLeft, 0);
    });
  });

  group('MockSubscriptionService — the offer arc (server mirror)', () {
    test('defaults to SETUP (no offer) → code no_offer', () async {
      final res = await MockSubscriptionService().getSalonSubscription(
        'provider1',
      );
      expect(res.success, isFalse);
      expect(res.code, 'no_offer');
    });

    test('startTrialIfAbsent: no row → the ONE 90-day trial on the given '
        'tier, with that tier\'s cap (pro-companion-path §3.1)', () async {
      final svc = MockSubscriptionService();
      expect(svc.startTrialIfAbsent('provider1'), isTrue);
      final state = await svc.getSalonSubscription('provider1');
      expect(state.data!.status, SalonOfferStatus.trial);
      expect(state.data!.tier, SalonTier.pro);
      expect(state.data!.seats.cap, 5);
      expect(
        state.data!.trialEndsAt.difference(DateTime.now()).inDays,
        inInclusiveRange(89, 90),
      );

      expect(svc.startTrialIfAbsent('salon_b', tier: SalonTier.reseau), isTrue);
      final reseau = await svc.getSalonSubscription('salon_b');
      expect(reseau.data!.tier, SalonTier.reseau);
      expect(reseau.data!.seats.cap, 15);
    });

    test('startTrialIfAbsent never replaces a row: a web choice, a running '
        'trial or an EXPIRED offer stays exactly as it is', () async {
      // A web choice (Business) made before the first publish.
      final chosen = MockSubscriptionService(
        initial: sample(tier: SalonTier.business),
      );
      expect(chosen.startTrialIfAbsent('provider1'), isFalse);
      expect(
        (await chosen.getSalonSubscription('provider1')).data!.tier,
        SalonTier.business,
      );

      // Expired: never a second trial.
      final expired = MockSubscriptionService(
        initial: sample(status: SalonOfferStatus.expired, unpublished: true),
      );
      expect(expired.startTrialIfAbsent('provider1'), isFalse);
      final state = await expired.getSalonSubscription('provider1');
      expect(state.data!.status, SalonOfferStatus.expired);
      expect(state.data!.unpublishedForBilling, isTrue);

      // A second start on the same salon is a no-op too.
      final svc = MockSubscriptionService();
      expect(svc.startTrialIfAbsent('p'), isTrue);
      final first = (await svc.getSalonSubscription('p')).data!.trialEndsAt;
      expect(svc.startTrialIfAbsent('p', tier: SalonTier.reseau), isFalse);
      final again = (await svc.getSalonSubscription('p')).data!;
      expect(again.tier, SalonTier.pro);
      expect(again.trialEndsAt, first);
    });
  });

  group('ApiProSubscriptionService', () {
    Future<InMemorySessionStore> connectedStore() async {
      final store = InMemorySessionStore();
      await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
      return store;
    }

    test('GET /providers/{id}/subscription parses; 404 → no_offer', () async {
      var call = 0;
      final svc = ApiProSubscriptionService(
        client: MockClient((req) async {
          expect(req.url.path, '/providers/p1/subscription');
          call++;
          if (call == 1) {
            return http.Response(
              jsonEncode({
                'tier': 'pro',
                'status': 'trial',
                'trialEndsAt': '2026-09-01T00:00:00.000Z',
                'graceEndsAt': '2026-09-08T00:00:00.000Z',
                'unpublishedForBilling': false,
                'seats': {'cap': 5, 'used': 1},
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'error': 'not_found'}), 404);
        }),
        baseUrl: 'http://x',
        providerSessionStore: await connectedStore(),
      );
      final ok = await svc.getSalonSubscription('p1');
      expect(ok.success, isTrue);
      expect(ok.data!.seats.cap, 5);

      final setup = await svc.getSalonSubscription('p1');
      expect(setup.success, isFalse);
      expect(setup.code, 'no_offer');
    });

    test('not connected → error', () async {
      final svc = ApiProSubscriptionService(
        client: MockClient((_) async => http.Response('{}', 200)),
        baseUrl: 'http://x',
        providerSessionStore: InMemorySessionStore(),
      );
      expect((await svc.getSalonSubscription('p1')).success, isFalse);
    });
  });

  group('ProSubscriptionProvider', () {
    late _MockSubscriptionService service;

    setUpAll(() {
      service = _MockSubscriptionService();
      serviceLocator.subscriptionService = service;
    });

    setUp(() => reset(service));

    test('load populates the salon state', () async {
      when(
        () => service.getSalonSubscription('p1'),
      ).thenAnswer((_) async => ApiResponse.success(sample()));
      final p = ProSubscriptionProvider();
      await p.load('p1');
      expect(p.salon!.seats.used, 2);
      expect(p.isSetup, isFalse);
      expect(p.loadFailed, isFalse);
    });

    test('no_offer maps to the explicit SETUP state (not an error)', () async {
      when(
        () => service.getSalonSubscription('p1'),
      ).thenAnswer((_) async => ApiResponse.error('', code: 'no_offer'));
      final p = ProSubscriptionProvider();
      await p.load('p1');
      expect(p.isSetup, isTrue);
      expect(p.salon, isNull);
      expect(p.loadFailed, isFalse);
    });

    test('load failure sets loadFailed', () async {
      when(
        () => service.getSalonSubscription('p1'),
      ).thenAnswer((_) async => ApiResponse.error('boom'));
      final p = ProSubscriptionProvider();
      await p.load('p1');
      expect(p.loadFailed, isTrue);
      expect(p.salon, isNull);
    });
  });
}
