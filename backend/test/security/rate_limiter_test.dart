import 'dart:io';

import 'package:myweli_backend/src/db/postgres_rate_limiter.dart';
import 'package:myweli_backend/src/security/identity_limits.dart';
import 'package:myweli_backend/src/security/rate_limiter.dart';
import 'package:test/test.dart';

/// The per-identity limiter — the mechanism, before anything calls it.
///
/// `docs/design/backend-rate-limiting.md` §1 measured two gaps. The auth one
/// was closed by Cloud Armor; the row reading `Booking routes — no limit of any
/// kind` was not. This is the mechanism that closes it, and it ships inert:
/// nothing calls `hit` until the surfaces are wired.
///
/// Design: docs/design/backend-identity-rate-limits.md
void main() {
  group('the ceiling', () {
    test('under it passes, AT it passes, one over refuses', () async {
      final l = InMemoryRateLimiter();
      for (var i = 1; i <= 10; i++) {
        final v = await l.hit('k', limit: 10, window: kIdentityWindow);
        expect(v.ok, isTrue, reason: 'hit $i of 10 must be allowed');
        expect(v.hits, i);
        expect(v.limit, 10);
      }
      // The off-by-one that matters: the 10th of 10 is allowed, the 11th is not.
      expect(
        (await l.hit('k', limit: 10, window: kIdentityWindow)).ok,
        isFalse,
      );
    });

    test('the window rolls', () async {
      var now = DateTime.utc(2026, 8, 19, 10, 30);
      final l = InMemoryRateLimiter(clock: () => now);
      expect((await l.hit('k', limit: 1, window: kIdentityWindow)).ok, isTrue);
      expect((await l.hit('k', limit: 1, window: kIdentityWindow)).ok, isFalse);
      now = DateTime.utc(2026, 8, 19, 11, 0);
      expect(
        (await l.hit('k', limit: 1, window: kIdentityWindow)).ok,
        isTrue,
        reason: 'a new hour is a new budget',
      );
    });

    test('a boundary permits 2x the limit, and that is DOCUMENTED', () async {
      // A fixed window, not a sliding one. Stated here rather than discovered:
      // `email_send_budget` has the identical property and never says so. The
      // answer if it ever matters is a shorter window — sliding needs a row per
      // request, which is the write amplification this design avoids.
      var now = DateTime.utc(2026, 8, 19, 10, 59, 59);
      final l = InMemoryRateLimiter(clock: () => now);
      for (var i = 0; i < 10; i++) {
        expect(
          (await l.hit('k', limit: 10, window: kIdentityWindow)).ok,
          isTrue,
        );
      }
      now = DateTime.utc(2026, 8, 19, 11, 0, 1);
      for (var i = 0; i < 10; i++) {
        expect(
          (await l.hit('k', limit: 10, window: kIdentityWindow)).ok,
          isTrue,
        );
      }
      // 20 in two seconds, by design.
    });
  });

  test('TWO IDENTITIES DO NOT SHARE A BUDGET', () async {
    // The property the whole design rests on. If it fails, one abuser takes
    // everyone down — which is the per-IP failure mode this exists to avoid.
    final l = InMemoryRateLimiter();
    for (var i = 0; i < 10; i++) {
      await l.hit('book:user_a', limit: 10, window: kIdentityWindow);
    }
    expect(
      (await l.hit('book:user_a', limit: 10, window: kIdentityWindow)).ok,
      isFalse,
      reason: 'A is spent',
    );
    expect(
      (await l.hit('book:user_b', limit: 10, window: kIdentityWindow)).ok,
      isTrue,
      reason: 'B must be untouched by A exhausting theirs',
    );
  });

  test('concurrent hits cannot exceed the ceiling', () async {
    // The reservation is one atomic step for exactly this reason. A
    // read-then-write would let two callers both see 9 and both proceed.
    final l = InMemoryRateLimiter();
    final results = await Future.wait([
      for (var i = 0; i < 25; i++)
        l.hit('k', limit: 10, window: kIdentityWindow),
    ]);
    expect(results.where((r) => r.ok), hasLength(10));
  });

  group('a limiter that cannot answer does not refuse', () {
    test('a throwing store fails OPEN, and says so', () async {
      final logged = <String>[];
      final l = FailOpenRateLimiter(_Broken(), log: logged.add);
      final v = await l.hit('book:u1', limit: 10, window: kIdentityWindow);
      expect(
        v.ok,
        isTrue,
        reason:
            'every real control still holds without the limiter; failing '
            'closed would turn a Postgres blip into nobody being able to book',
      );
      expect(logged.single, contains('rate_limit_unavailable'));
      expect(logged.single, contains('book:u1'));
    });

    test('and `used` degrades to 0 rather than throwing', () async {
      final l = FailOpenRateLimiter(_Broken(), log: (_) {});
      expect(await l.used('k', window: kIdentityWindow), 0);
    });

    test('it is otherwise transparent', () async {
      final l = FailOpenRateLimiter(InMemoryRateLimiter(), log: (_) {});
      expect((await l.hit('k', limit: 1, window: kIdentityWindow)).ok, isTrue);
      expect((await l.hit('k', limit: 1, window: kIdentityWindow)).ok, isFalse);
    });
  });

  group('windowStart', () {
    test('floors to the epoch, so every instance agrees', () {
      final a = windowStart(
        DateTime.utc(2026, 8, 19, 10, 0, 0),
        kIdentityWindow,
      );
      final b = windowStart(
        DateTime.utc(2026, 8, 19, 10, 59, 59),
        kIdentityWindow,
      );
      expect(a, b);
      expect(
        windowStart(DateTime.utc(2026, 8, 19, 11, 0, 0), kIdentityWindow),
        isNot(a),
      );
    });

    test('works for any duration, not just an hour', () {
      const m = Duration(minutes: 5);
      expect(
        windowStart(DateTime.utc(2026, 8, 19, 10, 3), m),
        windowStart(DateTime.utc(2026, 8, 19, 10, 4, 59), m),
      );
      expect(
        windowStart(DateTime.utc(2026, 8, 19, 10, 5), m),
        isNot(windowStart(DateTime.utc(2026, 8, 19, 10, 4), m)),
      );
    });
  });

  group('what a refusal leaves behind', () {
    // **This is what replaces the probe.** The per-identity limits can be
    // provoked on staging, where the Q1b seam mints a token, and NOT on
    // production, where that seam is deliberately absent. So a limit that fires
    // in production would otherwise be invisible: the caller sees a 429 and we
    // see nothing. The log line is the only signal there will ever be.

    // The WARNING half. Until 2026-08-20 `warnAt` and the line it produces had
    // no test at all — no format, no cadence, no arithmetic — while the refusal
    // beside it had five. The asymmetry was invisible because nothing asked.

    test('a refusal is logged, every time', () async {
      final logged = <String>[];
      final l = InMemoryRateLimiter();
      for (var i = 0; i < 5; i++) {
        await allowUnderLimit(l, 'book:u1', 2, log: logged.add);
      }
      final refusals = logged.where((x) => x.startsWith('rate_limited'));
      expect(
        refusals,
        hasLength(3),
        reason:
            'EVERY refusal, unlike the warning — one line in an hour is a '
            'person who hit a ceiling, three hundred is an attacker being held',
      );
      expect(refusals.first, contains('bucket=book:u1'));
      expect(refusals.first, contains('limit=2'));
    });

    test('and it carries the count, which is the whole signal', () async {
      final logged = <String>[];
      final l = InMemoryRateLimiter();
      for (var i = 0; i < 4; i++) {
        await allowUnderLimit(l, 'book:u1', 2, log: logged.add);
      }
      final refusals = logged
          .where((x) => x.startsWith('rate_limited'))
          .toList();
      expect(refusals[0], contains('hits=3'));
      expect(refusals[1], contains('hits=4'));
    });

    test('an ALLOWED request logs no refusal', () async {
      // The control: a line that appeared on every call would make the alert
      // fire constantly and mean nothing.
      final logged = <String>[];
      await allowUnderLimit(
        InMemoryRateLimiter(),
        'book:u1',
        10,
        log: logged.add,
      );
      expect(logged.where((x) => x.startsWith('rate_limited')), isEmpty);
    });

    test('the line carries no recipient or address', () async {
      // Same rule as the send budget's: the bucket is a pseudonymous id, and
      // nothing else about the caller belongs in a log.
      final logged = <String>[];
      final l = InMemoryRateLimiter();
      for (var i = 0; i < 3; i++) {
        await allowUnderLimit(l, 'sign:avatar:user_abc', 1, log: logged.add);
      }
      for (final line in logged) {
        expect(line, isNot(contains('@')));
      }
    });

    test('the alert script watches the string the code actually prints', () {
      final script = File(
        '../infra/gcp/92-identity-limit-alert.sh',
      ).readAsStringSync();
      expect(script, contains('rate_limited'));
    });
  });

  group('what the warning leaves behind', () {
    test('it fires exactly ONCE per bucket per window', () async {
      // Compared with `==`, not `>=`, precisely so it fires once. The
      // refusal is the opposite: every time, because there the count is the
      // signal. Getting this backwards makes the early warning a flood.
      final logged = <String>[];
      final l = InMemoryRateLimiter();
      for (var i = 0; i < 12; i++) {
        await allowUnderLimit(l, 'book:u1', 10, log: logged.add);
      }
      expect(
        logged.where((x) => x.startsWith('rate_limit_warning')),
        hasLength(1),
        reason: 'once per crossing — the alert period assumes exactly this',
      );
    });

    test('it carries bucket, hits and limit, in that shape', () async {
      final logged = <String>[];
      final l = InMemoryRateLimiter();
      for (var i = 0; i < 8; i++) {
        await allowUnderLimit(l, 'book:u1', 10, log: logged.add);
      }
      final w = logged.firstWhere((x) => x.startsWith('rate_limit_warning'));
      expect(w, 'rate_limit_warning bucket=book:u1 hits=8 limit=10');
    });

    test('the warning arrives BEFORE the first refusal', () async {
      // Its whole worth is being early. If it could arrive after, it would be
      // a second alarm rather than a chance to act.
      final logged = <String>[];
      final l = InMemoryRateLimiter();
      for (var i = 0; i < 12; i++) {
        await allowUnderLimit(l, 'book:u1', 10, log: logged.add);
      }
      final w = logged.indexWhere((x) => x.startsWith('rate_limit_warning'));
      final r = logged.indexWhere((x) => x.startsWith('rate_limited'));
      expect(w, greaterThanOrEqualTo(0));
      expect(r, greaterThan(w));
    });

    test('a request below the mark logs nothing at all', () async {
      final logged = <String>[];
      await allowUnderLimit(
        InMemoryRateLimiter(),
        'book:u1',
        10,
        log: logged.add,
      );
      expect(logged, isEmpty);
    });

    test('warnAt is 80% of the ceiling, floored', () {
      expect(warnAt(10), 8);
      expect(warnAt(5), 4);
      expect(warnAt(60), 48);
      expect(warnAt(40), 32);
    });

    test('a ceiling too small to have an 80% never warns', () async {
      // warnAt(1) == 0, and a real limiter hands out hits starting at 1, so
      // nothing ever equals it. Latent rather than live — no default is that
      // small — but the ceilings are settable from the environment now, so an
      // operator can configure a surface into silence without being told.
      expect(warnAt(1), 0);
      expect(warnAt(0), 0);
      final logged = <String>[];
      final l = InMemoryRateLimiter();
      for (var i = 0; i < 4; i++) {
        await allowUnderLimit(l, 'book:u1', 1, log: logged.add);
      }
      expect(
        logged.where((x) => x.startsWith('rate_limit_warning')),
        isEmpty,
        reason: 'a ceiling of 1 is silent — the refusal is the only signal',
      );
    });

    test('reviewSubmit buys exactly one request of notice', () async {
      // warnAt(5) == 4, last allowed is 5, refusal at 6. Strictly earlier than
      // the refusal, but only just — the runbook says so, because on that
      // surface both alerts will often fire seconds apart.
      final logged = <String>[];
      final l = InMemoryRateLimiter();
      for (var i = 0; i < 6; i++) {
        await allowUnderLimit(l, 'review:u1', 5, log: logged.add);
      }
      final w = logged.indexWhere((x) => x.startsWith('rate_limit_warning'));
      final r = logged.indexWhere((x) => x.startsWith('rate_limited'));
      expect(logged[w], contains('hits=4'));
      expect(logged[r], contains('hits=6'));
    });
  });

  group('failing open means failing FAST', () {
    test('every limiter query carries a deadline', () {
      // Source-level, because the behaviour needs a database that accepts the
      // connection and then never answers — which cannot be arranged in a unit
      // test and must not be arranged in a deployed one.
      //
      // Counting call sites rather than grepping for the word: a file that
      // mentions `timeout` once while a second query goes unbounded is exactly
      // the shape this misses.
      final src = File(
        'lib/src/db/postgres_rate_limiter.dart',
      ).readAsStringSync();
      final calls = '_pool.execute('.allMatches(src).length;
      final bounded = 'timeout: kLimiterQueryTimeout'.allMatches(src).length;
      expect(
        calls,
        greaterThan(0),
        reason: 'the queries moved or were renamed',
      );
      expect(
        bounded,
        calls,
        reason:
            'an unbounded query cannot throw when the database wedges, so '
            'FailOpenRateLimiter never catches, rate_limit_unavailable is '
            'never printed, and the alert cannot fire in the one scenario it '
            'exists for — while the caller waits out Cloud Run\'s 300s',
      );
    });

    test('the deadline is well under the request deadline', () {
      expect(kLimiterQueryTimeout, lessThan(const Duration(seconds: 10)));
      expect(kLimiterQueryTimeout, greaterThan(const Duration(seconds: 1)));
    });

    test(
      'the fail-open verdict is allowed, uncounted, and announced',
      () async {
        final logged = <String>[];
        final v = await FailOpenRateLimiter(
          _ThrowingLimiter(),
          log: logged.add,
        ).hit('book:u1', limit: 10, window: const Duration(hours: 1));
        expect(v.ok, isTrue, reason: 'the request must go through');
        expect(
          v.hits,
          0,
          reason: 'nothing was counted, and it must not pretend',
        );
        expect(v.limit, 10);
        expect(logged, ['rate_limit_unavailable bucket=book:u1']);
      },
    );

    test('the announcement carries no exception text', () async {
      // The bucket says which surface is unbounded. A stack trace from the pool
      // says nothing a reader of this line needs, and is the usual way an
      // internal detail reaches a log that a human forwards elsewhere.
      final logged = <String>[];
      await FailOpenRateLimiter(
        _ThrowingLimiter(
          boom: 'connection refused to 10.1.2.3:5432 as myweli_app',
        ),
        log: logged.add,
      ).hit('book:u1', limit: 10, window: const Duration(hours: 1));
      expect(logged.single, isNot(contains('10.1.2.3')));
      expect(logged.single, isNot(contains('myweli_app')));
      expect(logged.single, isNot(contains('Exception')));
    });

    test('a fail-open verdict cannot raise a warning', () async {
      // The fabricated hits:0 equals warnAt for any ceiling of 0 or 1, so every
      // failed hit during an outage would announce a threshold nobody crossed.
      // No shipped ceiling is that small, but they are settable per environment.
      final logged = <String>[];
      await allowUnderLimit(
        FailOpenRateLimiter(_ThrowingLimiter(), log: (_) {}),
        'book:u1',
        1,
        log: logged.add,
      );
      expect(
        logged.where((x) => x.startsWith('rate_limit_warning')),
        isEmpty,
        reason: 'nothing was counted, so no threshold was crossed',
      );
    });
  });

  group('the policy', () {
    test('buckets are namespaced per surface', () {
      expect(bookingBucket('u1'), 'book:u1');
      expect(reviewBucket('u1'), 'review:u1');
      expect(signBucket('gallery', 'p1'), 'sign:gallery:p1');
      // No two surfaces can collide for one identity.
      final all = {
        bookingBucket('x'),
        reviewBucket('x'),
        signBucket('gallery', 'x'),
        signBucket('avatar', 'x'),
      };
      expect(all, hasLength(4));
    });

    test('sign limits are per purpose', () {
      const l = kDefaultIdentityLimits;
      expect(signLimitFor('gallery', l), l.signGallery);
      expect(signLimitFor('kyc', l), l.signKyc);
      expect(signLimitFor('avatar', l), l.signAvatar);
    });

    test('signReview clears reviewSubmit x maxPhotos — the composition', () {
      // The non-obvious lockout: a review carries up to 6 photos, so a user
      // submitting `reviewSubmit` reviews may need that many signs. Two
      // individually generous limits can compose into a refusal on a surface
      // the user never approached.
      const l = kDefaultIdentityLimits;
      const maxPhotosPerReview = 6; // ReviewsService._maxPhotos
      expect(
        l.signReview,
        greaterThanOrEqualTo(l.reviewSubmit * maxPhotosPerReview),
        reason:
            'raising reviewSubmit without raising signReview re-creates the '
            'composition lockout this number exists to prevent',
      );
    });

    test('the defaults are above plausible launch volume', () {
      const l = kDefaultIdentityLimits;
      expect(l.booking, greaterThanOrEqualTo(10));
      expect(
        l.signGallery,
        greaterThan(l.booking),
        reason: 'a salon loading a portfolio is the bursty legitimate case',
      );
    });
  });
}

class _Broken implements RateLimiter {
  @override
  Future<RateVerdict> hit(
    String bucket, {
    required int limit,
    required Duration window,
  }) async => throw StateError('pool is down');

  @override
  Future<int> used(String bucket, {required Duration window}) async =>
      throw StateError('pool is down');
}

class _ThrowingLimiter implements RateLimiter {
  _ThrowingLimiter({this.boom = 'down'});
  final String boom;

  @override
  Future<RateVerdict> hit(
    String bucket, {
    required int limit,
    required Duration window,
  }) async => throw Exception(boom);

  @override
  Future<int> used(String bucket, {required Duration window}) async =>
      throw Exception(boom);
}
