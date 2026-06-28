import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../routes/me/provider/index.dart' as me_provider;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockProviderAuth extends Mock implements ProviderAuthRepository {}

class _MockProviders extends Mock implements ProvidersRepository {}

ProviderAccount _account({String? providerId}) => ProviderAccount(
  id: 'acc1',
  phoneNumber: '+2250700000009',
  businessName: 'Salon Awa',
  businessType: 'salon',
  createdAt: DateTime.utc(2026),
)..providerId = providerId;

void main() {
  group('GET /me/provider', () {
    final tokens = TokenService(secret: 'test-secret');
    late _MockProviderAuth auth;
    late _MockProviders providers;

    setUp(() {
      auth = _MockProviderAuth();
      providers = _MockProviders();
    });

    RequestContext ctx(Request request) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<ProviderAuthRepository>()).thenReturn(auth);
      when(() => c.read<ProvidersRepository>()).thenReturn(providers);
      return c;
    }

    Request req(String method, {String? token}) => Request(
      method,
      Uri.parse('http://localhost/me/provider'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );

    String tok(String sub, String role) =>
        tokens.issueAccessToken(subject: sub, role: role).token;

    test('linked provider → 200 {account, provider}', () async {
      when(
        () => auth.accountById('acc1'),
      ).thenAnswer((_) async => _account(providerId: 'p1'));
      when(
        () => providers.byId('p1'),
      ).thenAnswer((_) async => {'id': 'p1', 'name': 'Salon Awa'});

      final res = await me_provider.onRequest(
        ctx(req('GET', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.ok);
      final m = await res.json() as Map;
      expect((m['account'] as Map)['businessName'], 'Salon Awa');
      expect((m['provider'] as Map)['id'], 'p1');
    });

    test('anonymous → 401', () async {
      final res = await me_provider.onRequest(ctx(req('GET')));
      expect(res.statusCode, HttpStatus.unauthorized);
    });

    test('non-provider role → 403', () async {
      final res = await me_provider.onRequest(
        ctx(req('GET', token: tok('u1', 'user'))),
      );
      expect(res.statusCode, HttpStatus.forbidden);
    });

    test('provider with no linked salon → 403', () async {
      when(
        () => auth.accountById('acc1'),
      ).thenAnswer((_) async => _account(providerId: null));
      final res = await me_provider.onRequest(
        ctx(req('GET', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.forbidden);
    });

    test('linked salon missing → 404', () async {
      when(
        () => auth.accountById('acc1'),
      ).thenAnswer((_) async => _account(providerId: 'gone'));
      when(() => providers.byId('gone')).thenAnswer((_) async => null);
      final res = await me_provider.onRequest(
        ctx(req('GET', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.notFound);
    });

    test('unsupported verb → 405', () async {
      final res = await me_provider.onRequest(
        ctx(req('POST', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
