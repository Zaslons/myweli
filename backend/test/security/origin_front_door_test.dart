import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/security/origin_auth.dart';
import 'package:myweli_backend/src/security/origin_front_door.dart';
import 'package:myweli_backend/src/security/rate_limiter.dart';
import 'package:test/test.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// A limiter that records whether it was consulted, and can be told to throw.
class _SpyLimiter implements RateLimiter {
  _SpyLimiter(this._inner, {this.throws = false});

  final RateLimiter _inner;
  final bool throws;
  final List<String> buckets = [];

  @override
  Future<RateVerdict> hit(
    String bucket, {
    required int limit,
    required Duration window,
  }) {
    buckets.add(bucket);
    if (throws) throw StateError('limiter is down');
    return _inner.hit(bucket, limit: limit, window: window);
  }

  @override
  Future<int> used(String bucket, {required Duration window}) =>
      _inner.used(bucket, window: window);
}

/// The twelve middleware cases of the spec's §8, in its order.
///
/// Each rejection sits beside its control, and the two ORDER properties the
/// design rests on get their own cases: the IP is never read before the header
/// verified (8), and `/health` is exact rather than a prefix (1).
///
/// Design: docs/design/infra-cloudflare-front-door.md §5.2, §8
void main() {
  const secret = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEF'; // ≥ 32
  const enforce = OriginAuthOn(secret: secret, mode: OriginAuthMode.enforce);
  const logMode = OriginAuthOn(secret: secret, mode: OriginAuthMode.log);

  RequestContext ctx(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
  }) {
    final c = _MockRequestContext();
    when(() => c.request).thenReturn(
      Request(method, Uri.parse('http://localhost$path'), headers: headers),
    );
    return c;
  }

  /// Runs one request through the middleware with a recording inner and a
  /// recording log; returns the response plus what was observed.
  Future<({Response res, bool innerRan, List<String> log})> run(
    OriginAuth auth,
    RequestContext context, {
    RateLimiter? limiter,
  }) async {
    var innerRan = false;
    final log = <String>[];
    final res =
        await ((RequestContext _) {
          innerRan = true;
          return Response.json(body: {'ok': true});
        }).use(
          originFrontDoorMiddleware(
            () => auth,
            () => limiter ?? _SpyLimiter(InMemoryRateLimiter()),
            log: log.add,
          ),
        )(context);
    return (res: res, innerRan: innerRan, log: log);
  }

  group('1. /health is exempt, and exactly /health', () {
    test('GET /health without the header under enforce → passes', () async {
      final r = await run(enforce, ctx('/health'));
      expect(r.res.statusCode, HttpStatus.ok);
      expect(r.innerRan, isTrue, reason: 'the liveness probe carries nothing');
      expect(r.log, isEmpty);
    });

    test('control: /healthz → 403 — a prefix match would exempt it', () async {
      final r = await run(enforce, ctx('/healthz'));
      expect(r.res.statusCode, HttpStatus.forbidden);
      expect(r.innerRan, isFalse);
    });
  });

  group('2. OriginAuthOff', () {
    test('passes with no log, header or not', () async {
      final r = await run(const OriginAuthOff(), ctx('/providers'));
      expect(r.res.statusCode, HttpStatus.ok);
      expect(r.innerRan, isTrue);
      expect(r.log, isEmpty);
    });
  });

  group('3. enforce, no header', () {
    test('→ 403 origin_required, inner not run, one log line', () async {
      final r = await run(enforce, ctx('/providers?commune=abidjan'));
      expect(r.res.statusCode, HttpStatus.forbidden);
      expect(jsonDecode(await r.res.body()), {
        'error': 'origin_required',
        'message': 'Requests must come through api.myweli.com.',
      });
      expect(r.innerRan, isFalse);
      expect(r.log, ['origin_auth_missing method=GET path=/providers']);
    });

    test('the log line never carries the query string', () async {
      // Query strings are where secrets end up by accident — the request-id
      // middleware's own rule, kept here.
      final r = await run(enforce, ctx('/providers?token=SECRET-VALUE'));
      expect(r.log.single, isNot(contains('SECRET-VALUE')));
      expect(r.log.single, isNot(contains('?')));
    });

    test('nor any header value', () async {
      final r = await run(
        enforce,
        ctx(
          '/providers',
          headers: {
            'x-myweli-origin-auth': 'WRONG-BUT-PRESENT-abcdefghijklmnopqrs',
            'authorization': 'Bearer TOKEN-VALUE',
          },
        ),
      );
      expect(r.res.statusCode, HttpStatus.forbidden);
      expect(r.log.single, isNot(contains('WRONG-BUT-PRESENT')));
      expect(r.log.single, isNot(contains('TOKEN-VALUE')));
    });
  });

  group('4. enforce, wrong value', () {
    test('same length, one character off → 403', () async {
      final off = '${secret.substring(0, secret.length - 1)}x';
      expect(off.length, secret.length);
      final r = await run(
        enforce,
        ctx('/providers', headers: {'x-myweli-origin-auth': off}),
      );
      expect(r.res.statusCode, HttpStatus.forbidden);
      expect(r.innerRan, isFalse);
    });

    test('a prefix of the secret → 403', () async {
      final r = await run(
        enforce,
        ctx(
          '/providers',
          headers: {'x-myweli-origin-auth': secret.substring(0, 32)},
        ),
      );
      expect(r.res.statusCode, HttpStatus.forbidden);
    });
  });

  group('5. enforce, right value', () {
    test('→ passes, inner ran, no log', () async {
      final r = await run(
        enforce,
        ctx('/providers', headers: {'x-myweli-origin-auth': secret}),
      );
      expect(r.res.statusCode, HttpStatus.ok);
      expect(r.innerRan, isTrue);
      expect(r.log, isEmpty);
    });

    test('the header name is matched case-insensitively', () async {
      // The Worker sends `X-Myweli-Origin-Auth`; shelf lower-cases it.
      final r = await run(
        enforce,
        ctx('/providers', headers: {'X-Myweli-Origin-Auth': secret}),
      );
      expect(r.res.statusCode, HttpStatus.ok);
    });
  });

  group('6. log mode', () {
    test('no header → passes AND logs', () async {
      final r = await run(logMode, ctx('/providers', method: 'POST'));
      expect(r.res.statusCode, HttpStatus.ok);
      expect(r.innerRan, isTrue);
      expect(r.log, ['origin_auth_missing method=POST path=/providers']);
    });

    test('right value → passes, no log', () async {
      final r = await run(
        logMode,
        ctx('/providers', headers: {'x-myweli-origin-auth': secret}),
      );
      expect(r.res.statusCode, HttpStatus.ok);
      expect(r.log, isEmpty);
    });
  });

  group('7. preflights', () {
    test('OPTIONS /appointments with the header → passes', () async {
      // The Worker adds the header to EVERY method, so a browser preflight
      // from admin.myweli.com carries it and reaches the CORS middleware.
      final r = await run(
        enforce,
        ctx(
          '/appointments',
          method: 'OPTIONS',
          headers: {'x-myweli-origin-auth': secret},
        ),
      );
      expect(r.res.statusCode, HttpStatus.ok);
      expect(r.innerRan, isTrue);
    });
  });

  group('8. spoof — the IP is read only AFTER verification', () {
    test('no origin header + CF-Connecting-IP on /auth/otp/request → 403, '
        'limiter never called', () async {
      final spy = _SpyLimiter(InMemoryRateLimiter());
      final r = await run(
        enforce,
        ctx(
          '/auth/otp/request',
          method: 'POST',
          headers: {'cf-connecting-ip': '1.2.3.4'},
        ),
        limiter: spy,
      );
      expect(r.res.statusCode, HttpStatus.forbidden);
      expect(
        spy.buckets,
        isEmpty,
        reason:
            'on the direct door anyone can send CF-Connecting-IP; a forged '
            'one must be answered 403 before any limiter runs',
      );
    });

    test('in log mode an unverified request is ALSO never limited', () async {
      // The rollout window counts the door; it must not let a forged address
      // reach the limiter either.
      final spy = _SpyLimiter(InMemoryRateLimiter());
      final r = await run(
        logMode,
        ctx(
          '/auth/otp/request',
          method: 'POST',
          headers: {'cf-connecting-ip': '1.2.3.4'},
        ),
        limiter: spy,
      );
      expect(r.res.statusCode, HttpStatus.ok);
      expect(spy.buckets, isEmpty);
    });
  });

  group('9. verified, /auth/* — the per-IP limit', () {
    const ip = '203.0.113.9';
    RequestContext authReq(String path, {String from = ip}) => ctx(
      path,
      method: 'POST',
      headers: {'x-myweli-origin-auth': secret, 'cf-connecting-ip': from},
    );

    test('10 pass, the 11th → 429 rate_limited with the log line', () async {
      final spy = _SpyLimiter(InMemoryRateLimiter());
      for (var i = 1; i <= 10; i++) {
        final r = await run(
          enforce,
          authReq('/auth/otp/request'),
          limiter: spy,
        );
        expect(r.res.statusCode, HttpStatus.ok, reason: 'request $i of 10');
        expect(r.log, isEmpty, reason: 'no 80 % warning for IP buckets');
      }
      final r = await run(enforce, authReq('/auth/otp/request'), limiter: spy);
      expect(r.res.statusCode, HttpStatus.tooManyRequests);
      expect(jsonDecode(await r.res.body()), {'error': 'rate_limited'});
      expect(r.innerRan, isFalse);
      final bucket = ipAuthBucket(ip);
      expect(r.log, ['rate_limited bucket=$bucket hits=11 limit=10']);
      expect(r.res.headers.containsKey('retry-after'), isFalse);
    });

    test('a different IP is still at 1/10', () async {
      final inner = InMemoryRateLimiter();
      final spy = _SpyLimiter(inner);
      for (var i = 0; i < 11; i++) {
        await run(enforce, authReq('/auth/otp/request'), limiter: spy);
      }
      final other = await run(
        enforce,
        authReq('/auth/otp/request', from: '198.51.100.7'),
        limiter: spy,
      );
      expect(other.res.statusCode, HttpStatus.ok);
      expect(
        await inner.used(ipAuthBucket('198.51.100.7'), window: kIpAuthWindow),
        1,
      );
    });

    test('/providers from the same IP never touches the limiter', () async {
      final spy = _SpyLimiter(InMemoryRateLimiter());
      for (var i = 0; i < 12; i++) {
        final r = await run(
          enforce,
          ctx(
            '/providers',
            headers: {'x-myweli-origin-auth': secret, 'cf-connecting-ip': ip},
          ),
          limiter: spy,
        );
        expect(r.res.statusCode, HttpStatus.ok);
      }
      expect(spy.buckets, isEmpty);
    });

    test('/admin/auth/login shares the scope', () async {
      final spy = _SpyLimiter(InMemoryRateLimiter());
      for (var i = 0; i < 10; i++) {
        await run(enforce, authReq('/admin/auth/login'), limiter: spy);
      }
      final r = await run(enforce, authReq('/admin/auth/login'), limiter: spy);
      expect(r.res.statusCode, HttpStatus.tooManyRequests);
    });

    test('and /admin/auth/* counts in the same bucket as /auth/*', () async {
      // One address, one budget across both prefixes — Cloud Armor keyed on
      // the IP alone, and so does this.
      final spy = _SpyLimiter(InMemoryRateLimiter());
      for (var i = 0; i < 10; i++) {
        await run(enforce, authReq('/auth/otp/request'), limiter: spy);
      }
      final r = await run(enforce, authReq('/admin/auth/login'), limiter: spy);
      expect(r.res.statusCode, HttpStatus.tooManyRequests);
    });

    test('the bucket is ip:auth: + 32 hex, and the digest is NOT the IP', () {
      final b = ipAuthBucket(ip);
      expect(b, startsWith('ip:auth:'));
      expect(b, isNot(contains(ip)));
      expect(
        b.substring('ip:auth:'.length),
        matches(RegExp(r'^[0-9a-f]{32}$')),
      );
      // The first 32 hex of sha256('203.0.113.9') — pinned so a change of
      // hash or of prefix length is a test failure, not a silent re-keying
      // that forgives every address mid-window.
      final digest = sha256.convert(utf8.encode(ip)).toString();
      expect(b, 'ip:auth:${digest.substring(0, 32)}');
      expect(b, 'ip:auth:d861b7e91033ebc1c1e8e7af39290101');
    });

    test('the hit goes to the limiter with limit 10 / window 1 min', () async {
      final spy = _SpyLimiter(InMemoryRateLimiter());
      await run(enforce, authReq('/auth/otp/request'), limiter: spy);
      expect(spy.buckets, [ipAuthBucket(ip)]);
      expect(kIpAuthLimit, 10);
      expect(kIpAuthWindow, const Duration(minutes: 1));
    });
  });

  group('10. verified, no CF-Connecting-IP', () {
    test(
      '→ passes, logs origin_client_ip_missing, limiter never called',
      () async {
        final spy = _SpyLimiter(InMemoryRateLimiter());
        final r = await run(
          enforce,
          ctx(
            '/auth/otp/request',
            method: 'POST',
            headers: {'x-myweli-origin-auth': secret},
          ),
          limiter: spy,
        );
        expect(r.res.statusCode, HttpStatus.ok);
        expect(r.innerRan, isTrue);
        expect(r.log, ['origin_client_ip_missing path=/auth/otp/request']);
        expect(
          spy.buckets,
          isEmpty,
          reason: 'unknown must never silently collapse into one shared bucket',
        );
      },
    );
  });

  group('11. the limiter throws', () {
    test('→ the request passes; not a 500', () async {
      // Fail-open is FailOpenRateLimiter's job in production. This is the
      // limiter handed over WITHOUT the wrapper — the middleware must still
      // not turn a limiter error into a 500 on every sign-in.
      final spy = _SpyLimiter(InMemoryRateLimiter(), throws: true);
      final r = await run(
        enforce,
        ctx(
          '/auth/otp/request',
          method: 'POST',
          headers: {'x-myweli-origin-auth': secret, 'cf-connecting-ip': ip9},
        ),
        limiter: spy,
      );
      expect(r.res.statusCode, HttpStatus.ok);
      expect(r.innerRan, isTrue);
      expect(spy.buckets, hasLength(1), reason: 'it WAS consulted');
    });
  });

  group('12. the window', () {
    test(
      'with a fake clock, the 11th request in the next minute passes',
      () async {
        var now = DateTime.utc(2026, 9, 9, 10, 30, 15);
        final spy = _SpyLimiter(InMemoryRateLimiter(clock: () => now));
        RequestContext req() => ctx(
          '/auth/otp/request',
          method: 'POST',
          headers: {'x-myweli-origin-auth': secret, 'cf-connecting-ip': ip9},
        );
        for (var i = 0; i < 10; i++) {
          await run(enforce, req(), limiter: spy);
        }
        expect(
          (await run(enforce, req(), limiter: spy)).res.statusCode,
          HttpStatus.tooManyRequests,
        );
        now = DateTime.utc(2026, 9, 9, 10, 31, 0);
        expect(
          (await run(enforce, req(), limiter: spy)).res.statusCode,
          HttpStatus.ok,
          reason: 'a fixed one-minute window rolled',
        );
      },
    );
  });
}

const ip9 = '203.0.113.9';
