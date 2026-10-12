import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:postgres/postgres.dart';

import '../admin/admin_auth_repository.dart';
import '../auth/auth_repository.dart' show RefreshResult, TokenPair;
import '../auth/login_throttle.dart';
import '../auth/tokens.dart';
import 'refresh_exchange.dart';

/// Postgres-backed admin auth. Mirrors the provider refresh design: opaque
/// refresh tokens hashed at rest, rotated atomically on use, family revoked on
/// reuse past the 30 s grace (docs/design/backend-refresh-rotation-atomic.md).
class PostgresAdminAuthRepository implements AdminAuthRepository {
  PostgresAdminAuthRepository(
    this._pool, {
    required TokenService tokens,
    required LoginThrottle throttle,
  }) : _tokens = tokens,
       _throttle = throttle;

  final Pool<void> _pool;
  final TokenService _tokens;
  final LoginThrottle _throttle;
  final _rng = Random.secure();

  String _id(String prefix) {
    final bytes = List<int>.generate(12, (_) => _rng.nextInt(256));
    return '${prefix}_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  @override
  Future<bool> ensureSeedAdmin({
    required String email,
    required String password,
  }) async {
    final e = email.trim().toLowerCase();
    final existing = await _pool.execute(
      Sql.named('SELECT 1 FROM admins WHERE email = @e'),
      parameters: {'e': e},
    );
    if (existing.isNotEmpty) return false;
    await _pool.execute(
      Sql.named(
        'INSERT INTO admins (id, email, password_hash) '
        'VALUES (@id, @e, @h)',
      ),
      parameters: {
        'id': _id('admin'),
        'e': e,
        'h': BCrypt.hashpw(password, BCrypt.gensalt()),
      },
    );
    return true;
  }

  @override
  Future<AdminAccount?> adminById(String id) async {
    final r = await _pool.execute(
      Sql.named('SELECT id, email, status FROM admins WHERE id = @id'),
      parameters: {'id': id},
    );
    if (r.isEmpty) return null;
    final row = r.first;
    return AdminAccount(
      id: row[0]! as String,
      email: row[1]! as String,
      status: row[2]! as String,
    );
  }

  @override
  Future<AdminLoginResult> login(String email, String password) async {
    final e = adminThrottleKey(email);
    // **Fail closed.** A null means the store could not answer, and it gets a
    // code of its own — not `locked_out`, which would tell an operator at 2am
    // that someone guessed too often when the truth is that Postgres is sick.
    final locked = await throttleValue(() => _throttle.isLocked(e));
    if (locked == null) {
      return (ok: false, error: 'throttle_unavailable', tokens: null);
    }
    if (locked) {
      return (ok: false, error: 'locked_out', tokens: null);
    }
    final r = await _pool.execute(
      Sql.named(
        'SELECT id, password_hash, status FROM admins WHERE email = @e',
      ),
      parameters: {'e': e},
    );
    if (r.isEmpty) {
      // Also fail closed: a failure bcrypt rejected but the store did not
      // COUNT is a repeatable free guess, which is the whole attack.
      if (!await throttleOk(() => _throttle.recordFailure(e))) {
        return (ok: false, error: 'throttle_unavailable', tokens: null);
      }
      return (ok: false, error: 'invalid_credentials', tokens: null);
    }
    final row = r.first;
    final id = row[0]! as String;
    final hash = row[1]! as String;
    final status = row[2]! as String;
    if (status != 'active' || !BCrypt.checkpw(password, hash)) {
      // Also fail closed: a failure bcrypt rejected but the store did not
      // COUNT is a repeatable free guess, which is the whole attack.
      if (!await throttleOk(() => _throttle.recordFailure(e))) {
        return (ok: false, error: 'throttle_unavailable', tokens: null);
      }
      return (ok: false, error: 'invalid_credentials', tokens: null);
    }
    // The one exception: the operations that bound the ATTACKER fail closed;
    // the one that forgives the USER fails open. If this throws the count is
    // simply not cleared — stricter, never looser.
    await throttleOk(() => _throttle.reset(e));
    return (
      ok: true,
      error: null,
      tokens: await _issueInFamily(_pool, id, _id('fam')),
    );
  }

  @override
  Future<AdminPasswordChangeResult> changePassword({
    required String adminId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final r = await _pool.execute(
      Sql.named(
        'SELECT email, password_hash, status FROM admins WHERE id = @i',
      ),
      parameters: {'i': adminId},
    );
    if (r.isEmpty) return (ok: false, error: 'not_found');
    final email = r.first[0]! as String;
    final hash = r.first[1]! as String;
    final status = r.first[2]! as String;

    // Same key as `login`, deliberately: a key of its own would hand a stolen
    // access token a FRESH five-guess budget that login's lockout never sees.
    final e = adminThrottleKey(email);
    // Fail closed, for login's reason — the password and this throttle are the
    // complete control set on the staff credential.
    final locked = await throttleValue(() => _throttle.isLocked(e));
    if (locked == null) return (ok: false, error: 'throttle_unavailable');
    if (locked) return (ok: false, error: 'locked_out');

    if (status != 'active' || !BCrypt.checkpw(currentPassword, hash)) {
      if (!await throttleOk(() => _throttle.recordFailure(e))) {
        return (ok: false, error: 'throttle_unavailable');
      }
      return (ok: false, error: 'invalid_credentials');
    }
    // Checked only AFTER the current password verifies, so an unauthenticated
    // guess learns nothing about the policy from the shape of the refusal.
    if (newPassword.length < kAdminPasswordMinLength) {
      return (ok: false, error: 'weak_password');
    }
    if (BCrypt.checkpw(newPassword, hash)) {
      return (ok: false, error: 'password_unchanged');
    }

    final next = BCrypt.hashpw(newPassword, BCrypt.gensalt());
    // **One transaction, because the halves are not independent.** A crash
    // between them would leave the password changed with every old session
    // still alive — the exact state the rotation exists to end.
    await _pool.runTx((tx) async {
      await tx.execute(
        Sql.named('UPDATE admins SET password_hash = @h WHERE id = @i'),
        parameters: {'h': next, 'i': adminId},
      );
      await tx.execute(
        Sql.named('DELETE FROM admin_refresh_tokens WHERE admin_id = @i'),
        parameters: {'i': adminId},
      );
    });
    // Fails open, like login's: the caller just proved they hold the password,
    // and refusing them over a throttle write would be a self-inflicted outage.
    await throttleOk(() => _throttle.reset(e));
    return (ok: true, error: null);
  }

  /// **One transaction, the child insert inside it.** This used to be three
  /// independent statements, so a failure between the UPDATE and the INSERT
  /// left the token rotated with no child — the session unrecoverable, and the
  /// client's retry then revoked as theft. Atomic claim, 30 s grace on the
  /// database clock, family revoke past it — the consumer/provider exchange.
  /// Design: docs/design/backend-refresh-rotation-atomic.md.
  @override
  Future<RefreshResult> refresh(String refreshToken) {
    final hash = _tokens.hashToken(refreshToken);
    return _pool.runTx(
      (tx) => exchangeRefreshToken(
        tx,
        table: 'admin_refresh_tokens',
        ownerColumns: 'admin_id',
        tokenHash: hash,
        issueChild: (row) => _issueInFamily(
          tx,
          row['admin_id'] as String,
          row['family_id'] as String,
        ),
      ),
    );
  }

  /// Writes through [session]: the pool for a login, the exchange's own
  /// transaction for a refresh.
  Future<TokenPair> _issueInFamily(
    Session session,
    String adminId,
    String familyId,
  ) async {
    final access = _tokens.issueAccessToken(subject: adminId, role: 'admin');
    final refresh = _tokens.generateRefreshToken();
    await session.execute(
      Sql.named(
        'INSERT INTO admin_refresh_tokens (token_hash, admin_id, family_id) '
        'VALUES (@h, @a, @f)',
      ),
      parameters: {
        'h': _tokens.hashToken(refresh),
        'a': adminId,
        'f': familyId,
      },
    );
    return (
      accessToken: access.token,
      refreshToken: refresh,
      expiresAt: access.expiresAt,
    );
  }
}
