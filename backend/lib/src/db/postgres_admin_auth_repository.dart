import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:postgres/postgres.dart';

import '../admin/admin_auth_repository.dart';
import '../auth/auth_repository.dart' show RefreshResult, TokenPair;
import '../auth/login_throttle.dart';
import '../auth/tokens.dart';

/// Postgres-backed admin auth. Mirrors the provider refresh design: opaque
/// refresh tokens hashed at rest, rotated on use, family revoked on reuse.
class PostgresAdminAuthRepository implements AdminAuthRepository {
  PostgresAdminAuthRepository(
    this._pool, {
    required TokenService tokens,
    LoginThrottle? throttle,
  }) : _tokens = tokens,
       _throttle = throttle ?? LoginThrottle();

  final Pool<void> _pool;
  final TokenService _tokens;
  final LoginThrottle _throttle;
  final _rng = Random.secure();

  String _id(String prefix) {
    final bytes = List<int>.generate(12, (_) => _rng.nextInt(256));
    return '${prefix}_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  @override
  Future<void> ensureSeedAdmin({
    required String email,
    required String password,
  }) async {
    final e = email.trim().toLowerCase();
    final existing = await _pool.execute(
      Sql.named('SELECT 1 FROM admins WHERE email = @e'),
      parameters: {'e': e},
    );
    if (existing.isNotEmpty) return;
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
    final e = email.trim().toLowerCase();
    if (_throttle.isLocked(e)) {
      return (ok: false, error: 'locked_out', tokens: null);
    }
    final r = await _pool.execute(
      Sql.named(
        'SELECT id, password_hash, status FROM admins WHERE email = @e',
      ),
      parameters: {'e': e},
    );
    if (r.isEmpty) {
      _throttle.recordFailure(e);
      return (ok: false, error: 'invalid_credentials', tokens: null);
    }
    final row = r.first;
    final id = row[0]! as String;
    final hash = row[1]! as String;
    final status = row[2]! as String;
    if (status != 'active' || !BCrypt.checkpw(password, hash)) {
      _throttle.recordFailure(e);
      return (ok: false, error: 'invalid_credentials', tokens: null);
    }
    _throttle.reset(e);
    return (
      ok: true,
      error: null,
      tokens: await _issueInFamily(id, _id('fam')),
    );
  }

  @override
  Future<RefreshResult> refresh(String refreshToken) async {
    final h = _tokens.hashToken(refreshToken);
    final r = await _pool.execute(
      Sql.named(
        'SELECT admin_id, family_id, rotated '
        'FROM admin_refresh_tokens WHERE token_hash = @h',
      ),
      parameters: {'h': h},
    );
    if (r.isEmpty) return (ok: false, error: 'refresh_invalid', tokens: null);
    final row = r.first;
    final adminId = row[0]! as String;
    final familyId = row[1]! as String;
    final rotated = row[2]! as bool;
    if (rotated) {
      await _pool.execute(
        Sql.named('DELETE FROM admin_refresh_tokens WHERE family_id = @f'),
        parameters: {'f': familyId},
      );
      return (ok: false, error: 'refresh_reused', tokens: null);
    }
    await _pool.execute(
      Sql.named(
        'UPDATE admin_refresh_tokens SET rotated = true '
        'WHERE token_hash = @h',
      ),
      parameters: {'h': h},
    );
    return (
      ok: true,
      error: null,
      tokens: await _issueInFamily(adminId, familyId),
    );
  }

  Future<TokenPair> _issueInFamily(String adminId, String familyId) async {
    final access = _tokens.issueAccessToken(subject: adminId, role: 'admin');
    final refresh = _tokens.generateRefreshToken();
    await _pool.execute(
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
