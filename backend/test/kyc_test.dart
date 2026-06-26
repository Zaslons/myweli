import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/kyc_service.dart';
import 'package:test/test.dart';

import '../routes/me/kyc.dart' as kyc_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late InMemoryProviderAuthRepository providerAuth;
  late KycService service;
  final tokens = TokenService(secret: 'test-secret');
  late String accountId;
  late String token;

  setUp(() async {
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    service = KycService(providerAuth);
    final reg = await providerAuth.register(
      phoneNumber: '+2250500000070',
      businessName: 'X',
      businessType: 'salon',
    );
    accountId = reg.provider!.id;
    token = tokens.issueAccessToken(subject: accountId, role: 'provider').token;
  });

  List<Map<String, dynamic>> docs() => [
    {'type': 'idCard', 'fileName': 'id.jpg', 'key': 'kyc/$accountId/a.jpg'},
    {'type': 'selfie', 'fileName': 's.jpg', 'key': 'kyc/$accountId/b.jpg'},
  ];

  group('KycService', () {
    test('submit stores docs + sets pending; status reads back', () async {
      final r = await service.submit(accountId, docs());
      expect(r.ok, isTrue);
      expect(r.data!['status'], 'pending');
      expect((r.data!['documents'] as List).length, 2);
      final first = (r.data!['documents'] as List).first as Map;
      expect(first['type'], 'idCard');
      expect(first['submittedAt'], isNotNull); // server-stamped

      final got = await service.status(accountId);
      expect((got.data!['documents'] as List).length, 2);
    });

    test('resubmit clears a prior rejection back to pending', () async {
      (await providerAuth.accountById(accountId))!
        ..verificationStatus = 'rejected'
        ..rejectionReason = 'Blurry ID';
      final r = await service.submit(accountId, docs());
      expect(r.data!['status'], 'pending');
      expect(r.data!['rejectionReason'], isNull);
    });

    test('rejects bad type / foreign key / empty', () async {
      expect(
        (await service.submit(accountId, [
          {'type': 'passport', 'key': 'kyc/$accountId/a.jpg'},
        ])).error,
        'invalid_input',
      );
      // A key under another account's prefix is rejected.
      expect(
        (await service.submit(accountId, [
          {'type': 'idCard', 'key': 'kyc/someone_else/a.jpg'},
        ])).error,
        'invalid_input',
      );
      expect(
        (await service.submit(accountId, const [])).error,
        'invalid_input',
      );
    });
  });

  group('route', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<KycService>()).thenReturn(service);
      return context;
    }

    Request req(String method, {String? bearer, Object? body}) => Request(
      method,
      Uri.parse('http://localhost/me/kyc'),
      headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
      body: body == null ? null : '{"documents":${_json(docs())}}',
    );

    test('GET → 200; POST → 200 pending; no token → 401; user → 403; '
        'bad verb → 405', () async {
      final post = await kyc_route.onRequest(
        ctx(req('POST', bearer: token, body: docs())),
      );
      expect(post.statusCode, HttpStatus.ok);
      expect((await post.json() as Map)['status'], 'pending');

      final get = await kyc_route.onRequest(ctx(req('GET', bearer: token)));
      expect(get.statusCode, HttpStatus.ok);

      final noAuth = await kyc_route.onRequest(ctx(req('GET')));
      expect(noAuth.statusCode, HttpStatus.unauthorized);

      final userTok = tokens
          .issueAccessToken(subject: 'u1', role: 'user')
          .token;
      final asUser = await kyc_route.onRequest(
        ctx(req('GET', bearer: userTok)),
      );
      expect(asUser.statusCode, HttpStatus.forbidden);

      final badVerb = await kyc_route.onRequest(
        ctx(req('DELETE', bearer: token)),
      );
      expect(badVerb.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}

/// Tiny JSON-array encoder for the fixture docs (avoids importing convert here).
String _json(List<Map<String, dynamic>> docs) {
  final parts = docs.map(
    (d) =>
        '{"type":"${d['type']}","fileName":"${d['fileName']}",'
        '"key":"${d['key']}"}',
  );
  return '[${parts.join(',')}]';
}
