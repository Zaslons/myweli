import 'dart:io';

import 'package:myweli_backend/src/auth/auth_repository.dart'
    show RefreshOutcome, RefreshResult, TokenPair, kRefreshReuseGrace;
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

  /// Moves a token's rotation [ago] into the past on the DATABASE clock — the
  /// one the grace is measured on — or, with null, clears it as a row rotated
  /// before migration 0037 has it.
  Future<void> rotatedAgo(String token, Duration? ago) => pool.execute(
    Sql.named(
      ago == null
          ? 'UPDATE admin_refresh_tokens SET rotated_at = NULL '
                'WHERE token_hash = @h'
          : 'UPDATE admin_refresh_tokens SET rotated_at = now() - '
                '@ago:interval WHERE token_hash = @h',
    ),
    parameters: {'h': tokens.hashToken(token), 'ago': ?ago},
  );

  /// The token's row, or null once it is gone.
  Future<Map<String, dynamic>?> tokenRow(String token) async {
    final r = await pool.execute(
      Sql.named(
        'SELECT family_id, rotated, rotated_at FROM admin_refresh_tokens '
        'WHERE token_hash = @h',
      ),
      parameters: {'h': tokens.hashToken(token)},
    );
    return r.isEmpty ? null : r.first.toColumnMap();
  }

  Future<int> familySize(String familyId) async {
    final r = await pool.execute(
      Sql.named(
        'SELECT count(*)::int AS n FROM admin_refresh_tokens '
        'WHERE family_id = @f',
      ),
      parameters: {'f': familyId},
    );
    return r.first.toColumnMap()['n'] as int;
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

  /// **`changePassword` against a real database.**
  ///
  /// Until now the only coverage was an in-memory double, so the production
  /// claim — "every refresh token for the admin is revoked in the SAME
  /// transaction as the hash update" — was asserted against code that is not
  /// the code that runs. The in-memory version revokes with
  /// `_refreshByHash.removeWhere`; the real one issues
  /// `DELETE FROM admin_refresh_tokens WHERE admin_id = @i` inside `runTx`, and
  /// nothing had ever executed that statement.
  group('changePassword, against Postgres', () {
    Future<int> refreshRows(String adminId) async {
      final r = await pool.execute(
        Sql.named(
          'SELECT count(*) FROM admin_refresh_tokens WHERE admin_id = @i',
        ),
        parameters: {'i': adminId},
      );
      return (r.first.toColumnMap()['count'] as int?) ?? 0;
    }

    Future<String> adminIdOf(String email) async {
      final r = await pool.execute(
        Sql.named('SELECT id FROM admins WHERE email = @e'),
        parameters: {'e': email},
      );
      return r.first.toColumnMap()['id'] as String;
    }

    test('the new password logs in and THE OLD ONE DOES NOT', () async {
      final e = freshEmail();
      addTearDown(() => purge(e));
      final r = repo();
      await r.ensureSeedAdmin(email: e, password: 'old-password-1');
      final id = await adminIdOf(e);

      final res = await r.changePassword(
        adminId: id,
        currentPassword: 'old-password-1',
        newPassword: 'new-password-12',
      );
      expect(res.ok, isTrue, reason: res.error);

      expect((await r.login(e, 'new-password-12')).ok, isTrue);
      expect(
        (await r.login(e, 'old-password-1')).ok,
        isFalse,
        reason: 'the hash was not actually written to the admins row',
      );
    });

    test(
      'EVERY REFRESH ROW IS GONE — the production claim, on real rows',
      () async {
        final e = freshEmail();
        addTearDown(() => purge(e));
        final r = repo();
        await r.ensureSeedAdmin(email: e, password: 'old-password-1');
        final id = await adminIdOf(e);

        // Three sessions, so a partial delete is distinguishable from a full one.
        for (var i = 0; i < 3; i++) {
          expect((await r.login(e, 'old-password-1')).ok, isTrue);
        }
        expect(
          await refreshRows(id),
          greaterThanOrEqualTo(3),
          reason: 'control: the rows exist before the change',
        );

        final tok = (await r.login(e, 'old-password-1')).tokens!.refreshToken;
        await r.changePassword(
          adminId: id,
          currentPassword: 'old-password-1',
          newPassword: 'new-password-12',
        );

        expect(await refreshRows(id), 0);
        expect(
          (await r.refresh(tok)).ok,
          isFalse,
          reason: 'a leaked refresh token must die with the rotation',
        );
      },
    );

    test('a wrong current password changes nothing and COUNTS', () async {
      final e = freshEmail();
      addTearDown(() => purge(e));
      final r = repo();
      await r.ensureSeedAdmin(email: e, password: 'old-password-1');
      final id = await adminIdOf(e);

      final res = await r.changePassword(
        adminId: id,
        currentPassword: 'not-the-password',
        newPassword: 'new-password-12',
      );
      expect(res.ok, isFalse);
      expect(res.error, 'invalid_credentials');
      expect(
        await failCount(e),
        1,
        reason: 'an uncounted wrong guess is a repeatable free guess',
      );
      expect(
        (await r.login(e, 'old-password-1')).ok,
        isTrue,
        reason: 'the stored hash must be untouched after a refused change',
      );
    });

    test('a short or unchanged password is refused, and only AFTER the '
        'current one verifies', () async {
      final e = freshEmail();
      addTearDown(() => purge(e));
      final r = repo();
      await r.ensureSeedAdmin(email: e, password: 'old-password-1');
      final id = await adminIdOf(e);

      expect(
        (await r.changePassword(
          adminId: id,
          currentPassword: 'old-password-1',
          newPassword: 'short',
        )).error,
        'weak_password',
      );
      expect(
        (await r.changePassword(
          adminId: id,
          currentPassword: 'old-password-1',
          newPassword: 'old-password-1',
        )).error,
        'password_unchanged',
      );
      // Neither refusal counted against the throttle: the caller proved they
      // hold the password, so these are policy refusals, not failed guesses.
      expect(await failCount(e), isNull);
    });

    test(
      'an unknown admin id is refused without touching the throttle',
      () async {
        final r = repo();
        final res = await r.changePassword(
          adminId: 'admin_does_not_exist',
          currentPassword: 'whatever-goes-here',
          newPassword: 'new-password-12',
        );
        expect(res.ok, isFalse);
        expect(res.error, 'not_found');
      },
    );
  });

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

    // Past the 30 s grace — inside it a replay gets a sibling (the
    // `refresh exchange` group below).
    await rotatedAgo(
      first.refreshToken,
      kRefreshReuseGrace + const Duration(seconds: 1),
    );
    final replay = await r.refresh(first.refreshToken);
    expect(replay.ok, isFalse, reason: 'the used token cannot be replayed');
    final afterRevoke = await r.refresh(second.tokens!.refreshToken);
    expect(
      afterRevoke.ok,
      isFalse,
      reason: 'reuse revokes the whole FAMILY, not just the replayed token',
    );
  });

  /// The atomic exchange with the 30 s grace on `admin_refresh_tokens`
  /// (docs/design/backend-refresh-rotation-atomic.md §8) — the consumer and
  /// provider tables are pinned the same way in postgres_repositories_test.dart.
  group('refresh exchange — atomic, 30 s grace, one transaction', () {
    // A second pool, so eight exchanges can hold eight connections AT ONCE.
    late Pool<void> pool2;
    setUpAll(() => pool2 = createPool(url));
    tearDownAll(() => pool2.close());

    // Holds a child INSERT into one family until the test lets go: a BEFORE
    // INSERT trigger, scoped to that family, that must take an advisory lock
    // the test holds. Keys are this file's own (postgres_repositories_test.dart
    // uses another range), so a concurrently running file never waits on one.
    const kHoldClass = 0x4D57;
    var nextHoldKey = 2000;
    Future<int> holdChildInserts(String family) async {
      final key = nextHoldKey++;
      await pool.execute(
        r'CREATE OR REPLACE FUNCTION mw_test_hold_admin_child() '
        r'RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN '
        r'PERFORM pg_advisory_xact_lock(TG_ARGV[0]::int, TG_ARGV[1]::int); '
        r'RETURN NEW; END $$',
      );
      Future<void> drop() => pool.execute(
        'DROP TRIGGER IF EXISTS mw_test_hold_admin_child '
        'ON admin_refresh_tokens',
      );
      addTearDown(drop);
      await pool.execute(
        'CREATE TRIGGER mw_test_hold_admin_child BEFORE INSERT '
        'ON admin_refresh_tokens FOR EACH ROW '
        "WHEN (NEW.family_id = '$family') "
        "EXECUTE FUNCTION mw_test_hold_admin_child('$kHoldClass', '$key')",
      );
      return key;
    }

    Future<bool> childInsertWaiting(int key) async {
      final r = await pool.execute(
        'SELECT count(*)::int AS n FROM pg_locks '
        "WHERE locktype = 'advisory' AND NOT granted "
        'AND classid = $kHoldClass AND objid = $key AND objsubid = 2',
      );
      return r.first.toColumnMap()['n'] == 1;
    }

    Future<bool> familyDeleteWaiting() async {
      final r = await pool.execute(
        'SELECT count(*)::int AS n FROM pg_stat_activity '
        "WHERE wait_event_type = 'Lock' "
        "AND query LIKE 'DELETE FROM admin_refresh_tokens WHERE family_id%'",
      );
      return r.first.toColumnMap()['n'] == 1;
    }

    /// Polls [probe] until true — bounded, so a setup that never reaches the
    /// interleaving fails loudly instead of hanging or passing.
    Future<void> until(Future<bool> Function() probe, String what) async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!await probe()) {
        if (DateTime.now().isAfter(deadline)) fail('never reached: $what');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    /// A fresh admin, logged in. The admin's id comes back too, for the
    /// fault-injection triggers below.
    Future<({TokenPair first, String adminId})> loggedIn() async {
      final e = freshEmail();
      addTearDown(() => purge(e));
      final r = repo();
      await r.ensureSeedAdmin(email: e, password: 'pw12345');
      final first = (await r.login(e, 'pw12345')).tokens!;
      final payload = tokens.verifyAccessToken(first.accessToken)!.payload;
      return (first: first, adminId: (payload as Map)['sub'] as String);
    }

    test(
      'N = 8 concurrent exchanges of one token → all ok, EXACTLY ONE '
      'rotated, seven grace siblings, all in its family (repeated)',
      () async {
        for (var round = 0; round < 6; round++) {
          final first = (await loggedIn()).first;
          final family = (await tokenRow(first.refreshToken))!['family_id'];
          final results = await Future.wait([
            for (var i = 0; i < 8; i++)
              PostgresAdminAuthRepository(
                i.isEven ? pool : pool2,
                tokens: tokens,
                throttle: InMemoryLoginThrottle(),
              ).refresh(first.refreshToken),
          ]);
          expect(
            results.map((r) => r.ok),
            everyElement(isTrue),
            reason: 'round $round',
          );
          expect(
            results.where((r) => r.outcome == RefreshOutcome.rotated),
            hasLength(1),
            reason: 'round $round: the claim is atomic — exactly one winner',
          );
          expect(
            results.where((r) => r.outcome == RefreshOutcome.grace),
            hasLength(7),
            reason: 'round $round',
          );
          for (final r in results) {
            expect(
              (await tokenRow(r.tokens!.refreshToken))!['family_id'],
              family,
              reason: 'round $round: no fork — every child is in the family',
            );
          }
          expect(await familySize(family as String), 9, reason: 'round $round');
          final parent = (await tokenRow(first.refreshToken))!;
          expect(parent['rotated'], isTrue);
          expect(parent['rotated_at'], isNotNull);
        }
      },
    );

    test('rotated 29 s ago → GRACE, family intact; 31 s ago → refresh_reused '
        'and the family is gone', () async {
      final r = repo();
      final first = (await loggedIn()).first;
      final child = await r.refresh(first.refreshToken);
      expect(child.outcome, RefreshOutcome.rotated);
      final family =
          (await tokenRow(first.refreshToken))!['family_id'] as String;

      await rotatedAgo(first.refreshToken, const Duration(seconds: 29));
      final rotatedAt = (await tokenRow(first.refreshToken))!['rotated_at'];
      expect(rotatedAt, isNotNull);
      final sibling = await r.refresh(first.refreshToken);
      expect(sibling.outcome, RefreshOutcome.grace);
      expect(sibling.ok, isTrue);
      expect(
        (await tokenRow(sibling.tokens!.refreshToken))!['family_id'],
        family,
      );
      expect(await familySize(family), 3, reason: 'nothing revoked');
      // The grace runs from the FIRST rotation. A grace exchange that moved
      // `rotated_at` would let a replay every 29 s keep it open forever, and
      // reuse would never be detected. The 31 s step below backdates the row
      // itself, so it cannot see this; only this read can.
      expect(
        (await tokenRow(first.refreshToken))!['rotated_at'],
        rotatedAt,
        reason: 'a grace exchange must not move the parent\'s rotated_at',
      );

      await rotatedAgo(first.refreshToken, const Duration(seconds: 31));
      final reuse = await r.refresh(first.refreshToken);
      expect(reuse.outcome, RefreshOutcome.reused);
      expect(reuse.error, 'refresh_reused');
      expect(reuse.tokens, isNull);
      expect(await familySize(family), 0, reason: 'family revoked');
      for (final dead in [child, sibling]) {
        final x = await r.refresh(dead.tokens!.refreshToken);
        expect(x.outcome, RefreshOutcome.invalid);
        expect(x.error, 'refresh_invalid');
      }
    });

    test(
      'rotated before migration 0037 (rotated_at NULL) → refresh_reused',
      () async {
        final r = repo();
        final first = (await loggedIn()).first;
        final child = await r.refresh(first.refreshToken);
        await rotatedAgo(first.refreshToken, null);
        final reuse = await r.refresh(first.refreshToken);
        expect(reuse.outcome, RefreshOutcome.reused);
        expect(reuse.error, 'refresh_reused');
        expect(
          (await r.refresh(child.tokens!.refreshToken)).error,
          'refresh_invalid',
        );
      },
    );

    test('a grace exchange that arrives while a family revoke already holds '
        'the rows WAITS for it and mints nothing (FOR UPDATE)', () async {
      final first = (await loggedIn()).first;
      await repo().refresh(first.refreshToken); // rotated: now in grace
      final family =
          (await tokenRow(first.refreshToken))!['family_id'] as String;

      late Future<RefreshResult> racing;
      await pool.runTx((tx) async {
        await tx.execute(
          Sql.named('DELETE FROM admin_refresh_tokens WHERE family_id = @f'),
          parameters: {'f': family},
        );
        // The revoke holds the family's rows, uncommitted. The exchange starts
        // now, on another connection, and must wait for it.
        racing = PostgresAdminAuthRepository(
          pool2,
          tokens: tokens,
          throttle: InMemoryLoginThrottle(),
        ).refresh(first.refreshToken);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      final r = await racing;
      expect(r.outcome, RefreshOutcome.invalid);
      expect(await familySize(family), 0);
    });

    // The other order: the exchange locked its row FIRST and is inserting its
    // child when the revoke arrives. The revoke's DELETE waits on that row, and
    // its snapshot predates the child — so ONE DELETE left the child alive,
    // unrotated, in a family whose reuse caller was told refresh_reused. The
    // revoke now repeats until it deletes nothing. Ordered with an advisory
    // lock the child insert must take (a trigger scoped to this family), not
    // with sleeps.
    for (final grace in [true, false]) {
      final what = grace
          ? 'a grace sibling'
          : 'the child of a plain rotation of the newest token';
      test('$what, minted while a family revoke waits on its row, is deleted '
          'by that revoke too (the DELETE repeats)', () async {
        final r = repo();
        final t0 = (await loggedIn()).first;
        final t1 = (await r.refresh(t0.refreshToken)).tokens!;
        final newest = (await r.refresh(t1.refreshToken)).tokens!;
        final family =
            (await tokenRow(t0.refreshToken))!['family_id'] as String;
        // t0 past the grace: presenting it is reuse. t1 was rotated just now,
        // so it is in the grace; the newest is unrotated.
        await rotatedAgo(t0.refreshToken, const Duration(minutes: 1));
        final key = await holdChildInserts(family);
        final other = PostgresAdminAuthRepository(
          pool2,
          tokens: tokens,
          throttle: InMemoryLoginThrottle(),
        );

        late Future<RefreshResult> minting;
        late Future<RefreshResult> revoking;
        await pool.runTx((hold) async {
          await hold.execute('SELECT pg_advisory_xact_lock($kHoldClass, $key)');
          minting = other.refresh(
            grace ? t1.refreshToken : newest.refreshToken,
          );
          await until(
            () => childInsertWaiting(key),
            'the exchange holds its row and waits to insert its child',
          );
          revoking = other.refresh(t0.refreshToken);
          await until(
            familyDeleteWaiting,
            'the revoke DELETE waits on the row the exchange holds',
          );
        }); // the hold ends: the child commits, then the DELETE resumes

        final m = await minting;
        expect(
          m.outcome,
          grace ? RefreshOutcome.grace : RefreshOutcome.rotated,
        );
        final x = await revoking;
        expect(x.outcome, RefreshOutcome.reused);
        expect(x.error, 'refresh_reused');
        expect(
          await familySize(family),
          0,
          reason:
              'the child committed while the revoke waited is revoked '
              'with the rest of its family',
        );
        expect(
          (await r.refresh(m.tokens!.refreshToken)).outcome,
          RefreshOutcome.invalid,
        );
      });
    }

    test('an unknown token → refresh_invalid', () async {
      final x = await repo().refresh('never-issued');
      expect(x.outcome, RefreshOutcome.invalid);
      expect(x.error, 'refresh_invalid');
      expect(x.tokens, isNull);
    });

    // **The exchange is ONE transaction**, proved from both directions by
    // fault injection scoped to one admin id (so nothing else in the database
    // can trip it). This was three independent statements: a failure between
    // the UPDATE and the INSERT left the token rotated with no child.

    test('a child insert that FAILS rolls the claim back: the token is still '
        'unrotated, and the retry is a clean rotation', () async {
      final r = repo();
      final (:first, :adminId) = await loggedIn();
      await pool.execute(
        r'CREATE OR REPLACE FUNCTION mw_test_refuse_admin_child() '
        r'RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN '
        r"RAISE EXCEPTION 'test: child insert refused'; END $$",
      );
      Future<void> drop() => pool.execute(
        'DROP TRIGGER IF EXISTS mw_test_refuse_admin_child '
        'ON admin_refresh_tokens',
      );
      addTearDown(drop);
      await pool.execute(
        'CREATE TRIGGER mw_test_refuse_admin_child BEFORE INSERT '
        'ON admin_refresh_tokens FOR EACH ROW '
        "WHEN (NEW.admin_id = '$adminId') "
        'EXECUTE FUNCTION mw_test_refuse_admin_child()',
      );

      await expectLater(r.refresh(first.refreshToken), throwsA(anything));
      await drop();

      final row = (await tokenRow(first.refreshToken))!;
      expect(row['rotated'], isFalse, reason: 'the claim rolled back with it');
      expect(row['rotated_at'], isNull);
      expect(
        (await r.refresh(first.refreshToken)).outcome,
        RefreshOutcome.rotated,
        reason: 'not a grace sibling, not a revocation — a clean retry',
      );
    });

    test('a claim that fails at COMMIT leaves no child behind: the child '
        'insert is inside the same transaction', () async {
      final r = repo();
      final (:first, :adminId) = await loggedIn();
      final family =
          (await tokenRow(first.refreshToken))!['family_id'] as String;
      await pool.execute(
        r'CREATE OR REPLACE FUNCTION mw_test_refuse_admin_commit() '
        r'RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN '
        r"RAISE EXCEPTION 'test: commit refused'; END $$",
      );
      Future<void> drop() => pool.execute(
        'DROP TRIGGER IF EXISTS mw_test_refuse_admin_commit '
        'ON admin_refresh_tokens',
      );
      addTearDown(drop);
      // Deferred: fires at COMMIT, after the child insert has run.
      await pool.execute(
        'CREATE CONSTRAINT TRIGGER mw_test_refuse_admin_commit AFTER UPDATE '
        'ON admin_refresh_tokens DEFERRABLE INITIALLY DEFERRED FOR EACH ROW '
        "WHEN (NEW.admin_id = '$adminId') "
        'EXECUTE FUNCTION mw_test_refuse_admin_commit()',
      );

      await expectLater(r.refresh(first.refreshToken), throwsA(anything));
      await drop();

      expect(
        await familySize(family),
        1,
        reason:
            'the parent alone — a child written outside the transaction '
            'would have survived its rollback',
      );
      expect((await tokenRow(first.refreshToken))!['rotated'], isFalse);
    });
  });
}
