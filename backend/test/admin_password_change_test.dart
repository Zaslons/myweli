import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/admin/admin_auth_repository.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/auth/login_throttle.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:test/test.dart';

import '../routes/admin/_middleware.dart' as mw;
import '../routes/admin/auth/password.dart' as pw_route;

class _MockRequestContext extends Mock implements RequestContext {}

/// A throttle that can be broken **after** setup, for the fail-closed arms.
///
/// Switchable rather than permanently broken because the fixture has to log in
/// to learn the admin id, and a throttle that is down from birth fails that too
/// — the first version of this test died in its own setup.
class _FlakyThrottle implements LoginThrottle {
  _FlakyThrottle() : _inner = InMemoryLoginThrottle();
  final InMemoryLoginThrottle _inner;
  bool broken = false;

  @override
  Future<bool> isLocked(String key) async =>
      broken ? throw StateError('down') : _inner.isLocked(key);
  @override
  Future<void> recordFailure(String key) async =>
      broken ? throw StateError('down') : _inner.recordFailure(key);
  @override
  Future<void> reset(String key) async =>
      broken ? throw StateError('down') : _inner.reset(key);
}

void main() {
  final tokens = TokenService(secret: 'test-secret');
  const seedPw = 'pw12345678901'; // 13 chars — clears the floor
  const newPw = 'a-brand-new-password';

  late InMemoryAdminAuthRepository repo;
  late InMemoryAuditLogRepository audit;
  late String adminId;

  Future<void> boot({LoginThrottle? throttle}) async {
    repo = InMemoryAdminAuthRepository(tokens: tokens, throttle: throttle);
    audit = InMemoryAuditLogRepository();
    await repo.ensureSeedAdmin(email: 'a@myweli.ci', password: seedPw);
    final r = await repo.login('a@myweli.ci', seedPw);
    adminId = tokens.verifyAccessToken(r.tokens!.accessToken)!.subject!;
  }

  RequestContext ctx(
    Object? body, {
    String? bearer,
    HttpMethod method = HttpMethod.post,
    bool malformed = false,
  }) {
    final c = _MockRequestContext();
    final uri = Uri.parse('http://localhost/admin/auth/password');
    final headers = {if (bearer != null) 'Authorization': 'Bearer $bearer'};
    when(() => c.request).thenReturn(
      method == HttpMethod.get
          ? Request.get(uri, headers: headers)
          : Request.post(
              uri,
              headers: headers,
              body: malformed ? 'not-json' : jsonEncode(body),
            ),
    );
    when(() => c.read<TokenService>()).thenReturn(tokens);
    when(() => c.read<AdminAuthRepository>()).thenReturn(repo);
    when(() => c.read<AuditLogRepository>()).thenReturn(audit);
    return c;
  }

  String adminBearer() =>
      tokens.issueAccessToken(subject: adminId, role: 'admin').token;

  setUp(boot);

  group('POST /admin/auth/password', () {
    test(
      'changes the password: the new one logs in, the old one does not',
      () async {
        final r = await pw_route.onRequest(
          ctx({
            'currentPassword': seedPw,
            'newPassword': newPw,
          }, bearer: adminBearer()),
        );
        expect(r.statusCode, HttpStatus.noContent);

        expect((await repo.login('a@myweli.ci', newPw)).ok, isTrue);
        expect(
          (await repo.login('a@myweli.ci', seedPw)).ok,
          isFalse,
          reason:
              'the old password must stop working — otherwise the rotation '
              'is the same no-op that redeploying ADMIN_PASSWORD already was',
        );
      },
    );

    test(
      'REFRESH TOKENS ISSUED BEFORE THE CHANGE ARE REJECTED AFTER IT',
      () async {
        // The point of the rotation: a leaked refresh token must die with it.
        // Without this the credential changes and the thief keeps their session.
        final before = (await repo.login('a@myweli.ci', seedPw)).tokens!;
        expect(
          (await repo.refresh(before.refreshToken)).ok,
          isTrue,
          reason: 'control: the token works before the change',
        );

        final fresh = (await repo.login('a@myweli.ci', seedPw)).tokens!;
        await pw_route.onRequest(
          ctx({
            'currentPassword': seedPw,
            'newPassword': newPw,
          }, bearer: adminBearer()),
        );
        expect((await repo.refresh(fresh.refreshToken)).ok, isFalse);
      },
    );

    test(
      'THE /admin/auth EXEMPTION: anonymous → 401, non-admin → 403',
      () async {
        // The middleware waves everything under /admin/auth through, so this
        // route authenticates itself. If that self-check were dropped, the
        // endpoint would be an unauthenticated password reset.
        final anon = await pw_route.onRequest(
          ctx({'currentPassword': seedPw, 'newPassword': newPw}),
        );
        expect(anon.statusCode, HttpStatus.unauthorized);

        final userTok = tokens
            .issueAccessToken(subject: 'u1', role: 'user')
            .token;
        final asUser = await pw_route.onRequest(
          ctx({
            'currentPassword': seedPw,
            'newPassword': newPw,
          }, bearer: userTok),
        );
        expect(asUser.statusCode, HttpStatus.forbidden);

        // …and the exemption really is in force, so the guard above is load-
        // bearing rather than redundant with the middleware.
        final passed = await mw.middleware((_) async => Response(body: 'ok'))(
          ctx(null, method: HttpMethod.get),
        );
        expect(
          passed.statusCode,
          HttpStatus.ok,
          reason: '/admin/auth/* bypasses the gate — hence the self-check',
        );

        expect(
          (await repo.login('a@myweli.ci', seedPw)).ok,
          isTrue,
          reason: 'no refused call may have changed the password',
        );
      },
    );

    test(
      'a wrong current password → 401 and COUNTS against the throttle',
      () async {
        await boot(throttle: InMemoryLoginThrottle(maxAttempts: 2));
        final bearer = adminBearer();
        for (var i = 0; i < 2; i++) {
          final r = await pw_route.onRequest(
            ctx({
              'currentPassword': 'wrong-one-here',
              'newPassword': newPw,
            }, bearer: bearer),
          );
          expect(r.statusCode, HttpStatus.unauthorized);
        }
        // The budget is shared with login — a key of its own would hand a stolen
        // access token a fresh five guesses that login's lockout never sees.
        final locked = await pw_route.onRequest(
          ctx({
            'currentPassword': seedPw,
            'newPassword': newPw,
          }, bearer: bearer),
        );
        expect(locked.statusCode, HttpStatus.tooManyRequests);
        expect(await locked.json(), {'error': 'locked_out'});
        expect(
          (await repo.login('a@myweli.ci', seedPw)).error,
          'locked_out',
          reason: 'the lockout must reach login, not live in its own namespace',
        );
      },
    );

    test('throttle down → 503 throttle_unavailable, never 401', () async {
      final flaky = _FlakyThrottle();
      await boot(throttle: flaky);
      flaky.broken = true;
      final r = await pw_route.onRequest(
        ctx({
          'currentPassword': seedPw,
          'newPassword': newPw,
        }, bearer: adminBearer()),
      );
      expect(r.statusCode, HttpStatus.serviceUnavailable);
      expect(await r.json(), {'error': 'throttle_unavailable'});
      expect(r.headers['retry-after'], '5');
    });

    test(
      'a short new password is refused, and 12 exactly is accepted',
      () async {
        final short = await pw_route.onRequest(
          ctx({
            'currentPassword': seedPw,
            'newPassword': 'a' * 11,
          }, bearer: adminBearer()),
        );
        expect(short.statusCode, HttpStatus.badRequest);
        expect(await short.json(), {'error': 'invalid_input'});

        final atFloor = await pw_route.onRequest(
          ctx({
            'currentPassword': seedPw,
            'newPassword': 'b' * 12,
          }, bearer: adminBearer()),
        );
        expect(
          atFloor.statusCode,
          HttpStatus.noContent,
          reason: 'the floor is a boundary, not an approximation',
        );
      },
    );

    test('a new password beyond bcrypt 72 bytes is refused', () async {
      // bcrypt truncates at 72, so a 100-char "password" is really its first 72
      // and the rest is theatre.
      final r = await pw_route.onRequest(
        ctx({
          'currentPassword': seedPw,
          'newPassword': 'c' * 73,
        }, bearer: adminBearer()),
      );
      expect(r.statusCode, HttpStatus.badRequest);
    });

    test('reusing the current password → 400 password_unchanged', () async {
      final r = await pw_route.onRequest(
        ctx({
          'currentPassword': seedPw,
          'newPassword': seedPw,
        }, bearer: adminBearer()),
      );
      expect(r.statusCode, HttpStatus.badRequest);
      expect(await r.json(), {'error': 'password_unchanged'});
    });

    test('malformed body → 400; wrong verb → 405', () async {
      final bad = await pw_route.onRequest(
        ctx(null, bearer: adminBearer(), malformed: true),
      );
      expect(bad.statusCode, HttpStatus.badRequest);
      expect(await bad.json(), {'error': 'invalid_body'});

      final verb = await pw_route.onRequest(
        ctx(null, bearer: adminBearer(), method: HttpMethod.get),
      );
      expect(verb.statusCode, HttpStatus.methodNotAllowed);
    });

    test('AUDITED, AND THE ENTRY CARRIES NO PASSWORD MATERIAL', () async {
      await pw_route.onRequest(
        ctx({
          'currentPassword': seedPw,
          'newPassword': newPw,
        }, bearer: adminBearer()),
      );
      final rows = (await audit.list()).items;
      expect(rows, hasLength(1));
      expect(rows.single['action'], 'admin.password_changed');
      expect(rows.single['actorAdminId'], adminId);

      final serialised = jsonEncode(rows.single);
      for (final secret in [seedPw, newPw]) {
        expect(
          serialised.contains(secret),
          isFalse,
          reason: 'no password, prefix or hash may reach the audit log',
        );
      }
      expect(
        serialised.contains(r'$2'),
        isFalse,
        reason: r'$2… is a bcrypt hash prefix',
      );
    });

    test('a failed change writes NO audit row', () async {
      await pw_route.onRequest(
        ctx({
          'currentPassword': 'wrong-one-here',
          'newPassword': newPw,
        }, bearer: adminBearer()),
      );
      expect((await audit.list()).items, isEmpty);
    });
  });

  group('ensureSeedAdmin is bootstrap-only, and says so', () {
    test(
      'reports true on create and FALSE when it discards the password',
      () async {
        final fresh = InMemoryAdminAuthRepository(tokens: tokens);
        expect(
          await fresh.ensureSeedAdmin(email: 'a@myweli.ci', password: seedPw),
          isTrue,
        );
        // This false is what the boot NOTICE keys on. Without it the discarded
        // password is invisible, which is how "rotate ADMIN_PASSWORD" could be
        // believed for as long as it was.
        expect(
          await fresh.ensureSeedAdmin(
            email: 'a@myweli.ci',
            password: 'other-pw-1',
          ),
          isFalse,
        );
        expect((await fresh.login('a@myweli.ci', 'other-pw-1')).ok, isFalse);
        expect((await fresh.login('a@myweli.ci', seedPw)).ok, isTrue);
      },
    );
  });
}
