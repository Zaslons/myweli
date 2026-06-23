import 'dart:math';

import 'package:postgres/postgres.dart';

import '../auth/auth_repository.dart';
import '../auth/tokens.dart';

/// Postgres-backed [AuthRepository]. Same security logic as
/// [InMemoryAuthRepository] (OTP hashed + attempt/resend budgets; refresh
/// hashed, rotated, reuse → family revoke) expressed in SQL. All queries are
/// parameterized; multi-write paths run in a transaction.
class PostgresAuthRepository implements AuthRepository {
  PostgresAuthRepository(
    this._pool, {
    required TokenService tokens,
    required bool isProd,
    Duration otpValidity = const Duration(minutes: 5),
    int maxAttempts = 5,
    int maxResends = 3,
  }) : _tokens = tokens,
       _isProd = isProd,
       _otpValidity = otpValidity,
       _maxAttempts = maxAttempts,
       _maxResends = maxResends;

  final Pool<void> _pool;
  final TokenService _tokens;
  final bool _isProd;
  final Duration _otpValidity;
  final int _maxAttempts;
  final int _maxResends;
  final Random _random = Random.secure();

  @override
  Future<OtpRequestResult> requestOtp(String phoneNumber) async {
    final existing = await _pool.execute(
      Sql.named('SELECT resends_left FROM otp_codes WHERE phone_number = @p'),
      parameters: {'p': phoneNumber},
    );
    final hadExisting = existing.isNotEmpty;
    final prevResends = hadExisting
        ? existing.first.toColumnMap()['resends_left'] as int
        : 0;
    if (hadExisting && prevResends <= 0) {
      return (
        ok: false,
        error: 'otp_resend_limit',
        devCode: null,
        expiresInSeconds: 0,
      );
    }
    final resendsLeft = hadExisting ? prevResends - 1 : _maxResends;
    final code = (100000 + _random.nextInt(900000)).toString();
    await _pool.execute(
      Sql.named(
        'INSERT INTO otp_codes '
        '(phone_number, code_hash, expires_at, attempts_left, resends_left) '
        'VALUES (@p, @h, @e, @a, @r) '
        'ON CONFLICT (phone_number) DO UPDATE SET '
        'code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at, '
        'attempts_left = EXCLUDED.attempts_left, '
        'resends_left = EXCLUDED.resends_left',
      ),
      parameters: {
        'p': phoneNumber,
        'h': _tokens.hashToken(code),
        'e': DateTime.now().toUtc().add(_otpValidity),
        'a': _maxAttempts,
        'r': resendsLeft,
      },
    );
    return (
      ok: true,
      error: null,
      devCode: _isProd ? null : code,
      expiresInSeconds: _otpValidity.inSeconds,
    );
  }

