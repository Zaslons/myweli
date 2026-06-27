import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/subscription/subscription.dart';
import 'package:test/test.dart';

import '../routes/me/subscription.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockProviderAuth extends Mock implements ProviderAuthRepository {}

ProviderAccount _account(DateTime createdAt) => ProviderAccount(
  id: 'prov1',
  phoneNumber: '+2250700000001',
  businessName: 'Salon X',
  businessType: 'salon',
  createdAt: createdAt,
);

void main() {
  group('computeSubscription', () {
    final now = DateTime.utc(2026, 6, 28, 12);

    test('within trial → pro/trial with days-left rounded up', () {
      final s = computeSubscription(
        accountCreatedAt: now.subtract(const Duration(days: 10)),
        now: now,
      );
      expect(s.tier, 'pro');
      expect(s.status, 'trial');
      expect(s.trialDaysLeft, 80); // 90 - 10
    });

    test('partial day rounds up', () {
      final s = computeSubscription(
        accountCreatedAt: now.subtract(const Duration(days: 89, hours: 12)),
        now: now,
      );
      expect(s.trialDaysLeft, 1); // 12h left → 1 day
    });

    test('after trial → free', () {
      final s = computeSubscription(
        accountCreatedAt: now.subtract(const Duration(days: 100)),
        now: now,
      );
      expect(s.tier, 'free');
      expect(s.status, 'free');
      expect(s.trialDaysLeft, 0);
    });
  });

  group('GET /me/subscription', () {
    final tokens = TokenService(secret: 'test-secret');
    late _MockProviderAuth providers;

    setUp(() => providers = _MockProviderAuth());

    RequestContext ctx(Request request) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<ProviderAuthRepository>()).thenReturn(providers);
      return c;
    }

    Request req(String method, {String? token}) => Request(
      method,
      Uri.parse('http://localhost/me/subscription'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );

    String tok(String sub, {String role = 'provider'}) =>
        tokens.issueAccessToken(subject: sub, role: role).token;

    test('provider in trial → 200 with derived shape', () async {
      when(() => providers.accountById('prov1')).thenAnswer(
        (_) async =>
            _account(DateTime.now().toUtc().subtract(const Duration(days: 5))),
      );
      final res = await route.onRequest(ctx(req('GET', token: tok('prov1'))));
      expect(res.statusCode, HttpStatus.ok);
      final body = await res.json() as Map;
      expect(body['tier'], 'pro');
      expect(body['status'], 'trial');
      expect(body['trialDaysLeft'], greaterThan(80));
    });

    test('non-provider → 403', () async {
      final res = await route.onRequest(
        ctx(req('GET', token: tok('u1', role: 'user'))),
      );
      expect(res.statusCode, HttpStatus.forbidden);
    });

    test('anon → 401', () async {
      final res = await route.onRequest(ctx(req('GET')));
      expect(res.statusCode, HttpStatus.unauthorized);
    });

    test('missing account → 404', () async {
      when(() => providers.accountById(any())).thenAnswer((_) async => null);
      final res = await route.onRequest(ctx(req('GET', token: tok('ghost'))));
      expect(res.statusCode, HttpStatus.notFound);
    });

    test('non-GET → 405', () async {
      when(
        () => providers.accountById(any()),
      ).thenAnswer((_) async => _account(DateTime.now().toUtc()));
      final res = await route.onRequest(ctx(req('POST', token: tok('prov1'))));
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
