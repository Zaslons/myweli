import 'dart:io';

import 'package:test/test.dart';

/// The origin gate is WIRED — source-level pins in the
/// `identity_limits_wiring_test` shape.
///
/// **Why a behavioural test cannot replace these.** The middleware is a
/// function that takes two callbacks; nothing obliges `routes/_middleware.dart`
/// to call it, and if it did not, every route test would still pass — the gate
/// would simply not exist in production, with `/health` green throughout.
/// The same for `originAuth`: a `final` nobody lists in
/// `_assertConfiguredDependenciesResolve` is resolved on first use, i.e. on the
/// first request through the open door rather than at boot. And the compare:
/// `==` on a 64-character secret compiles, passes every equality test, and
/// leaks the secret one prefix at a time.
///
/// Design: docs/design/infra-cloudflare-front-door.md §5.2, §8
void main() {
  group('routes/_middleware.dart', () {
    final src = File('routes/_middleware.dart').readAsStringSync();

    test('uses originFrontDoorMiddleware with BOTH callbacks', () {
      expect(
        src,
        contains(
          '.use(originFrontDoorMiddleware(() => originAuth, () => rateLimiter))',
        ),
        reason:
            'a value instead of a callback would evaluate the env-derived '
            'final at chain-build time and pre-empt the aggregated boot check',
      );
    });

    test('placed INSIDE CORS and OUTSIDE every provider', () {
      final cors = src.indexOf('.use(corsMiddleware(');
      final door = src.indexOf('.use(originFrontDoorMiddleware(');
      final obs = src.indexOf('.use(observabilityMiddleware(');
      final lastProvider = src.lastIndexOf('.use(provider<');
      expect(cors, isNonNegative);
      expect(door, isNonNegative);
      expect(obs, isNonNegative);
      // dart_frog: the LAST `.use` is OUTERMOST. Inside CORS = before it in
      // file order, so a 429 gets the CORS headers and a preflight is answered
      // before the limiter counts it; after every provider in file order =
      // outside them, so nothing that reaches a database runs unverified.
      expect(door, greaterThan(lastProvider), reason: 'outside every provider');
      expect(door, lessThan(cors), reason: 'inside CORS (before it in file)');
      expect(door, lessThan(obs), reason: 'inside observability');
    });
  });

  group('lib/src/dependencies.dart', () {
    final src = File('lib/src/dependencies.dart').readAsStringSync();

    test('constructs originAuth from BOTH env names', () {
      final start = src.indexOf(
        'final OriginAuth originAuth = resolveOriginAuth(',
      );
      expect(start, isNonNegative, reason: 'the singleton exists');
      final call = src.substring(start, src.indexOf(');', start));
      expect(call, contains("_envOrNull('ORIGIN_AUTH_SECRET')"));
      expect(call, contains("_envOrNull('ORIGIN_AUTH_MODE')"));
      expect(
        call,
        contains('isProd: _isProd'),
        reason:
            'prod-only, not guardsOn: staging has no Worker and keeps its '
            'run.app door public by design',
      );
    });

    test('lists originAuth in _assertConfiguredDependenciesResolve', () {
      final start = src.indexOf('void _assertConfiguredDependenciesResolve()');
      expect(start, isNonNegative);
      final body = src.substring(start, src.indexOf('\n}\n', start));
      expect(
        body,
        contains("'originAuth': () => originAuth,"),
        reason:
            'a mis-set value must die at boot in the aggregated line, never '
            'on the first request',
      );
    });

    test('the cron prune reaches the UNWRAPPED Postgres limiter, reported', () {
      expect(
        src,
        contains('Future<int?> pruneRateLimitWindows(Duration olderThan)'),
        reason: 'null is how a failed prune is reported to the cron',
      );
      expect(
        src,
        contains('final limiter = _postgresRateLimiter;'),
        reason: 'FailOpenRateLimiter hides what it wraps; the prune needs it',
      );
      expect(
        src,
        contains('pruneOrReport(() => limiter.prune(olderThan))'),
        reason: 'a prune that throws must not fail the cron it rides on',
      );
      expect(
        src,
        contains(
          'FailOpenRateLimiter(\n  _postgresRateLimiter ?? InMemoryRateLimiter(),\n)',
        ),
        reason: 'and the request path still goes through the fail-open wrapper',
      );
    });
  });

  group('lib/src/security/origin_front_door.dart', () {
    final src = File(
      'lib/src/security/origin_front_door.dart',
    ).readAsStringSync();

    test('compares the secret with constantTimeEquals, never ==', () {
      expect(
        src,
        contains("import '../auth/smoke_seam.dart' show constantTimeEquals;"),
      );
      expect(src, contains('constantTimeEquals(on.secret, provided)'));
      expect(
        src,
        isNot(contains('== on.secret')),
        reason:
            'a short-circuiting compare leaks the secret one prefix at a time',
      );
      expect(src, isNot(contains('on.secret ==')));
    });

    test('the exemption is path-EXACT', () {
      expect(src, contains("const String kOriginAuthExemptPath = '/health';"));
      expect(src, contains('if (path == kOriginAuthExemptPath)'));
      expect(
        src,
        isNot(contains("startsWith('/health")),
        reason: 'a prefix match would exempt /healthz-anything',
      );
    });

    test('the header names are the fixed strings the Worker sends', () {
      expect(
        src,
        contains("const String kOriginAuthHeader = 'x-myweli-origin-auth';"),
      );
      expect(
        src,
        contains("const String kClientIpHeader = 'cf-connecting-ip';"),
      );
    });

    test(
      'the log lines are the ones the runbooks and the rollout grep for',
      () {
        expect(src, contains("'origin_auth_missing method="));
        expect(src, contains("'origin_client_ip_missing path="));
        expect(src, contains("'rate_limited bucket="));
        expect(
          src,
          isNot(contains('rate_limit_warning')),
          reason: 'no 80 % warning for IP buckets — spec §5.2',
        );
      },
    );
  });

  group('routes/internal/cron/subscriptions.dart', () {
    final src = File(
      'routes/internal/cron/subscriptions.dart',
    ).readAsStringSync();

    test('calls pruneRateLimitWindows daily, and returns the count', () {
      expect(
        src,
        contains('await pruneRateLimitWindows(const Duration(days: 1))'),
      );
      expect(
        src,
        contains("'rateLimitWindowsPruned':"),
        reason: 'a prune nobody can see is the shape this repo keeps finding',
      );
    });
  });
}
