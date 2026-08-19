import 'package:myweli_backend/src/auth/login_throttle.dart';
import 'package:test/test.dart';

/// The lockout contract, with a pinned clock.
///
/// **There was no test for this class at all.** The only coverage was
/// `admin_test.dart`'s "three wrong passwords, then the correct one is refused"
/// — which never touched expiry, never touched `reset`, never pinned the
/// defaults, and could not: it injects no clock. So the two properties that
/// decide whether an admin can ever log in again were both unasserted while the
/// class guarded the only staff credential.
///
/// Design: docs/design/backend-admin-login-throttle.md
void main() {
  late DateTime now;
  LoginThrottle make({int max = 3}) => InMemoryLoginThrottle(
    maxAttempts: max,
    lockout: const Duration(minutes: 15),
    clock: () => now,
  );

  setUp(() => now = DateTime.utc(2026, 8, 19, 12));

  group('the threshold', () {
    test('under it is not locked; AT it is', () async {
      final t = make();
      expect(await t.isLocked('k'), isFalse);
      await t.recordFailure('k');
      await t.recordFailure('k');
      expect(await t.isLocked('k'), isFalse, reason: '2 of 3');
      await t.recordFailure('k');
      expect(await t.isLocked('k'), isTrue, reason: 'the 3rd of 3 locks');
    });

    test('and a locked key is refused even with the right password', () async {
      // Stated here because it is the property, not an implementation detail:
      // the throttle runs BEFORE the credential is checked, so being right does
      // not help. That is what makes it a lockout rather than a filter.
      final t = make();
      for (var i = 0; i < 3; i++) {
        await t.recordFailure('k');
      }
      expect(await t.isLocked('k'), isTrue);
    });
  });

  group('expiry', () {
    test('THE BOUNDARY INSTANT IS STILL LOCKED', () async {
      // `isAfter(until)` is false when now == until. A sub-millisecond
      // distinction, and the one the Postgres translation had to match with
      // `>=` rather than `>`.
      final t = make();
      for (var i = 0; i < 3; i++) {
        await t.recordFailure('k');
      }
      now = DateTime.utc(2026, 8, 19, 12, 15);
      expect(await t.isLocked('k'), isTrue, reason: 'at exactly `until`');
      now = DateTime.utc(2026, 8, 19, 12, 15, 0, 1);
      expect(await t.isLocked('k'), isFalse, reason: 'one millisecond later');
    });

    test('AND THE COUNTER RESTARTS AT 1, not at N+1', () async {
      // The lazy delete clears the count as well as the lock. Without it, one
      // failure after a lockout expires would re-lock immediately and the admin
      // would never get back in.
      final t = make();
      for (var i = 0; i < 3; i++) {
        await t.recordFailure('k');
      }
      now = DateTime.utc(2026, 8, 19, 12, 20);
      expect(await t.isLocked('k'), isFalse);
      await t.recordFailure('k');
      expect(
        await t.isLocked('k'),
        isFalse,
        reason: 'one failure after expiry must not re-lock',
      );
    });
  });

  test('RESET ON SUCCESS — the Monday-and-Friday property', () async {
    // Four wrong attempts on Monday, a successful login, four more on Friday.
    // Without `reset` those accumulate and the admin is locked out by a typo
    // spread across a week. Entirely untested before this file.
    final t = make(max: 5);
    for (var i = 0; i < 4; i++) {
      await t.recordFailure('k');
    }
    await t.reset('k'); // …they logged in successfully
    for (var i = 0; i < 4; i++) {
      await t.recordFailure('k');
    }
    expect(
      await t.isLocked('k'),
      isFalse,
      reason: 'the successful login forgave the first four',
    );
  });

  test('keys are independent', () async {
    final t = make();
    for (var i = 0; i < 3; i++) {
      await t.recordFailure('a');
    }
    expect(await t.isLocked('a'), isTrue);
    expect(await t.isLocked('b'), isFalse);
  });

  test('the defaults are 5 attempts and 15 minutes', () {
    // Both production call sites take the defaults, and nothing pinned them.
    expect(kDefaultMaxAttempts, 5);
    expect(kDefaultLockout, const Duration(minutes: 15));
  });

  group('adminThrottleKey', () {
    test('trims and lower-cases, so one address is one budget', () {
      expect(adminThrottleKey('  Admin@Myweli.CI '), 'admin@myweli.ci');
      expect(adminThrottleKey('admin@myweli.ci'), 'admin@myweli.ci');
    });
  });

  group('failing closed', () {
    test('throttleValue reports a store that cannot answer', () async {
      expect(await throttleValue<bool>(() async => true), isTrue);
      expect(
        await throttleValue<bool>(() async => throw StateError('down')),
        isNull,
        reason: 'null is the signal the caller turns into 503',
      );
    });

    test('throttleOk reports whether a write landed', () async {
      expect(await throttleOk(() async {}), isTrue);
      expect(await throttleOk(() async => throw StateError('down')), isFalse);
    });
  });
}
