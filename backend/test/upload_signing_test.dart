import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
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

    test(
      'R2StorageService.presignGet signs a GET on the chosen private bucket',
      () async {
        final r2 = R2StorageService(
          endpoint: 'https://acc.r2.cloudflarestorage.com',
          bucket: 'uploads',
          accessKeyId: 'AKID',
          secretAccessKey: 'SECRET',
          publicBaseUrl: 'https://cdn.myweli.com',
          kycBucket: 'kyc-bkt',
          depositBucket: 'deposit-bkt',
          clock: () => DateTime.utc(2026, 6, 26, 10),
        );
        final url = r2.presignGet(
          key: 'deposit/u1/abc.jpg',
          bucket: StorageBucket.deposit,
        );
        // Deposit screenshots live in their own bucket, not the KYC one.
        expect(
          url,
          startsWith('https://acc.r2.cloudflarestorage.com/deposit-bkt/'),
        );
        expect(
          r2.presignGet(key: 'kyc/a/x.pdf', bucket: StorageBucket.kyc),
          startsWith('https://acc.r2.cloudflarestorage.com/kyc-bkt/'),
        );
        expect(url, contains('X-Amz-Algorithm=AWS4-HMAC-SHA256'));
        expect(url, contains('X-Amz-Credential=AKID%2F20260626%2Fauto%2Fs3'));
        expect(url, contains('X-Amz-Date=20260626T100000Z'));
        expect(url, contains('X-Amz-Expires=300'));
        expect(url, contains('X-Amz-SignedHeaders=host'));
        expect(url, matches(RegExp(r'X-Amz-Signature=[0-9a-f]{64}')));
      },
    );

    test('R2StorageService.presignDelete signs a DELETE query URL', () {
      final r2 = R2StorageService(
        endpoint: 'https://acc.r2.cloudflarestorage.com',
        bucket: 'uploads',
        accessKeyId: 'AKID',
        secretAccessKey: 'SECRET',
        publicBaseUrl: 'https://cdn.myweli.com/',
        kycBucket: 'kyc-private',
        clock: () => DateTime.utc(2026, 7, 11, 10),
      );
      final url = r2.presignDelete(
        key: 'kyc/acc1/doc.pdf',
        bucket: StorageBucket.kyc,
      );
      expect(url, startsWith('https://acc.r2.cloudflarestorage.com/'));
      expect(url, contains('/kyc-private/kyc/acc1/doc.pdf?'));
      expect(url, contains('X-Amz-Algorithm=AWS4-HMAC-SHA256'));
      expect(url, matches(RegExp(r'X-Amz-Signature=[0-9a-f]{64}')));
      // A different METHOD must sign differently (the method is in the
      // canonical request).
      final get = r2.presignGet(
        key: 'kyc/acc1/doc.pdf',
        bucket: StorageBucket.kyc,
      );
      expect(
        RegExp(r'X-Amz-Signature=([0-9a-f]{64})').firstMatch(url)!.group(1),
        isNot(
          RegExp(r'X-Amz-Signature=([0-9a-f]{64})').firstMatch(get)!.group(1),
        ),
      );
    });

    test('FakeStorageService.presignGet returns a usable private URL', () {
      expect(
        const FakeStorageService().presignGet(
          key: 'deposit/u1/x.jpg',
          bucket: StorageBucket.deposit,
        ),
        startsWith('https://fake-storage.local/deposit/deposit/u1/x.jpg'),
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
      service = UploadSigningService(
        providerAuth,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        const FakeStorageService(),
      );
      final reg = await providerAuth.register(
        email: 'reg12@test.pro',
        authProvider: 'google',
        googleSub: 'reg-sub-12',
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

    test('review purpose: public, scoped to the USER prefix (P2b)', () async {
      final r = await service.sign(
        'u42',
        contentType: 'image/png',
        purpose: 'review',
      );
      expect(r.ok, isTrue);
      final data = r.data!;
      expect((data['fields'] as Map)['key'], startsWith('review/u42/'));
      // Public bucket: tiles render the photos.
      expect(data['publicUrl'], contains('review/u42/'));
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

    test(
      'kyc upload: account-scoped key, accepts pdf, no public URL',
      () async {
        final r = await service.sign(
          accountId,
          contentType: 'application/pdf', // PDF allowed for KYC, not gallery
          purpose: 'kyc',
        );
        expect(r.ok, isTrue);
        expect(
          (r.data!['fields'] as Map)['key'],
          startsWith('kyc/$accountId/'),
        );
        expect(r.data!['key'], startsWith('kyc/$accountId/'));
        expect(r.data!.containsKey('publicUrl'), isFalse); // never public
        // PDF is rejected for gallery.
        expect(
          (await service.sign(
            accountId,
            contentType: 'application/pdf',
            purpose: 'gallery',
          )).error,
          'invalid_input',
        );
      },
    );

    test(
      'deposit upload: consumer-scoped private key, no public URL',
      () async {
        // A consumer sub (not a provider account) — no provider lookup needed.
        final r = await service.sign(
          'user_consumer',
          contentType: 'image/jpeg',
          purpose: 'deposit',
        );
        expect(r.ok, isTrue);
        expect(
          (r.data!['fields'] as Map)['key'],
          startsWith('deposit/user_consumer/'),
        );
        expect(r.data!['key'], startsWith('deposit/user_consumer/'));
        expect(r.data!.containsKey('publicUrl'), isFalse); // never public
        // PDF is not allowed for a deposit screenshot (images only).
        expect(
          (await service.sign(
            'user_consumer',
            contentType: 'application/pdf',
            purpose: 'deposit',
          )).error,
          'invalid_input',
        );
      },
    );

    test('kyc works for an unlinked account (gallery does not)', () async {
      final reg = await providerAuth.register(
        email: 'reg13@test.pro',
        authProvider: 'google',
        googleSub: 'reg-sub-13',
        phoneNumber: '+2250500000063',
        businessName: 'Unlinked',
        businessType: 'salon',
      );
      final id = reg.provider!.id;
      expect(
        (await service.sign(id, contentType: 'image/jpeg', purpose: 'kyc')).ok,
        isTrue,
      );
      expect(
        (await service.sign(
          id,
          contentType: 'image/jpeg',
          purpose: 'gallery',
        )).error,
        'forbidden',
      );
    });

    test('an unlinked account → forbidden', () async {
      final reg = await providerAuth.register(
        email: 'reg14@test.pro',
        authProvider: 'google',
        googleSub: 'reg-sub-14',
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
      service = UploadSigningService(
        providerAuth,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        const FakeStorageService(),
      );
      final reg = await providerAuth.register(
        email: 'reg15@test.pro',
        authProvider: 'google',
        googleSub: 'reg-sub-15',
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

    test('deposit purpose: consumer → 200; provider → 403', () async {
      final userToken = tokens
          .issueAccessToken(subject: 'u1', role: 'user')
          .token;
      // Consumer can sign a deposit upload.
      final ok = await sign_route.onRequest(
        ctx(
          post(
            '/uploads/sign',
            bearer: userToken,
            body: {'contentType': 'image/jpeg', 'purpose': 'deposit'},
          ),
        ),
      );
      expect(ok.statusCode, HttpStatus.ok);
      // A provider token cannot use the deposit purpose.
      final provider = await sign_route.onRequest(
        ctx(
          post(
            '/uploads/sign',
            bearer: token,
            body: {'contentType': 'image/jpeg', 'purpose': 'deposit'},
          ),
        ),
      );
      expect(provider.statusCode, HttpStatus.forbidden);
    });

    test('review purpose: consumer → 200 public URL; provider → 403', () async {
      final userToken = tokens
          .issueAccessToken(subject: 'u1', role: 'user')
          .token;
      final ok = await sign_route.onRequest(
        ctx(
          post(
            '/uploads/sign',
            bearer: userToken,
            body: {'contentType': 'image/jpeg', 'purpose': 'review'},
          ),
        ),
      );
      expect(ok.statusCode, HttpStatus.ok);
      final body = jsonDecode(await ok.body()) as Map<String, dynamic>;
      expect(body['key'], startsWith('review/u1/'));
      expect(body['publicUrl'], isNotNull);

      final provider = await sign_route.onRequest(
        ctx(
          post(
            '/uploads/sign',
            bearer: token,
            body: {'contentType': 'image/jpeg', 'purpose': 'review'},
          ),
        ),
      );
      expect(provider.statusCode, HttpStatus.forbidden);
    });
  });
}
