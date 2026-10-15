import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/admin/admin_auth_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/observability/request_middleware.dart';
import 'package:test/test.dart';

import '../../routes/admin/auth/refresh.dart' as admin_refresh;
import '../../routes/auth/provider/refresh.dart' as provider_refresh;
import '../../routes/auth/refresh.dart' as consumer_refresh;
import '../http/observed.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// One principal's in-memory twin, behind the three calls this file needs.
typedef _Twin = ({
  String name,
  Future<TokenPair> Function() login,
  Future<RefreshResult> Function(String token) refresh,
});

/// The in-memory twins and the refresh routes under the atomic exchange with
/// the 30-second grace (docs/design/backend-refresh-rotation-atomic.md §8).
///
/// The Postgres twins are pinned against a real database in
/// test/db/postgres_repositories_test.dart (consumer + provider) and
/// test/db/postgres_admin_auth_test.dart (admin); this file holds the SAME
/// table of outcomes for the in-memory ones, on an injected clock — so a test
/// steps past 30 s without sleeping — and the routes' outcome log line.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late DateTime now;
  DateTime clock() => now;

  setUp(() => now = DateTime.utc(2026, 10, 12, 9));

  var seq = 0;

  _Twin consumer() {
    final repo = InMemoryAuthRepository(
      tokens: tokens,
      echoDevCode: true,
      clock: clock,
    );
    return (
      name: 'consumer',
      login: () async {
        final email = 'c${seq++}@myweli.test';
        final code = (await repo.requestEmailOtp(email)).devCode!;
        return (await repo.verifyEmailOtp(email, code)).tokens!;
      },
      refresh: repo.refresh,
    );
  }

  _Twin provider() {
    final repo = InMemoryProviderAuthRepository(
      tokens: tokens,
      echoDevCode: true,
      clock: clock,
    );
    return (
      name: 'provider',
      login: () async {
        final n = seq++;
        return (await repo.register(
          businessName: 'Salon $n',
          businessType: 'salon',
          phoneNumber: '+22507000000$n',
          email: 'p$n@myweli.test',
          authProvider: 'google',
          googleSub: 'g-$n',
        )).tokens!;
      },
      refresh: repo.refresh,
    );
  }

  _Twin admin() {
    final repo = InMemoryAdminAuthRepository(tokens: tokens, clock: clock);
    return (
      name: 'admin',
      login: () async {
        final email = 'a${seq++}@myweli.test';
        await repo.ensureSeedAdmin(email: email, password: 'secret123');
        return (await repo.login(email, 'secret123')).tokens!;
      },
      refresh: repo.refresh,
    );
  }

  for (final make in [consumer, provider, admin]) {
    group('in-memory twin: ${make().name}', () {
      test('the first exchange rotates; the pair is fresh', () async {
        final t = make();
        final first = await t.login();
        final r = await t.refresh(first.refreshToken);
        expect(r.outcome, RefreshOutcome.rotated);
        expect(r.ok, isTrue);
        expect(r.error, isNull);
        expect(r.tokens!.refreshToken, isNot(first.refreshToken));
      });

      test('another exchange 29 s later is GRACE: a sibling, nothing revoked; '
          'the family lives on', () async {
        final t = make();
        final first = await t.login();
        final child = (await t.refresh(first.refreshToken)).tokens!;

        now = now.add(const Duration(seconds: 29));
        final again = await t.refresh(first.refreshToken);
        expect(again.outcome, RefreshOutcome.grace);
        expect(again.ok, isTrue);
        expect(again.error, isNull);
        final sibling = again.tokens!;
        expect(sibling.refreshToken, isNot(child.refreshToken));
        expect(sibling.refreshToken, isNot(first.refreshToken));

        // Both descendants are live, unrotated tokens of the same family.
        expect(
          (await t.refresh(child.refreshToken)).outcome,
          RefreshOutcome.rotated,
        );
        expect(
          (await t.refresh(sibling.refreshToken)).outcome,
          RefreshOutcome.rotated,
        );
      });

      test(
        'the boundary is inclusive, as the SQL `>=` is: exactly 30 s → grace',
        () async {
          final t = make();
          final first = await t.login();
          await t.refresh(first.refreshToken);
          now = now.add(kRefreshReuseGrace);
          expect(
            (await t.refresh(first.refreshToken)).outcome,
            RefreshOutcome.grace,
          );
        },
      );

      test('31 s later it is REUSE: refresh_reused, and the whole family — '
          'child and grace sibling — is revoked', () async {
        final t = make();
        final first = await t.login();
        final child = (await t.refresh(first.refreshToken)).tokens!;
        now = now.add(const Duration(seconds: 10));
        final sibling = (await t.refresh(first.refreshToken)).tokens!;

        // 31 s after the ROTATION — the grace runs from the claim, not from the
        // last sibling, so a stream of replays cannot keep it open.
        now = now.add(const Duration(seconds: 21));
        final reuse = await t.refresh(first.refreshToken);
        expect(reuse.outcome, RefreshOutcome.reused);
        expect(reuse.ok, isFalse);
        expect(reuse.error, 'refresh_reused');
        expect(reuse.tokens, isNull);

        for (final dead in [child, sibling]) {
          final r = await t.refresh(dead.refreshToken);
          expect(r.outcome, RefreshOutcome.invalid);
          expect(r.error, 'refresh_invalid');
        }
      });

      test('an unknown token → refresh_invalid', () async {
        final r = await make().refresh('never-issued');
        expect(r.outcome, RefreshOutcome.invalid);
        expect(r.ok, isFalse);
        expect(r.error, 'refresh_invalid');
        expect(r.tokens, isNull);
      });

      test('N = 8 at once: exactly one rotates, seven are grace', () async {
        final t = make();
        final first = await t.login();
        final results = await Future.wait([
          for (var i = 0; i < 8; i++) t.refresh(first.refreshToken),
        ]);
        expect(results.every((r) => r.ok), isTrue);
        expect(
          results.where((r) => r.outcome == RefreshOutcome.rotated),
          hasLength(1),
        );
        expect(
          results.where((r) => r.outcome == RefreshOutcome.grace),
          hasLength(7),
        );
        expect(
          results.map((r) => r.tokens!.refreshToken).toSet(),
          hasLength(8),
          reason: 'every caller gets its own pair',
        );
      });
    });
  }

  group('the refresh routes log one outcome line', () {
    Request post(String path, Object body) => Request.post(
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
    );

    /// Runs [handler] and collects what it printed.
    Future<(Response, List<String>)> run(
      Future<Response> Function() handler,
    ) async {
      final lines = <String>[];
      final res = await runZoned(
        handler,
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => lines.add(line),
        ),
      );
      return (res, lines);
    }

    RequestContext ctx<R extends Object>(
      Request request,
      R repo, {
      String? requestId,
    }) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<R>()).thenReturn(repo);
      if (requestId != null) {
        when(() => c.read<RequestId>()).thenReturn(RequestId(requestId));
      }
      return c;
    }

    /// Everything secret the exchange touched — the presented pair, its hash,
    /// and the pair in the response [body] — none of which may be logged.
    List<String> secrets(TokenPair first, String body) {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return [
        first.refreshToken,
        first.accessToken,
        tokens.hashToken(first.refreshToken),
        if (json['refreshToken'] case final String r) ...[
          r,
          tokens.hashToken(r),
        ],
        if (json['accessToken'] case final String a) a,
      ];
    }

    test('consumer: rotated → 200, reused → 401 refresh_reused, each logged '
        'with principal, outcome and request id — and no token', () async {
      final repo = InMemoryAuthRepository(
        tokens: tokens,
        echoDevCode: true,
        clock: clock,
      );
      final code = (await repo.requestEmailOtp('log@myweli.test')).devCode!;
      final first = (await repo.verifyEmailOtp(
        'log@myweli.test',
        code,
      )).tokens!;

      final (ok, okLines) = await run(
        () => consumer_refresh.onRequest(
          ctx<AuthRepository>(
            post('/auth/refresh', {'refreshToken': first.refreshToken}),
            repo,
            requestId: 'req-c1',
          ),
        ),
      );
      expect(ok.statusCode, HttpStatus.ok);
      final okBody = await ok.body();
      expect(okLines, [
        'INFO: auth_refresh principal=consumer outcome=rotated '
            'request_id=req-c1',
      ]);

      now = now.add(kRefreshReuseGrace + const Duration(seconds: 1));
      final (reused, reusedLines) = await run(
        () => consumer_refresh.onRequest(
          ctx<AuthRepository>(
            post('/auth/refresh', {'refreshToken': first.refreshToken}),
            repo,
            requestId: 'req-c2',
          ),
        ),
      );
      expect(reused.statusCode, HttpStatus.unauthorized);
      expect(
        (jsonDecode(await reused.body()) as Map)['error'],
        'refresh_reused',
      );
      expect(reusedLines, [
        'INFO: auth_refresh principal=consumer outcome=reused '
            'request_id=req-c2',
      ]);

      for (final line in [...okLines, ...reusedLines]) {
        for (final s in secrets(first, okBody)) {
          expect(line, isNot(contains(s)));
        }
      }
    });

    test('provider: rotated, then grace — both 200, both logged', () async {
      final repo = InMemoryProviderAuthRepository(
        tokens: tokens,
        echoDevCode: true,
        clock: clock,
      );
      final first = (await repo.register(
        businessName: 'Log Salon',
        businessType: 'salon',
        phoneNumber: '+2250700000999',
        email: 'plog@myweli.test',
        authProvider: 'google',
        googleSub: 'g-log',
      )).tokens!;

      final lines = <String>[];
      final bodies = <String>[];
      for (final id in ['req-p1', 'req-p2']) {
        final (res, out) = await run(
          () => provider_refresh.onRequest(
            ctx<ProviderAuthRepository>(
              post('/auth/provider/refresh', {
                'refreshToken': first.refreshToken,
              }),
              repo,
              requestId: id,
            ),
          ),
        );
        expect(res.statusCode, HttpStatus.ok);
        bodies.add(await res.body());
        lines.addAll(out);
      }
      expect(lines, [
        'INFO: auth_refresh principal=provider outcome=rotated '
            'request_id=req-p1',
        'INFO: auth_refresh principal=provider outcome=grace '
            'request_id=req-p2',
      ]);
      for (final line in lines) {
        for (final body in bodies) {
          for (final s in secrets(first, body)) {
            expect(line, isNot(contains(s)));
          }
        }
      }
    });

    test('all three: a non-text refreshToken → 400 invalid_body, not 500 '
        '(docs/design/phone-leftovers.md §3)', () async {
      for (final (route, path) in <(Handler, String)>[
        (consumer_refresh.onRequest, '/auth/refresh'),
        (provider_refresh.onRequest, '/auth/provider/refresh'),
        (admin_refresh.onRequest, '/admin/auth/refresh'),
      ]) {
        // No repository: the body is refused before any is read.
        final res = await observed(
          route,
          ctx(post(path, {'refreshToken': 12345}), Object()),
        );
        expect(res.statusCode, HttpStatus.badRequest, reason: path);
        expect((jsonDecode(await res.body()) as Map)['error'], 'invalid_body');
      }
    });

    test('admin: an unknown token → 401 refresh_invalid, logged', () async {
      final repo = InMemoryAdminAuthRepository(tokens: tokens, clock: clock);
      final (res, lines) = await run(
        () => admin_refresh.onRequest(
          ctx<AdminAuthRepository>(
            post('/admin/auth/refresh', {'refreshToken': 'never-issued'}),
            repo,
            requestId: 'req-a1',
          ),
        ),
      );
      expect(res.statusCode, HttpStatus.unauthorized);
      expect((jsonDecode(await res.body()) as Map)['error'], 'refresh_invalid');
      expect(lines, [
        'INFO: auth_refresh principal=admin outcome=invalid request_id=req-a1',
      ]);
      expect(lines.single, isNot(contains('never-issued')));
    });

    test('admin: rotated → 200, logged', () async {
      final repo = InMemoryAdminAuthRepository(tokens: tokens, clock: clock);
      await repo.ensureSeedAdmin(
        email: 'alog@myweli.test',
        password: 'secret123',
      );
      final first = (await repo.login('alog@myweli.test', 'secret123')).tokens!;
      final (res, lines) = await run(
        () => admin_refresh.onRequest(
          ctx<AdminAuthRepository>(
            post('/admin/auth/refresh', {'refreshToken': first.refreshToken}),
            repo,
            requestId: 'req-a2',
          ),
        ),
      );
      expect(res.statusCode, HttpStatus.ok);
      expect(lines, [
        'INFO: auth_refresh principal=admin outcome=rotated request_id=req-a2',
      ]);
      for (final s in secrets(first, await res.body())) {
        expect(lines.single, isNot(contains(s)));
      }
    });

    test(
      'no request id in the context: the log says `none` and the rotation '
      'still answers 200 — a log line never fails a committed exchange',
      () async {
        final repo = InMemoryAuthRepository(
          tokens: tokens,
          echoDevCode: true,
          clock: clock,
        );
        final code = (await repo.requestEmailOtp('noid@myweli.test')).devCode!;
        final first = (await repo.verifyEmailOtp(
          'noid@myweli.test',
          code,
        )).tokens!;
        final (res, lines) = await run(
          () => consumer_refresh.onRequest(
            ctx<AuthRepository>(
              post('/auth/refresh', {'refreshToken': first.refreshToken}),
              repo,
            ),
          ),
        );
        expect(res.statusCode, HttpStatus.ok);
        expect(lines, [
          'INFO: auth_refresh principal=consumer outcome=rotated request_id=none',
        ]);
      },
    );

    test('a 400 (no exchange happened) logs nothing', () async {
      final repo = InMemoryAuthRepository(tokens: tokens, echoDevCode: true);
      final (res, lines) = await run(
        () => consumer_refresh.onRequest(
          ctx<AuthRepository>(
            post('/auth/refresh', {'refreshToken': ''}),
            repo,
            requestId: 'req-x',
          ),
        ),
      );
      expect(res.statusCode, HttpStatus.badRequest);
      expect(lines, isEmpty);
    });
  });
}
