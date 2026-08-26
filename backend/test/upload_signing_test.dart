import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/capabilities.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:myweli_backend/src/upload_signing_service.dart';
import 'package:test/test.dart';

import '../routes/uploads/sign.dart' as sign_route;

class _MockRequestContext extends Mock implements RequestContext {}

/// A membership world where catalogue.manage and profile.manage SEPARATE.
/// The preset matrix couples them today (manager holds both, reception
/// neither), so no role fixture can observe WHICH capability the sign gate
/// asks for — and V3 sparse grants are exactly the future where they differ.
class _CatalogueOnlyMembers extends MembershipService {
  _CatalogueOnlyMembers(super.members, super.providerAuth);

  @override
  Future<String?> salonForRequest(String accountId, {String? salonId}) async =>
      salonId;

  @override
  Future<bool> can(
    String accountId,
    String providerId,
    String capability,
  ) async => capability == Cap.catalogueManage;
}

void main() {
  group('StorageService', () {
    test('FakeStorageService returns deterministic fake URLs', () {
      final s = FakeStorageService();
      final up = s.presignPut(
        key: 'gallery/p1/abc.jpg',
        contentType: 'image/jpeg',
      );
      expect(up.url, startsWith('https://fake-storage.local'));
      // The OBJECT path, like R2 — a fake that accepted a shape real storage
      // rejects is how the presigned-POST defect survived every test we had.
      expect(up.url, contains('/gallery/p1/abc.jpg'));
      expect(up.headers['content-type'], 'image/jpeg');
      expect(
        s.publicUrl('gallery/p1/abc.jpg'),
        'https://fake-storage.local/gallery/p1/abc.jpg',
      );
    });

    test('R2StorageService signs a presigned PUT URL', () {
      final r2 = _r2();
      final up = r2.presignPut(
        key: 'gallery/p1/abc.jpg',
        contentType: 'image/webp',
      );
      final u = Uri.parse(up.url);

      expect(u.host, 'acc.r2.cloudflarestorage.com');
      expect(u.path, '/uploads/gallery/p1/abc.jpg');
      expect(u.queryParameters['X-Amz-Algorithm'], 'AWS4-HMAC-SHA256');
      expect(
        u.queryParameters['X-Amz-Credential'],
        'AKID/20260626/auto/s3/aws4_request',
      );
      expect(u.queryParameters['X-Amz-Date'], '20260626T100000Z');
      expect(u.queryParameters['X-Amz-Signature'], matches(r'^[0-9a-f]{64}$'));
      expect(u.queryParameters['X-Amz-SignedHeaders'], 'content-type;host');
      expect(up.headers, {'content-type': 'image/webp'});
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
        FakeStorageService().presignGet(
          key: 'deposit/u1/x.jpg',
          bucket: StorageBucket.deposit,
        ),
        startsWith('https://fake-storage.local/deposit/deposit/u1/x.jpg'),
      );
    });
  });

  group('UploadSigningService', () {
    late InMemoryProviderAuthRepository providerAuth;
    late InMemoryMembershipRepository memberships;
    late UploadSigningService service;
    final tokens = TokenService(secret: 'test-secret');
    late String accountId;

    setUp(() async {
      providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        echoDevCode: true,
      );
      memberships = InMemoryMembershipRepository();
      service = UploadSigningService(
        providerAuth,
        MembershipService(memberships, providerAuth),
        FakeStorageService(),
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
      expect(data['method'], 'PUT');
      expect(data['maxBytes'], isA<int>());
      expect(data['key'], startsWith('pending/gallery/provider1/'));
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
      expect(data['key'], startsWith('pending/review/u42/'));
      // Public bucket: tiles render the photos.
      expect(data['publicUrl'], contains('review/u42/'));
    });

    test('avatar purpose: public, its OWN prefix, scoped to the USER', () async {
      final r = await service.sign(
        'u42',
        contentType: 'image/jpeg',
        purpose: 'avatar',
      );
      expect(r.ok, isTrue);
      final data = r.data!;
      expect(data['key'], startsWith('pending/avatar/u42/'));
      expect(data['publicUrl'], contains('avatar/u42/'));
      // The point of the whole change: it shares the review branch's SHAPE
      // (public bucket, own prefix) and not its NAMESPACE. Erasure, moderation
      // and any lifecycle rule key on this prefix, so a profile photo filed
      // under `review/` would be swept by the wrong broom in both directions.
      expect(data['key'], isNot(contains('review/')));
    });

    test('logo purpose: public, its OWN prefix, scoped to the SALON', () async {
      await memberships.ensureOwner(
        providerId: 'provider1',
        accountId: accountId,
        email: 'reg12@test.pro',
      );
      final r = await service.sign(
        accountId,
        contentType: 'image/png',
        purpose: 'logo',
      );
      expect(r.ok, isTrue, reason: r.error ?? '');
      final data = r.data!;
      expect(data['key'], startsWith('pending/logo/provider1/'));
      expect(data['publicUrl'], contains('logo/provider1/'));
      // Its own namespace, not the gallery's: a logo filed under gallery/
      // would look like a portfolio photo to every future gallery sweep
      // (salon-logo.md §5, the avatar's §3 argument verbatim).
      expect(data['key'], isNot(contains('gallery/')));
    });

    test(
      'logo: a member WITHOUT profile.manage is refused at sign time',
      () async {
        // Reception holds neither profile.manage nor catalogue.manage — but
        // the point of gating on profile.manage specifically is the CLAIM
        // surface's gate: a sign gate wider than the claim gate would let a
        // member sign uploads they can never save (salon-logo.md §6).
        await memberships.ensureOwner(
          providerId: 'provider1',
          accountId: accountId,
          email: 'reg12@test.pro',
        );
        final reg2 = await providerAuth.register(
          email: 'reception@test.pro',
          authProvider: 'google',
          googleSub: 'reg-sub-13',
          phoneNumber: '+2250500000061',
          businessName: 'X',
          businessType: 'salon',
          providerId: 'provider1x',
        );
        final receptionId = reg2.provider!.id;
        final inv = await memberships.invite(
          providerId: 'provider1',
          email: 'reception@test.pro',
          role: 'reception',
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
        );
        await memberships.activate(inv.id, receptionId);

        final r = await service.sign(
          receptionId,
          contentType: 'image/jpeg',
          purpose: 'logo',
          salonId: 'provider1',
        );
        expect(r.ok, isFalse);
        expect(r.error, 'forbidden');
      },
    );

    test('logo: catalogue.manage alone is NOT enough — the gate asks for the '
        "claim surface's own cap", () async {
      // salon-logo.md §6 decision 2: the PATCH that claims a logo requires
      // profile.manage, so a sign gate satisfied by catalogue.manage would
      // let a catalogue-only member sign uploads it can never save — an
      // orphan generator. The role presets cannot test this (no role holds
      // catalogue.manage without profile.manage), hence the stub.
      final catalogueOnly = UploadSigningService(
        providerAuth,
        _CatalogueOnlyMembers(memberships, providerAuth),
        FakeStorageService(),
      );
      // Control: the same member CAN sign a gallery upload…
      final gallery = await catalogueOnly.sign(
        accountId,
        contentType: 'image/jpeg',
        purpose: 'gallery',
        salonId: 'provider1',
      );
      expect(gallery.ok, isTrue, reason: gallery.error ?? '');
      // …and is refused a logo.
      final r = await catalogueOnly.sign(
        accountId,
        contentType: 'image/jpeg',
        purpose: 'logo',
        salonId: 'provider1',
      );
      expect(r.ok, isFalse);
      expect(r.error, 'forbidden');
    });

    test('R6: a selected salon scopes the gallery key; a forged one is '
        'denied', () async {
      // The owner also owns provider2.
      await memberships.ensureOwner(
        providerId: 'provider2',
        accountId: accountId,
        email: 'reg12@test.pro',
      );
      final r = await service.sign(
        accountId,
        contentType: 'image/jpeg',
        purpose: 'gallery',
        salonId: 'provider2',
      );
      expect(r.ok, isTrue);
      expect(r.data!['key'], startsWith('pending/gallery/provider2/'));

      final forged = await service.sign(
        accountId,
        contentType: 'image/jpeg',
        purpose: 'gallery',
        salonId: 'provider9',
      );
      expect(forged.ok, isFalse);
      expect(forged.error, 'forbidden');
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
      // `avatar` used to be the example here. It is a real purpose now, so the
      // negative branch needs one that is still genuinely unknown — otherwise
      // adding a purpose silently deletes the coverage that guards the rest.
      expect(
        (await service.sign(
          accountId,
          contentType: 'image/jpeg',
          purpose: 'banner',
        )).error,
        'invalid_input',
      );
      expect(
        (await service.sign(
          accountId,
          contentType: 'image/jpeg',
          purpose: null,
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
        expect(r.data!['key'], startsWith('pending/kyc/$accountId/'));
        expect(r.data!['key'], startsWith('pending/kyc/$accountId/'));
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
        expect(r.data!['key'], startsWith('pending/deposit/user_consumer/'));
        expect(r.data!['key'], startsWith('pending/deposit/user_consumer/'));
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
        echoDevCode: true,
      );
      service = UploadSigningService(
        providerAuth,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        FakeStorageService(),
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
      expect((await ok.json() as Map)['method'], 'PUT');

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
      expect(body['key'], startsWith('pending/review/u1/'));
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

    test('avatar purpose: consumer → 200 public URL; provider → 403', () async {
      final userToken = tokens
          .issueAccessToken(subject: 'u1', role: 'user')
          .token;
      final ok = await sign_route.onRequest(
        ctx(
          post(
            '/uploads/sign',
            bearer: userToken,
            body: {'contentType': 'image/jpeg', 'purpose': 'avatar'},
          ),
        ),
      );
      expect(ok.statusCode, HttpStatus.ok);
      final body = jsonDecode(await ok.body()) as Map<String, dynamic>;
      expect(body['key'], startsWith('pending/avatar/u1/'));
      expect(body['publicUrl'], isNotNull);

      // Symmetric: a PROVIDER token cannot borrow the consumer namespace
      // either, which is what stops a salon writing into a user's prefix.
      final provider = await sign_route.onRequest(
        ctx(
          post(
            '/uploads/sign',
            bearer: token,
            body: {'contentType': 'image/jpeg', 'purpose': 'avatar'},
          ),
        ),
      );
      expect(provider.statusCode, HttpStatus.forbidden);
    });
  });

  group('presignPut — the R2 fix', () {
    // R2 answers a presigned POST with 501 NotImplemented. Measured against the
    // live bucket; docs/design/backend-r2-presigned-put.md §2.
    test('targets the OBJECT path, not the bucket root', () {
      // The literal defect. presignPost returned "{endpoint}/{bucket}" —
      // correct for POST, where the key rides in the form — and a PUT there
      // would write an object literally named after the bucket, or 400.
      final r = _r2().presignPut(
        key: 'deposit/u1/abc.jpg',
        contentType: 'image/jpeg',
        bucket: StorageBucket.deposit,
      );
      expect(r.url, contains('/myweli-deposit/deposit/u1/abc.jpg?'));
      expect(
        r.url,
        isNot(matches(RegExp(r'/myweli-deposit\?'))),
        reason: 'the bucket root is the POST target and is wrong for PUT',
      );
    });

    test('pins content-type, and returns exactly the headers it signed', () {
      // Probe 4 against real R2: sending a content-type other than the signed
      // one is 403 SignatureDoesNotMatch. So the returned headers map is not
      // advisory — the client must send precisely these.
      final r = _r2().presignPut(
        key: 'k.jpg',
        contentType: 'image/jpeg',
        bucket: StorageBucket.deposit,
      );
      expect(r.headers['content-type'], 'image/jpeg');
      final signed = Uri.parse(r.url).queryParameters['X-Amz-SignedHeaders'];
      expect(signed, 'content-type;host', reason: 'sorted, and host included');
    });

    test('does NOT sign content-length — R2 ignores it', () {
      // Measured: a body 500 bytes larger than a signed content-length was
      // accepted with 200. Signing it would read as enforcement in review and
      // enforce nothing, so the size cap moves to the service (§3).
      final r = _r2().presignPut(
        key: 'k.jpg',
        contentType: 'image/jpeg',
        bucket: StorageBucket.deposit,
      );
      expect(
        Uri.parse(r.url).queryParameters['X-Amz-SignedHeaders'],
        isNot(contains('content-length')),
      );
    });
  });
}

/// The R2 signer under test. Deposit bucket named explicitly because the PUT
/// tests assert the object path, which embeds it.
R2StorageService _r2() => R2StorageService(
  endpoint: 'https://acc.r2.cloudflarestorage.com',
  bucket: 'uploads',
  accessKeyId: 'AKID',
  secretAccessKey: 'SECRET',
  publicBaseUrl: 'https://cdn.myweli.com/',
  kycBucket: 'myweli-kyc',
  depositBucket: 'myweli-deposit',
  clock: () => DateTime.utc(2026, 6, 26, 10),
);
