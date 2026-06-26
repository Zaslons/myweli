import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:myweli_backend/src/upload_signing_service.dart';
import 'package:test/test.dart';

import '../routes/uploads/sign.dart' as sign_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  group('StorageService', () {
    test('FakeStorageService returns deterministic fake URLs', () {
      const s = FakeStorageService();
      final post = s.presignPost(
        key: 'gallery/p1/abc.jpg',
        contentType: 'image/jpeg',
        maxBytes: 100,
      );
      expect(post.url, startsWith('https://fake-storage.local'));
      expect(post.fields['key'], 'gallery/p1/abc.jpg');
      expect(
        s.publicUrl('gallery/p1/abc.jpg'),
        'https://fake-storage.local/gallery/p1/abc.jpg',
      );
    });

    test('R2StorageService signs a presigned POST policy', () {
      final r2 = R2StorageService(
        endpoint: 'https://acc.r2.cloudflarestorage.com',
        bucket: 'uploads',
        accessKeyId: 'AKID',
        secretAccessKey: 'SECRET',
        publicBaseUrl: 'https://cdn.myweli.com/',
        clock: () => DateTime.utc(2026, 6, 26, 10),
      );
      final post = r2.presignPost(
        key: 'gallery/p1/abc.jpg',
        contentType: 'image/webp',
        maxBytes: 5242880,
      );

      expect(post.url, 'https://acc.r2.cloudflarestorage.com/uploads');
      expect(post.fields['key'], 'gallery/p1/abc.jpg');
      expect(post.fields['Content-Type'], 'image/webp');
      expect(post.fields['X-Amz-Algorithm'], 'AWS4-HMAC-SHA256');
      expect(
        post.fields['X-Amz-Credential'],
        'AKID/20260626/auto/s3/aws4_request',
      );
      expect(post.fields['X-Amz-Date'], '20260626T100000Z');
      // Signature is a 64-char hex HMAC.
      expect(post.fields['X-Amz-Signature'], matches(r'^[0-9a-f]{64}$'));
      // The base64 policy pins key + content-type + the size range.
      final policy =
          jsonDecode(utf8.decode(base64.decode(post.fields['Policy']!)))
              as Map<String, dynamic>;
      final conditions = policy['conditions'] as List;
      expect(
        conditions,
        contains(equals(['content-length-range', 0, 5242880])),
      );
      expect(conditions, contains(equals({'key': 'gallery/p1/abc.jpg'})));
      // Public URL trims the trailing slash on the base.
      expect(
        r2.publicUrl('gallery/p1/abc.jpg'),
        'https://cdn.myweli.com/gallery/p1/abc.jpg',
      );
    });
  });

  group('UploadSigningService', () {
    late InMemoryProviderAuthRepository providerAuth;
    late UploadSigningService service;
    final tokens = TokenService(secret: 'test-secret');
    late String accountId;

    setUp(() async {
      providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        isProd: false,
      );
      service = UploadSigningService(providerAuth, const FakeStorageService());
      final reg = await providerAuth.register(
        phoneNumber: '+2250500000060',
        businessName: 'X',
        businessType: 'salon',
        providerId: 'provider1',
      );
      accountId = reg.provider!.id;
    });

    test('signs a gallery upload scoped to the salon prefix', () async {
      final r = await service.sign(
        accountId,
        contentType: 'image/jpeg',
        purpose: 'gallery',
      );
      expect(r.ok, isTrue);
      final data = r.data!;
      expect(data['method'], 'POST');
      expect(data['maxBytes'], isA<int>());
      expect((data['fields'] as Map)['key'], startsWith('gallery/provider1/'));
      expect(data['publicUrl'], contains('gallery/provider1/'));
    });

    test('rejects a disallowed content-type / purpose', () async {
      expect(
        (await service.sign(
          accountId,
          contentType: 'image/gif',
          purpose: 'gallery',
        )).error,
        'invalid_input',
      );
      expect(
        (await service.sign(
          accountId,
          contentType: 'image/jpeg',
          purpose: 'avatar',
        )).error,
        'invalid_input',
      );
    });

    test('an unlinked account → forbidden', () async {
      final reg = await providerAuth.register(
        phoneNumber: '+2250500000061',
        businessName: 'Y',
        businessType: 'salon',
      );
      expect(
        (await service.sign(
          reg.provider!.id,
          contentType: 'image/jpeg',
          purpose: 'gallery',
        )).error,
        'forbidden',
      );
    });
  });

  group('route', () {
    late InMemoryProviderAuthRepository providerAuth;
    late UploadSigningService service;
    final tokens = TokenService(secret: 'test-secret');
    late String token;

    setUp(() async {
      providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        isProd: false,
      );
      service = UploadSigningService(providerAuth, const FakeStorageService());
      final reg = await providerAuth.register(
        phoneNumber: '+2250500000062',
        businessName: 'X',
        businessType: 'salon',
        providerId: 'provider1',
      );
      token = tokens
          .issueAccessToken(subject: reg.provider!.id, role: 'provider')
          .token;
    });

    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<UploadSigningService>()).thenReturn(service);
      return context;
    }

    Request post(String path, {String? bearer, Object? body}) => Request.post(
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
      body: body == null ? null : jsonEncode(body),
    );

    test('POST → 200 presigned; bad type → 400; no token → 401; '
        'user token → 403; GET → 405', () async {
      final ok = await sign_route.onRequest(
        ctx(
          post(
            '/uploads/sign',
            bearer: token,
            body: {'contentType': 'image/jpeg', 'purpose': 'gallery'},
          ),
        ),
      );
      expect(ok.statusCode, HttpStatus.ok);
      expect((await ok.json() as Map)['method'], 'POST');

      final bad = await sign_route.onRequest(
        ctx(
          post(
            '/uploads/sign',
            bearer: token,
            body: {'contentType': 'application/pdf', 'purpose': 'gallery'},
          ),
        ),
      );
      expect(bad.statusCode, HttpStatus.badRequest);

      final noAuth = await sign_route.onRequest(
        ctx(
          post(
            '/uploads/sign',
            body: {'contentType': 'image/jpeg', 'purpose': 'gallery'},
          ),
        ),
      );
      expect(noAuth.statusCode, HttpStatus.unauthorized);

      final userToken = tokens
          .issueAccessToken(subject: 'u1', role: 'user')
          .token;
      final forbidden = await sign_route.onRequest(
        ctx(
          post(
            '/uploads/sign',
            bearer: userToken,
            body: {'contentType': 'image/jpeg', 'purpose': 'gallery'},
          ),
        ),
      );
      expect(forbidden.statusCode, HttpStatus.forbidden);

      final badVerb = await sign_route.onRequest(
        ctx(
          Request.get(
            Uri.parse('http://localhost/uploads/sign'),
            headers: {'Authorization': 'Bearer $token'},
          ),
        ),
      );
      expect(badVerb.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
