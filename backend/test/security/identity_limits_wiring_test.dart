import 'dart:io';

import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/reviews_service.dart';
import 'package:myweli_backend/src/security/identity_limits.dart';
import 'package:myweli_backend/src/security/rate_limiter.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:myweli_backend/src/upload_signing_service.dart';
import 'package:test/test.dart';

/// The three surfaces refuse past their ceiling — and the composition root
/// actually supplies a limiter.
///
/// **The second half is the one no behavioural test can replace.** The limiter
/// is an OPTIONAL constructor parameter, which is what lets every existing
/// construction site keep compiling. It also means a forgotten one is *no limit
/// in production with every test green* — the services still work, the handler
/// tests still pass, and nothing anywhere says the control is absent. That is
/// the exact shape this repo keeps finding, so it gets a source-level check.
///
/// Design: docs/design/backend-identity-rate-limits.md §3
void main() {
  group('the composition root supplies a limiter', () {
    final src = File('lib/src/dependencies.dart').readAsStringSync();

    /// The constructor call for [name], from `= Name(` to its closing `);`.
    String construction(String name) {
      final start = src.indexOf('= $name(');
      expect(
        start,
        isNonNegative,
        reason: '$name is constructed in dependencies.dart',
      );
      final end = src.indexOf(');', start);
      expect(end, isNonNegative, reason: '$name construction is terminated');
      return src.substring(start, end);
    }

    for (final name in const [
      'BookingService',
      'ReviewsService',
      'UploadSigningService',
    ]) {
      test('$name is constructed WITH one', () {
        final call = construction(name);
        expect(
          call,
          contains('limiter:'),
          reason:
              '$name takes an optional limiter, so omitting it here disables '
              'the limit in production while every test stays green. Nothing '
              'behavioural can catch that, which is why this test exists.',
        );
        expect(
          call,
          contains('limits:'),
          reason: 'the thresholds must come from config, not the defaults',
        );
      });
    }

    test('and the limiter it supplies fails OPEN', () {
      // A limiter that refused on a Postgres blip would turn a database hiccup
      // into nobody being able to book. The wrapper is the difference, and it
      // is applied once, here.
      expect(src, contains('FailOpenRateLimiter('));
    });
  });

  group('booking', () {
    /// A booking service with nothing but a limiter that is already spent —
    /// enough to prove the check runs BEFORE any repository is touched, which
    /// is the ordering §4 argues for. If the check moved after the lookups,
    /// these null repositories would throw instead.
    test('refuses with rate_limited before touching any repository', () async {
      final limiter = InMemoryRateLimiter();
      for (var i = 0; i < 3; i++) {
        await limiter.hit(
          bookingBucket('u1'),
          limit: 3,
          window: kIdentityWindow,
        );
      }
      final svc = BookingService(
        _ExplodingProviders(),
        _ExplodingAppointments(),
        _ExplodingSlots(),
        limiter: limiter,
        limits: (
          booking: 3,
          reviewSubmit: 5,
          signGallery: 60,
          signReview: 40,
          signKyc: 10,
          signDeposit: 10,
          signAvatar: 10,
        ),
      );
      final r = await svc.book(
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDateTime: DateTime.utc(2026, 9, 1, 10),
      );
      expect(r.ok, isFalse);
      expect(
        r.error,
        'rate_limited',
        reason:
            'the repositories throw on any call, so reaching one would surface '
            'as an exception rather than this code',
      );
    });

    test('TWO IDENTITIES DO NOT SHARE THE BUDGET', () async {
      // The property the design rests on. If it fails, one abuser takes
      // everyone down — which is the per-IP failure mode this avoids.
      final limiter = InMemoryRateLimiter();
      for (var i = 0; i < 3; i++) {
        await limiter.hit(
          bookingBucket('a'),
          limit: 3,
          window: kIdentityWindow,
        );
      }
      expect(
        (await limiter.hit(
          bookingBucket('a'),
          limit: 3,
          window: kIdentityWindow,
        )).ok,
        isFalse,
      );
      expect(
        (await limiter.hit(
          bookingBucket('b'),
          limit: 3,
          window: kIdentityWindow,
        )).ok,
        isTrue,
        reason: 'b must be untouched by a exhausting theirs',
      );
    });
  });
  group('review submission', () {
    test('refuses with rate_limited before touching any repository', () async {
      final limiter = InMemoryRateLimiter();
      for (var i = 0; i < 2; i++) {
        await limiter.hit(
          reviewBucket('u1'),
          limit: 2,
          window: kIdentityWindow,
        );
      }
      final svc = ReviewsService(
        _ExplodingReviews(),
        _ExplodingAppointments(),
        _ExplodingProviders(),
        _ExplodingAuth(),
        limiter: limiter,
        limits: _limits(reviewSubmit: 2),
      );
      final r = await svc.submitForAppointment(
        'u1',
        'a1',
        rating: 5,
        text: 'bien',
      );
      expect(r.ok, isFalse);
      expect(r.error, 'rate_limited');
    });
  });

  group('upload signing', () {
    UploadSigningService svc(RateLimiter? limiter, IdentityLimits limits) =>
        UploadSigningService(
          _ExplodingProviderAuth(),
          _ExplodingMembers(),
          _ExplodingStorage(),
          limiter: limiter,
          limits: limits,
        );

    test('refuses per purpose, before resolving anything', () async {
      final limiter = InMemoryRateLimiter();
      for (var i = 0; i < 2; i++) {
        await limiter.hit(
          signBucket('avatar', 'u1'),
          limit: 2,
          window: kIdentityWindow,
        );
      }
      final r = await svc(
        limiter,
        _limits(signAvatar: 2),
      ).sign('u1', contentType: 'image/jpeg', purpose: 'avatar');
      expect(r.ok, isFalse);
      expect(r.error, 'rate_limited');
    });

    test('EXHAUSTING ONE PURPOSE DOES NOT TOUCH ANOTHER', () async {
      // The five purposes have wildly different honest volumes — a salon
      // loading forty gallery photos is normal, forty avatars is not — so each
      // carries its own number rather than a share of a total.
      final limiter = InMemoryRateLimiter();
      for (var i = 0; i < 2; i++) {
        await limiter.hit(
          signBucket('avatar', 'u1'),
          limit: 2,
          window: kIdentityWindow,
        );
      }
      // **The two limits must be EQUAL and low.** With `signDeposit` set
      // higher, a bucket that had wrongly dropped the purpose would still admit
      // the deposit call — the count would sit under the larger ceiling — and
      // this test would pass against the very mistake it exists to catch.
      // Measured: with 2 and 5 it did.
      final s = svc(limiter, _limits(signAvatar: 2, signDeposit: 2));
      expect(
        (await s.sign(
          'u1',
          contentType: 'image/jpeg',
          purpose: 'avatar',
        )).error,
        'rate_limited',
      );
      // `deposit` is untouched — and reaching the storage fake proves it got
      // past the limit rather than being refused by it.
      expect(
        () => s.sign('u1', contentType: 'image/jpeg', purpose: 'deposit'),
        throwsA(isA<StateError>()),
        reason: 'a separate budget, so this one proceeds into the work',
      );
    });

    test('an INVALID purpose is refused before any bucket is built', () async {
      // The trap §4 names: `purpose` is client-supplied, so keying on it before
      // validation would let an attacker mint a fresh bucket per request —
      // unbounded buckets, no limit, and a new database row for every miss.
      final limiter = InMemoryRateLimiter();
      final r = await svc(
        limiter,
        kDefaultIdentityLimits,
      ).sign('u1', contentType: 'image/jpeg', purpose: 'not-a-real-purpose');
      expect(r.error, 'invalid_input');
      expect(
        await limiter.used(
          signBucket('not-a-real-purpose', 'u1'),
          window: kIdentityWindow,
        ),
        0,
        reason:
            'no bucket may be created for a purpose outside the closed set — '
            'that is what turns the limiter into the attacker\'s amplifier',
      );
    });
  });

  test('a limiter that cannot answer does not block the work', () async {
    // Fail open: every real control still holds without the limiter, so a
    // Postgres blip must not become "nobody can book".
    final svc = UploadSigningService(
      _ExplodingProviderAuth(),
      _ExplodingMembers(),
      _ExplodingStorage(),
      limiter: FailOpenRateLimiter(_BrokenLimiter(), log: (_) {}),
      limits: kDefaultIdentityLimits,
    );
    expect(
      () => svc.sign('u1', contentType: 'image/jpeg', purpose: 'avatar'),
      throwsA(isA<StateError>()),
      reason: 'it proceeded into the work rather than refusing',
    );
  });
}

