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
/// model, the setup→choose→trial arc (ONE trial, switches keep the clock),
/// grace/expired states and the API path/status mapping.
void main() {
  SalonSubscription sample({
    SalonOfferStatus status = SalonOfferStatus.trial,
    bool unpublished = false,
  }) =>
      SalonSubscription(
        tier: SalonTier.pro,
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

  group('MockSubscriptionService — the offer arc', () {
    test('defaults to SETUP (no offer) → code no_offer', () async {
      final res =
          await MockSubscriptionService().getSalonSubscription('provider1');
      expect(res.success, isFalse);
      expect(res.code, 'no_offer');
    });

    test(
        'first choice starts the ONE 3-month trial; a switch keeps the '
        'clock and changes the cap', () async {
      final svc = MockSubscriptionService();
      final chosen = await svc.chooseOffer('provider1', SalonTier.pro);
      expect(chosen.success, isTrue);
      expect(chosen.data!.status, SalonOfferStatus.trial);
      expect(chosen.data!.seats.cap, 5);
      final firstEnd = chosen.data!.trialEndsAt;

      final switched = await svc.chooseOffer('provider1', SalonTier.business);
      expect(switched.success, isTrue);
      expect(switched.data!.tier, SalonTier.business);
      expect(switched.data!.trialEndsAt, firstEnd);
      expect(switched.data!.seats.cap, 15);
    });

    test('expired → choose is trial_used (payment is manual)', () async {
      final svc = MockSubscriptionService(
        initial: sample(status: SalonOfferStatus.expired, unpublished: true),
      );
      final res = await svc.chooseOffer('provider1', SalonTier.pro);
      expect(res.success, isFalse);
      expect(res.code, 'trial_used');

      final state = await svc.getSalonSubscription('provider1');
      expect(state.data!.unpublishedForBilling, isTrue);
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

    test('PUT {tier} → 200 state; 409 preserves trial_used', () async {
      var call = 0;
      final svc = ApiProSubscriptionService(
        client: MockClient((req) async {
          expect(req.method, 'PUT');
          expect(
            (jsonDecode(req.body) as Map<String, dynamic>)['tier'],
            'reseau',
          );
          call++;
          if (call == 1) {
            return http.Response(
              jsonEncode({
                'tier': 'reseau',
                'status': 'trial',
                'trialEndsAt': '2026-10-01T00:00:00.000Z',
                'graceEndsAt': '2026-10-08T00:00:00.000Z',
                'unpublishedForBilling': false,
                'seats': {'cap': 15, 'used': 1},
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'error': 'trial_used'}), 409);
        }),
        baseUrl: 'http://x',
        providerSessionStore: await connectedStore(),
      );
      final ok = await svc.chooseOffer('p1', SalonTier.reseau);
      expect(ok.success, isTrue);
      expect(ok.data!.tier, SalonTier.reseau);

      final used = await svc.chooseOffer('p1', SalonTier.reseau);
      expect(used.success, isFalse);
      expect(used.code, 'trial_used');
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
      registerFallbackValue(SalonTier.pro);
      service = _MockSubscriptionService();
      serviceLocator.subscriptionService = service;
    });

    setUp(() => reset(service));

    test('load populates the salon state', () async {
      when(() => service.getSalonSubscription('p1'))
          .thenAnswer((_) async => ApiResponse.success(sample()));
      final p = ProSubscriptionProvider();
      await p.load('p1');
      expect(p.salon!.seats.used, 2);
      expect(p.isSetup, isFalse);
      expect(p.loadFailed, isFalse);
    });

    test('no_offer maps to the explicit SETUP state (not an error)', () async {
      when(() => service.getSalonSubscription('p1'))
          .thenAnswer((_) async => ApiResponse.error('', code: 'no_offer'));
      final p = ProSubscriptionProvider();
      await p.load('p1');
      expect(p.isSetup, isTrue);
      expect(p.salon, isNull);
      expect(p.loadFailed, isFalse);
    });

    test('load failure sets loadFailed', () async {
      when(() => service.getSalonSubscription('p1'))
          .thenAnswer((_) async => ApiResponse.error('boom'));
      final p = ProSubscriptionProvider();
      await p.load('p1');
      expect(p.loadFailed, isTrue);
      expect(p.salon, isNull);
    });

    test(
        'choose success updates the state in place; trial_used surfaces '
        'its code', () async {
      when(() => service.getSalonSubscription('p1'))
          .thenAnswer((_) async => ApiResponse.error('', code: 'no_offer'));
      when(() => service.chooseOffer('p1', SalonTier.pro))
          .thenAnswer((_) async => ApiResponse.success(sample()));
      final p = ProSubscriptionProvider();
      await p.load('p1');
      expect(await p.choose('p1', SalonTier.pro), isTrue);
      expect(p.isSetup, isFalse);
      expect(p.salon!.tier, SalonTier.pro);

      when(() => service.chooseOffer('p1', SalonTier.business)).thenAnswer(
        (_) async => ApiResponse.error('essai utilisé', code: 'trial_used'),
      );
      expect(await p.choose('p1', SalonTier.business), isFalse);
      expect(p.chooseErrorCode, 'trial_used');
    });
  });
}