  @override
  Future<OtpVerifyResult> verifyOtp(String phoneNumber, String code) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT code_hash, expires_at, attempts_left '
        'FROM otp_codes WHERE phone_number = @p',
      ),
      parameters: {'p': phoneNumber},
    );
    if (rows.isEmpty) {
      return (ok: false, error: 'otp_none', user: null, tokens: null);
    }
    final row = rows.first.toColumnMap();
    if (DateTime.now().toUtc().isAfter(
      (row['expires_at'] as DateTime).toUtc(),
    )) {
      await _deleteOtp(phoneNumber);
      return (ok: false, error: 'otp_expired', user: null, tokens: null);
    }
    final attemptsLeft = row['attempts_left'] as int;
    if (attemptsLeft <= 0) {
      return (ok: false, error: 'otp_locked', user: null, tokens: null);
    }
    if ((row['code_hash'] as String) != _tokens.hashToken(code)) {
      final left = attemptsLeft - 1;
      await _pool.execute(
        Sql.named(
          'UPDATE otp_codes SET attempts_left = @a WHERE phone_number = @p',
        ),
        parameters: {'a': left, 'p': phoneNumber},
      );
      return (
        ok: false,
        error: left <= 0 ? 'otp_locked' : 'otp_invalid',
        user: null,
        tokens: null,
      );
    }
    return _pool.runTx((tx) async {
      await tx.execute(
        Sql.named('DELETE FROM otp_codes WHERE phone_number = @p'),
        parameters: {'p': phoneNumber},
      );
      final user = await _findOrCreateUser(tx, phoneNumber);
      final tokens = await _issueInFamily(tx, user.id, 'user', _newId('fam'));
      return (ok: true, error: null, user: user, tokens: tokens);
    });
  }

  @override
  Future<RefreshResult> refresh(String refreshToken) async {
    final hash = _tokens.hashToken(refreshToken);
    final rows = await _pool.execute(
      Sql.named(
        'SELECT user_id, role, family_id, rotated '
        'FROM refresh_tokens WHERE token_hash = @h',
      ),
      parameters: {'h': hash},
    );
    if (rows.isEmpty) {
      return (ok: false, error: 'refresh_invalid', tokens: null);
    }
    final row = rows.first.toColumnMap();
    if (row['rotated'] as bool) {
      await _pool.execute(
        Sql.named('DELETE FROM refresh_tokens WHERE family_id = @f'),
        parameters: {'f': row['family_id']},
      );
      return (ok: false, error: 'refresh_reused', tokens: null);
    }
    return _pool.runTx((tx) async {
      await tx.execute(
        Sql.named(
          'UPDATE refresh_tokens SET rotated = true WHERE token_hash = @h',
        ),
        parameters: {'h': hash},
      );
      final tokens = await _issueInFamily(
        tx,
        row['user_id'] as String,
        row['role'] as String,
        row['family_id'] as String,
      );
      return (ok: true, error: null, tokens: tokens);
    });
  }

  @override
  Future<AuthUser?> userById(String id) async {
    final rows = await _pool.execute(
      Sql.named('SELECT * FROM users WHERE id = @id'),
      parameters: {'id': id},
    );
    if (rows.isEmpty) return null;
    return _userFrom(rows.first.toColumnMap());
  }

  @override
  Future<AuthUser?> updateUser(
    String id, {
    String? name,
    String? email,
    String? avatarUrl,
  }) async {
    final existing = await userById(id);
    if (existing == null) return null;
    final rows = await _pool.execute(
      Sql.named(
        'UPDATE users SET name = @n:text, email = @e:text, '
        'avatar_url = @a:text WHERE id = @id RETURNING *',
      ),
      parameters: {
        'n': (name != null && name.isNotEmpty) ? name : existing.name,
        'e': email == null ? existing.email : (email.isEmpty ? null : email),
        'a': avatarUrl ?? existing.avatarUrl,
        'id': id,
      },
    );
    return _userFrom(rows.first.toColumnMap());
  }

  @override
  Future<bool> deleteUser(String id) async {
    final user = await userById(id);
    if (user == null) return false;
    await _deleteOtp(user.phoneNumber);
    final res = await _pool.execute(
      Sql.named('DELETE FROM users WHERE id = @id'),
      parameters: {'id': id},
    );
    return res.affectedRows > 0;
  }

  Future<void> _deleteOtp(String phoneNumber) => _pool.execute(
    Sql.named('DELETE FROM otp_codes WHERE phone_number = @p'),
    parameters: {'p': phoneNumber},
  );

  Future<AuthUser> _findOrCreateUser(
    Session session,
    String phoneNumber,
  ) async {
    final found = await session.execute(
      Sql.named('SELECT * FROM users WHERE phone_number = @p'),
      parameters: {'p': phoneNumber},
    );
    if (found.isNotEmpty) return _userFrom(found.first.toColumnMap());
    final created = await session.execute(
      Sql.named(
        'INSERT INTO users (id, phone_number) VALUES (@id, @p) RETURNING *',
      ),
      parameters: {'id': _newId('user'), 'p': phoneNumber},
    );
    return _userFrom(created.first.toColumnMap());
  }

  Future<TokenPair> _issueInFamily(
    Session session,
    String userId,
    String role,
    String familyId,
  ) async {
    final access = _tokens.issueAccessToken(subject: userId, role: role);
    final refresh = _tokens.generateRefreshToken();
    await session.execute(
      Sql.named(
        'INSERT INTO refresh_tokens (token_hash, user_id, role, family_id) '
        'VALUES (@h, @u, @r, @f)',
      ),
      parameters: {
        'h': _tokens.hashToken(refresh),
        'u': userId,
        'r': role,
        'f': familyId,
      },
    );
    return (
      accessToken: access.token,
      refreshToken: refresh,
      expiresAt: access.expiresAt,
    );
  }

  AuthUser _userFrom(Map<String, dynamic> m) => AuthUser(
    id: m['id'] as String,
    phoneNumber: m['phone_number'] as String,
    createdAt: m['created_at'] as DateTime,
    name: m['name'] as String?,
    email: m['email'] as String?,
    avatarUrl: m['avatar_url'] as String?,
  );

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
}