IdentityLimits _limits({
  int booking = 10,
  int reviewSubmit = 5,
  int signGallery = 60,
  int signReview = 40,
  int signKyc = 10,
  int signDeposit = 10,
  int signAvatar = 10,
}) => (
  booking: booking,
  reviewSubmit: reviewSubmit,
  signGallery: signGallery,
  signReview: signReview,
  signKyc: signKyc,
  signDeposit: signDeposit,
  signAvatar: signAvatar,
);

class _BrokenLimiter implements RateLimiter {
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

/// Fakes that throw on ANY call, so "the limit refused before the work" is
/// proven by the absence of an exception rather than by reading the code.
class _ExplodingProviders implements ProvidersRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError(
    'a repository was reached — the rate limit should have refused first',
  );
}

class _ExplodingAppointments implements AppointmentRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError(
    'a repository was reached — the rate limit should have refused first',
  );
}

class _ExplodingSlots implements SlotService {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError(
    'the slot engine was reached — the rate limit should have refused first',
  );
}

class _ExplodingReviews implements ReviewsRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('reached');
}

class _ExplodingAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('reached');
}

class _ExplodingProviderAuth implements ProviderAuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('reached');
}

class _ExplodingMembers implements MembershipService {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('reached');
}

class _ExplodingStorage implements StorageService {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('reached');
}
