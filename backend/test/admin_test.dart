import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/admin/admin_auth_repository.dart';
import 'package:myweli_backend/src/admin/admin_kyc_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/auth/login_throttle.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

import '../routes/admin/_middleware.dart' as mw;
import '../routes/admin/auth/login.dart' as login_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  final tokens = TokenService(secret: 'test-secret');

  group('InMemoryAdminAuthRepository', () {
    late InMemoryAdminAuthRepository repo;

    setUp(() async {
      repo = InMemoryAdminAuthRepository(
        tokens: tokens,
        throttle: LoginThrottle(maxAttempts: 3),
      );
      await repo.ensureSeedAdmin(
        email: 'Admin@Myweli.ci',
        password: 'secret123',
      );
    });

    test(
      'login succeeds (case-insensitive email) → admin-role token',
      () async {
        final r = await repo.login('admin@myweli.ci', 'secret123');
        expect(r.ok, isTrue);
        final jwt = tokens.verifyAccessToken(r.tokens!.accessToken);
        expect((jwt!.payload as Map)['role'], 'admin');
      },
    );

    test('wrong password fails; locks out after the attempt budget', () async {
      for (var i = 0; i < 3; i++) {
        expect(
          (await repo.login('admin@myweli.ci', 'nope')).error,
          'invalid_credentials',
        );
      }
      // Even the correct password is refused while locked.
      expect(
        (await repo.login('admin@myweli.ci', 'secret123')).error,
        'locked_out',
      );
    });

    test(
      'refresh rotates; reusing a rotated token revokes the family',
      () async {
        final first = (await repo.login(
          'admin@myweli.ci',
          'secret123',
        )).tokens!;
        final rotated = await repo.refresh(first.refreshToken);
        expect(rotated.ok, isTrue);
        expect(
          (await repo.refresh(first.refreshToken)).error,
          'refresh_reused',
        );
        // The whole family is gone, including the rotated token.
        expect(
          (await repo.refresh(rotated.tokens!.refreshToken)).error,
          'refresh_invalid',
        );
      },
    );

    test('ensureSeedAdmin is idempotent (does not overwrite)', () async {
      await repo.ensureSeedAdmin(email: 'admin@myweli.ci', password: 'changed');
      expect((await repo.login('admin@myweli.ci', 'secret123')).ok, isTrue);
    });
  });

  group('AdminKycService', () {
    late InMemoryProviderAuthRepository providers;
    late InMemoryAuditLogRepository audit;
    late AdminKycService svc;
    late InMemoryProvidersRepository listings;
    late String accountId;

    setUp(() async {
      providers = InMemoryProviderAuthRepository(tokens: tokens, isProd: false);
      audit = InMemoryAuditLogRepository();
      listings = InMemoryProvidersRepository([]);
      svc = AdminKycService(
        providers,
        const FakeStorageService(),
        audit,
        listings,
      );
      final reg = await providers.register(
        email: 'reg5@test.pro',
        authProvider: 'google',
        googleSub: 'reg-sub-5',
        phoneNumber: '+2250500000090',
        businessName: 'Salon X',
        businessType: 'salon',
        providerId: 'p1',
      );
      final salon = await listings.createSalon(
        name: 'Salon Badge',
        category: 'salon',
        phoneNumber: '+2250700000042',
      );
      await providers.linkProvider(reg.provider!.id, salon['id'] as String);
      accountId = reg.provider!.id;
      await providers.submitKyc(accountId, [
        {'type': 'id_card', 'key': 'kyc/$accountId/x.jpg'},
      ]);
    });

    test('queue lists pending accounts', () async {
      final data = (await svc.queue()).data! as Map;
      expect(data['total'], 1);
      expect((data['items'] as List).first['accountId'], accountId);
    });

    test('detail returns each doc with a signed view URL', () async {
      final docs = ((await svc.detail(accountId)).data! as Map)['docs'] as List;
      expect(
        (docs.first as Map)['viewUrl'],
        startsWith('https://fake-storage.local'),
      );
    });

    test('approve verifies + writes exactly one audit row', () async {
      final r = await svc.approve('admin_1', accountId);
      expect((r.data! as Map)['verificationStatus'], 'verified');

      final log = await audit.list();
      expect(log.total, 1);
      expect(log.items.first['action'], 'kyc.approve');
      expect(log.items.first['actorAdminId'], 'admin_1');

      // Audit 15.1: approval denormalizes the « Vérifié » badge onto the
      // public listing (and reject flips it back off).
      final acct = (r.data! as Map)['providerId'] as String;
      expect((await listings.byId(acct))!['verified'], isTrue);
      await svc.reject('admin_1', accountId, 'photos illisibles');
      expect((await listings.byId(acct))!['verified'], isFalse);
    });

    test('reject requires a reason and records it', () async {
      expect(
        (await svc.reject('admin_1', accountId, '')).error,
        'invalid_input',
      );
      final r = await svc.reject('admin_1', accountId, 'Document illisible');
      expect((r.data! as Map)['verificationStatus'], 'rejected');
      expect((r.data! as Map)['rejectionReason'], 'Document illisible');
      expect((await audit.list()).items.first['reason'], 'Document illisible');
    });

    test('approving an unknown account → not_found', () async {
      expect((await svc.approve('admin_1', 'nope')).error, 'not_found');
    });
  });

  group('admin trust boundary', () {
    Response okHandler(RequestContext _) => Response(body: 'ok');

    RequestContext ctx(String path, {String? bearer}) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request.get(
          Uri.parse('http://localhost$path'),
          headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
        ),
      );
      when(() => c.read<TokenService>()).thenReturn(tokens);
      return c;
    }

    test(
      'non-admin → 403, no token → 401, admin → pass, /auth bypasses',
      () async {
        final handler = mw.middleware(okHandler);
        final userTok = tokens
            .issueAccessToken(subject: 'u1', role: 'user')
            .token;
        final adminTok = tokens
            .issueAccessToken(subject: 'admin_1', role: 'admin')
            .token;

        expect(
          (await handler(ctx('/admin/kyc', bearer: userTok))).statusCode,
          HttpStatus.forbidden,
        );
        expect(
          (await handler(ctx('/admin/kyc'))).statusCode,
          HttpStatus.unauthorized,
        );
        expect(
          (await handler(ctx('/admin/kyc', bearer: adminTok))).statusCode,
          HttpStatus.ok,
        );
        // The login/refresh path is reachable without an admin token.
        expect(
          (await handler(ctx('/admin/auth/login'))).statusCode,
          HttpStatus.ok,
        );
      },
    );
  });

  group('admin login route', () {
    late InMemoryAdminAuthRepository repo;

    RequestContext ctx(Object body) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/admin/auth/login'),
          body: jsonEncode(body),
        ),
      );
      when(() => c.read<AdminAuthRepository>()).thenReturn(repo);
      return c;
    }

    setUp(() async {
      repo = InMemoryAdminAuthRepository(tokens: tokens);
      await repo.ensureSeedAdmin(email: 'a@myweli.ci', password: 'pw12345');
    });

    test('valid creds → 200 token pair; bad creds → 401', () async {
      final ok = await login_route.onRequest(
        ctx({'email': 'a@myweli.ci', 'password': 'pw12345'}),
      );
      expect(ok.statusCode, HttpStatus.ok);
      expect((await ok.json() as Map)['accessToken'], isNotNull);

      final bad = await login_route.onRequest(
        ctx({'email': 'a@myweli.ci', 'password': 'wrong'}),
      );
      expect(bad.statusCode, HttpStatus.unauthorized);
    });
  });
}
