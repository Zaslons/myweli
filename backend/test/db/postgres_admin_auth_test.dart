import 'dart:io';

import 'package:myweli_backend/src/auth/login_throttle.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_admin_auth_repository.dart';
import 'package:myweli_backend/src/db/postgres_login_throttle.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// `PostgresAdminAuthRepository` — which had **no integration coverage of any
/// kind** before this file.
///
/// Its login, its two-branch failure path, its throttle interaction and its
/// refresh rotation were all untested against a real database, on the
/// repository that guards the credential `admin/_middleware.dart` calls "the
/// only thing standing between the team and everyone's data."
///
/// Design: docs/design/backend-admin-login-throttle.md
void main() {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    test(
      'postgres admin auth (skipped — set DATABASE_URL to run)',
      () {},
      skip: 'requires DATABASE_URL',
    );
    return;
  }

  late Pool<void> pool;
  final tokens = TokenService(secret: 'test-secret');
  var seq = 0;
  var now = DateTime.utc(2026, 8, 19, 12);

  setUpAll(() async {
    pool = createPool(url);
    await withSchemaLock(pool, () => runMigrations(pool));
  });

  tearDownAll(() async => pool.close());

  setUp(() => now = DateTime.utc(2026, 8, 19, 12));

  /// A fresh address per test, so the suite is re-runnable against the same
  /// database without a reset.
  String freshEmail() =>
      'admin-${DateTime.now().microsecondsSinceEpoch}-${seq++}@myweli.test';

  PostgresAdminAuthRepository repo({int max = 3}) =>
      PostgresAdminAuthRepository(
        pool,
        tokens: tokens,
        throttle: PostgresLoginThrottle(
          pool,
          maxAttempts: max,
          lockout: const Duration(minutes: 15),
          clock: () => now,
        ),
      );

  Future<void> purge(String email) async {
    await pool.execute(
      Sql.named('DELETE FROM admin_login_throttle WHERE key_hash = @k:text'),
      parameters: {'k': PostgresLoginThrottle.hashKey(adminThrottleKey(email))},
    );
  }

  Future<int?> failCount(String email) async {
    final r = await pool.execute(
      Sql.named(
        'SELECT fail_count FROM admin_login_throttle WHERE key_hash = @k:text',
      ),
      parameters: {'k': PostgresLoginThrottle.hashKey(adminThrottleKey(email))},
    );
    return r.isEmpty ? null : r.first.toColumnMap()['fail_count'] as int;
  }

  test('a correct password mints an admin token', () async {
    final e = freshEmail();
    addTearDown(() => purge(e));
    final r = repo();
    await r.ensureSeedAdmin(email: e, password: 'pw12345');
    final ok = await r.login(e, 'pw12345');
    expect(ok.ok, isTrue);
    expect(ok.tokens, isNotNull);
    final claims = tokens.verifyAccessToken(ok.tokens!.accessToken);
    expect((claims?.payload as Map?)?['role'], 'admin');
  });

  test('the email is trimmed and case-insensitive', () async {
    final e = freshEmail();
    addTearDown(() => purge(e));
    final r = repo();
    await r.ensureSeedAdmin(email: e, password: 'pw12345');
    expect((await r.login('  ${e.toUpperCase()} ', 'pw12345')).ok, isTrue);
  });

  group('the two-branch failure path', () {
    test('AN UNKNOWN ADDRESS IS COUNTED — the enumeration property', () async {
      // The property that forces the open key set, and the one most likely to
      // be "optimised" away by someone who sees rows for addresses that are not
      // admins. Stop counting unknowns and `locked_out` appears only for real
      // admin addresses, which turns this endpoint into an oracle for them.
      final e = freshEmail();
      addTearDown(() => purge(e));
      final r = await repo().login(e, 'anything');
      expect(r.error, 'invalid_credentials');
      expect(
        await failCount(e),
        1,
        reason: 'an address that is not an admin still consumes budget',
      );
    });

    test('a known address with a wrong password is counted too', () async {
      final e = freshEmail();
      addTearDown(() => purge(e));
      final r = repo();
      await r.ensureSeedAdmin(email: e, password: 'pw12345');
      expect((await r.login(e, 'wrong')).error, 'invalid_credentials');
      expect(await failCount(e), 1);
    });

    test(
      'a DISABLED admin with the CORRECT password is refused, and counted',
      () async {
        // Half of a compound condition that nothing exercised. A suspended admin
        // holding the right password must be indistinguishable from a wrong one,
        // and must not get free attempts either.
        final e = freshEmail();
        addTearDown(() => purge(e));
        final r = repo();
        await r.ensureSeedAdmin(email: e, password: 'pw12345');
        await pool.execute(
          Sql.named(
            "UPDATE admins SET status = 'disabled' WHERE email = @e:text",
          ),
          parameters: {'e': adminThrottleKey(e)},
        );
        final out = await r.login(e, 'pw12345');
        expect(out.error, 'invalid_credentials');
        expect(await failCount(e), 1);
      },
    );
  });

  test('lockout end to end, then release after the window', () async {
    final e = freshEmail();
    addTearDown(() => purge(e));
    final r = repo();
    await r.ensureSeedAdmin(email: e, password: 'pw12345');
    for (var i = 0; i < 3; i++) {
      expect((await r.login(e, 'wrong')).error, 'invalid_credentials');
    }
    expect(
      (await r.login(e, 'pw12345')).error,
      'locked_out',
      reason: 'the CORRECT password is refused while locked',
    );
    now = DateTime.utc(2026, 8, 19, 12, 20);
    expect(
      (await r.login(e, 'pw12345')).ok,
      isTrue,
      reason: 'the window passed',
    );
  });

  test('THE LOCK DOES NOT EXTEND while it is held', () async {
    // Both call sites return at `isLocked` before recording, so attempts made
    // during a lockout do not push the expiry forward. Without that a
    // determined attacker turns a 15-minute penalty into a permanent one — and
    // so does an admin retrying in a panic.
    final e = freshEmail();
    addTearDown(() => purge(e));
    final r = repo();
    await r.ensureSeedAdmin(email: e, password: 'pw12345');
    for (var i = 0; i < 3; i++) {
      await r.login(e, 'wrong');
    }
    now = DateTime.utc(2026, 8, 19, 12, 5);
    for (var i = 0; i < 3; i++) {
      expect((await r.login(e, 'wrong')).error, 'locked_out');
    }
    now = DateTime.utc(2026, 8, 19, 12, 15, 0, 1);
    expect(
      (await r.login(e, 'pw12345')).ok,
      isTrue,
      reason: 'released 15 minutes after the TRIGGERING failure, not the last',
    );
  });

  test('a successful login forgives the earlier failures', () async {
    final e = freshEmail();
    addTearDown(() => purge(e));
    final r = repo();
    await r.ensureSeedAdmin(email: e, password: 'pw12345');
    await r.login(e, 'wrong');
    await r.login(e, 'wrong');
    expect((await r.login(e, 'pw12345')).ok, isTrue);
    expect(await failCount(e), isNull, reason: 'the row is gone');
    // …and the budget really is full again.
    await r.login(e, 'wrong');
    await r.login(e, 'wrong');
    expect((await r.login(e, 'pw12345')).ok, isTrue);
  });

  test('two admins have independent budgets', () async {
    final a = freshEmail();
    final b = freshEmail();
    addTearDown(() => purge(a));
    addTearDown(() => purge(b));
    final r = repo();
    await r.ensureSeedAdmin(email: a, password: 'pw12345');
    await r.ensureSeedAdmin(email: b, password: 'pw12345');
    for (var i = 0; i < 3; i++) {
      await r.login(a, 'wrong');
    }
    expect((await r.login(a, 'pw12345')).error, 'locked_out');
    expect((await r.login(b, 'pw12345')).ok, isTrue);
  });

  test(
    'ensureSeedAdmin is idempotent and does not overwrite the hash',
    () async {
      final e = freshEmail();
      addTearDown(() => purge(e));
      final r = repo();
      await r.ensureSeedAdmin(email: e, password: 'pw12345');
      await r.ensureSeedAdmin(email: e, password: 'different');
      expect(
        (await r.login(e, 'pw12345')).ok,
        isTrue,
        reason: 'the original password still works',
      );
    },
  );

  test('refresh rotates, and reuse revokes the family', () async {
    final e = freshEmail();
    addTearDown(() => purge(e));
    final r = repo();
    await r.ensureSeedAdmin(email: e, password: 'pw12345');
    final first = (await r.login(e, 'pw12345')).tokens!;
    final second = await r.refresh(first.refreshToken);
    expect(second.ok, isTrue);

    final replay = await r.refresh(first.refreshToken);
    expect(replay.ok, isFalse, reason: 'the used token cannot be replayed');
    final afterRevoke = await r.refresh(second.tokens!.refreshToken);
    expect(
      afterRevoke.ok,
      isFalse,
      reason: 'reuse revokes the whole FAMILY, not just the replayed token',
    );
  });
}
