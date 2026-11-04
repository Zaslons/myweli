import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/salon_facts.dart';
import 'package:myweli/models/salon_market.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

Map<String, dynamic> _providerJson() => {
  'id': 'provider_1',
  'phoneNumber': '+2250700000001',
  'businessName': 'Élégance',
  'businessType': 'salon',
  'verificationStatus': 'pending',
  'kycDocs': const <Map<String, dynamic>>[],
  'createdAt': DateTime(2026).toIso8601String(),
  'providerId': 'provider1',
};

const _facts = SalonFacts(
  salonId: SalonId('provider1'),
  name: 'Salon Excellence',
  category: 'salon',
  address: 'Cocody, Riviera 2',
  phoneNumber: '+2250700000002',
);

/// docs/design/product-questions-batch8.md §2.3 (B8.3, decision 29) — the
/// API service keeps the « Profil » salon facts INSIDE the persisted provider
/// session, like the market: they survive a restart, `null` clears them, a
/// signed-out store keeps nothing, and a session from before has none.
void main() {
  ApiAuthService serviceOn(SessionStore store) => ApiAuthService(
    client: MockClient(
      (req) async => http.Response(
        jsonEncode({
          'provider': _providerJson(),
          'accessToken': 'prov-123',
          'refreshToken': 'prov-refresh',
        }),
        200,
      ),
    ),
    baseUrl: 'http://x',
    providerSessionStore: store,
  );

  Future<ApiAuthService> signedIn(SessionStore store) async {
    final service = serviceOn(store);
    final login = await service.verifyProviderEmailOtp('salon@x.com', '123456');
    expect(login.signedIn, isTrue, reason: 'the scenario');
    return service;
  }

  test('survive a restart, next to the market', () async {
    final store = InMemorySessionStore();
    final service = await signedIn(store);
    await service.cacheProviderSalonMarket(
      const SalonMarket(
        salonId: SalonId('provider1'),
        timezone: 'Africa/Abidjan',
      ),
    );
    await service.cacheProviderSalonFacts(_facts);

    final restarted = serviceOn(store);
    expect(await restarted.getCachedProviderSalonFacts(), _facts);
    expect(
      (await restarted.getCachedProviderSalonMarket())?.salonId,
      'provider1',
    );
  });

  test('null CLEARS them — the market kept', () async {
    final store = InMemorySessionStore();
    final service = await signedIn(store);
    await service.cacheProviderSalonMarket(
      const SalonMarket(salonId: SalonId('provider1')),
    );
    await service.cacheProviderSalonFacts(_facts);

    await service.cacheProviderSalonFacts(null);

    expect(await service.getCachedProviderSalonFacts(), isNull);
    expect(await service.getCachedProviderSalonMarket(), isNotNull);
  });

  test('a sign-out drops them with the session', () async {
    final store = InMemorySessionStore();
    final service = await signedIn(store);
    await service.cacheProviderSalonFacts(_facts);

    await service.logoutProvider();

    expect(await service.getCachedProviderSalonFacts(), isNull);
  });

  test('signed out: nothing to cache into, nothing to read', () async {
    final store = InMemorySessionStore();
    final service = serviceOn(store);
    await service.cacheProviderSalonFacts(_facts);
    expect(await store.read(), isNull);
    expect(await service.getCachedProviderSalonFacts(), isNull);
  });

  test('a session stored before B8.3 reads with none', () async {
    final store = InMemorySessionStore();
    await store.save(
      jsonEncode({
        'token': 'prov-123',
        'refreshToken': 'r',
        'provider': _providerJson(),
      }),
    );

    expect(await serviceOn(store).getCachedProviderSalonFacts(), isNull);
  });
}
