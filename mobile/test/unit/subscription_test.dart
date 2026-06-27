import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/subscription.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/services/api/api_pro_subscription_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/interfaces/subscription_service_interface.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

class _MockSubscriptionService extends Mock
    implements SubscriptionServiceInterface {}

void main() {
  group('Subscription model', () {
    test('parses a trialing subscription', () {
      final s = Subscription.fromJson(const {
        'tier': 'pro',
        'status': 'trial',
        'trialEndsAt': '2026-09-01T00:00:00.000Z',
        'trialDaysLeft': 62,
      });
      expect(s.tier, SubscriptionTier.pro);
      expect(s.status, SubscriptionStatus.trial);
      expect(s.isTrialing, isTrue);
      expect(s.trialDaysLeft, 62);
    });

    test('unknown enum values fall back safely', () {
      final s = Subscription.fromJson(const {
        'tier': 'galaxy',
        'status': 'wat',
        'trialDaysLeft': 0,
      });
      expect(s.tier, SubscriptionTier.free);
      expect(s.status, SubscriptionStatus.free);
      expect(s.trialEndsAt, isNull);
    });
  });

  group('MockSubscriptionService', () {
    test('returns a trialing Pro subscription', () async {
      final res = await MockSubscriptionService().getSubscription();
      expect(res.success, isTrue);
      expect(res.data!.tier, SubscriptionTier.pro);
      expect(res.data!.isTrialing, isTrue);
    });
  });

  group('ApiProSubscriptionService', () {
    test('parses GET /me/subscription', () async {
      final store = InMemorySessionStore();
      await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
      final svc = ApiProSubscriptionService(
        client: MockClient((req) async {
          expect(req.url.path, '/me/subscription');
          return http.Response(
            jsonEncode({
              'tier': 'pro',
              'status': 'trial',
              'trialEndsAt': '2026-09-01T00:00:00.000Z',
              'trialDaysLeft': 62,
            }),
            200,
          );
        }),
        baseUrl: 'http://x',
        providerSessionStore: store,
      );
      final res = await svc.getSubscription();
      expect(res.success, isTrue);
      expect(res.data!.trialDaysLeft, 62);
    });

    test('not connected → error', () async {
      final svc = ApiProSubscriptionService(
        client: MockClient((_) async => http.Response('{}', 200)),
        baseUrl: 'http://x',
        providerSessionStore: InMemorySessionStore(),
      );
      expect((await svc.getSubscription()).success, isFalse);
    });
  });

  group('ProSubscriptionProvider', () {
    late _MockSubscriptionService service;

    setUpAll(() {
      service = _MockSubscriptionService();
      serviceLocator.subscriptionService = service;
    });

    setUp(() => reset(service));

    test('load populates the subscription', () async {
      when(() => service.getSubscription()).thenAnswer(
        (_) async => ApiResponse.success(
          const Subscription(
            tier: SubscriptionTier.pro,
            status: SubscriptionStatus.trial,
            trialEndsAt: null,
            trialDaysLeft: 30,
          ),
        ),
      );
      final p = ProSubscriptionProvider();
      await p.load();
      expect(p.subscription!.trialDaysLeft, 30);
      expect(p.loadFailed, isFalse);
    });

    test('load failure sets loadFailed', () async {
      when(() => service.getSubscription())
          .thenAnswer((_) async => ApiResponse.error('boom'));
      final p = ProSubscriptionProvider();
      await p.load();
      expect(p.loadFailed, isTrue);
      expect(p.subscription, isNull);
    });
  });
}
