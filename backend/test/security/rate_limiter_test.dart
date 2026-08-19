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
