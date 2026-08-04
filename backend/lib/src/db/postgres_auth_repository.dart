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
  Future<OtpRequestResult> requestOtp(String phoneNumber) =>
      _requestOtpIn('otp_codes', 'phone_number', phoneNumber);

  @override
  Future<OtpRequestResult> requestEmailOtp(String email) =>
      _requestOtpIn('email_otp_codes', 'email', email.trim().toLowerCase());

  Future<OtpRequestResult> _requestOtpIn(
    String table,
    String keyColumn,
    String key,
  ) async {
    // An expired code (never verified, e.g. the user abandoned the flow)
    // doesn't count against the resend budget — treat it as absent.
    final existing = await _pool.execute(
      Sql.named(
        'SELECT resends_left FROM $table '
        'WHERE $keyColumn = @p AND expires_at > now()',
      ),
      parameters: {'p': key},
    );
    final hadExisting = existing.isNotEmpty;
    final prevResends = hadExisting
        ? existing.first.toColumnMap()['resends_left'] as int
        : 0;
    if (hadExisting && prevResends <= 0) {
      return (
        ok: false,
        error: 'otp_resend_limit',
        code: null,
        devCode: null,
        expiresInSeconds: 0,
      );
    }
    final resendsLeft = hadExisting ? prevResends - 1 : _maxResends;
    final code = (100000 + _random.nextInt(900000)).toString();
    await _pool.execute(
      Sql.named(
        'INSERT INTO $table '
        '($keyColumn, code_hash, expires_at, attempts_left, resends_left) '
        'VALUES (@p, @h, @e, @a, @r) '
        'ON CONFLICT ($keyColumn) DO UPDATE SET '
        'code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at, '
        'attempts_left = EXCLUDED.attempts_left, '
        'resends_left = EXCLUDED.resends_left',
      ),
      parameters: {
        'p': key,
        'h': _tokens.hashToken(code),
        'e': DateTime.now().toUtc().add(_otpValidity),
        'a': _maxAttempts,
        'r': resendsLeft,
      },
    );
    return (
      ok: true,
      error: null,
      code: code,
      devCode: _isProd ? null : code,
      expiresInSeconds: _otpValidity.inSeconds,
    );
  }

  @override
  Future<OtpVerifyResult> verifyOtp(String phoneNumber, String code) async {
    final error = await _checkOtpIn(
      'otp_codes',
      'phone_number',
      phoneNumber,
      code,
    );
    if (error != null) {
      return (ok: false, error: error, user: null, tokens: null);
    }
    return _pool.runTx((tx) async {
      await tx.execute(
        Sql.named('DELETE FROM otp_codes WHERE phone_number = @p'),
        parameters: {'p': phoneNumber},
      );
      final user = await _findOrCreateByPhone(tx, phoneNumber);
      return _loginAs(tx, user);
    });
  }

  @override
  Future<OtpVerifyResult> verifyEmailOtp(String email, String code) async {
    final key = email.trim().toLowerCase();
    final error = await _checkOtpIn('email_otp_codes', 'email', key, code);
    if (error != null) {
      return (ok: false, error: error, user: null, tokens: null);
    }
    return _pool.runTx((tx) async {
      await tx.execute(
        Sql.named('DELETE FROM email_otp_codes WHERE email = @p'),
        parameters: {'p': key},
      );
      // Inbox ownership proven → the email is verified.
      var user = await _userWhere(tx, 'lower(email) = @e', {'e': key});
      if (user == null) {
        final created = await tx.execute(
          Sql.named(
            'INSERT INTO users (id, email, email_verified, auth_provider) '
            "VALUES (@id, @e, true, 'email') RETURNING *",
          ),
          parameters: {'id': _newId('user'), 'e': key},
        );
        user = _userFrom(created.first.toColumnMap());
      } else if (!user.emailVerified) {
        await tx.execute(
          Sql.named('UPDATE users SET email_verified = true WHERE id = @id'),
          parameters: {'id': user.id},
        );
        user.emailVerified = true;
      }
      return _loginAs(tx, user);
    });
  }

  @override
  Future<OtpVerifyResult> loginWithSocial({
    required String provider,
    required String sub,
    String? email,
    bool emailVerified = false,
    String? name,
    String? avatarUrl,
  }) async {
    // Only google/apple carry a dedicated sub column; anything else is a bug.
    final subColumn = switch (provider) {
      'google' => 'google_sub',
      'apple' => 'apple_sub',
      _ => throw ArgumentError.value(provider, 'provider'),
    };
    final emailKey = email?.trim().toLowerCase();
    return _pool.runTx((tx) async {
      var user = await _userWhere(tx, '$subColumn = @s', {'s': sub});
      if (user == null && emailKey != null && emailVerified) {
        // Link rule §4: a verified email joins this provider to the existing
        // account (never on an unverified email — T33).
        user = await _userWhere(tx, 'lower(email) = @e', {'e': emailKey});
        if (user != null) {
          await tx.execute(
            Sql.named(
              'UPDATE users SET $subColumn = @s, email_verified = true, '
              'name = COALESCE(name, @n:text), '
              'avatar_url = COALESCE(avatar_url, @a:text) WHERE id = @id',
            ),
            parameters: {'s': sub, 'n': name, 'a': avatarUrl, 'id': user.id},
          );
          user.emailVerified = true;
          user.name ??= name;
          user.avatarUrl ??= avatarUrl;
        }
      }
      if (user == null) {
        final created = await tx.execute(
          Sql.named(
            'INSERT INTO users '
            '(id, email, email_verified, $subColumn, auth_provider, name, avatar_url) '
            'VALUES (@id, @e:text, @v, @s, @p, @n:text, @a:text) RETURNING *',
          ),
          parameters: {
            'id': _newId('user'),
            'e': emailKey,
            'v': emailVerified && emailKey != null,
            's': sub,
            'p': provider,
            'n': name,
            'a': avatarUrl,
          },
        );
        user = _userFrom(created.first.toColumnMap());
      }
      return _loginAs(tx, user);
    });
  }

  /// Check a code against an OTP table; null means valid (caller consumes it).
  Future<String?> _checkOtpIn(
    String table,
    String keyColumn,
    String key,
    String code,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT code_hash, expires_at, attempts_left '
        'FROM $table WHERE $keyColumn = @p',
      ),
      parameters: {'p': key},
    );
    if (rows.isEmpty) return 'otp_none';
    final row = rows.first.toColumnMap();
    if (DateTime.now().toUtc().isAfter(
      (row['expires_at'] as DateTime).toUtc(),
    )) {
      await _pool.execute(
        Sql.named('DELETE FROM $table WHERE $keyColumn = @p'),
        parameters: {'p': key},
      );
      return 'otp_expired';
    }
    final attemptsLeft = row['attempts_left'] as int;
    if (attemptsLeft <= 0) return 'otp_locked';
    if ((row['code_hash'] as String) != _tokens.hashToken(code)) {
      final left = attemptsLeft - 1;
      await _pool.execute(
        Sql.named('UPDATE $table SET attempts_left = @a WHERE $keyColumn = @p'),
        parameters: {'a': left, 'p': key},
      );
      return left <= 0 ? 'otp_locked' : 'otp_invalid';
    }
    return null;
  }

  Future<OtpVerifyResult> _loginAs(Session tx, AuthUser user) async {
    if (user.status == 'banned') {
      return (ok: false, error: 'account_suspended', user: null, tokens: null);
    }
    final tokens = await _issueInFamily(tx, user.id, 'user', _newId('fam'));
    return (ok: true, error: null, user: user, tokens: tokens);
  }

  Future<AuthUser?> _userWhere(
    Session session,
    String condition,
    Map<String, Object?> parameters,
  ) async {
    final rows = await session.execute(
      Sql.named('SELECT * FROM users WHERE $condition'),
      parameters: parameters,
    );
    if (rows.isEmpty) return null;
    return _userFrom(rows.first.toColumnMap());
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
    String? phone,
  }) async {
    final existing = await userById(id);
    if (existing == null) return null;
    final newEmail = email == null
        ? existing.email
        : (email.isEmpty ? null : email.trim().toLowerCase());
    final emailChanged = newEmail != existing.email;
    final newPhone = phone == null
        ? existing.phoneNumber
        : (phone.isEmpty ? null : phone.trim());
    final phoneChanged = newPhone != existing.phoneNumber;
    final rows = await _pool.execute(
      Sql.named(
        'UPDATE users SET name = @n:text, email = @e:text, '
        'email_verified = @ev, avatar_url = @a:text, '
        'phone_number = @p:text, phone_verified = @pv '
        'WHERE id = @id RETURNING *',
      ),
      parameters: {
        'n': (name != null && name.isNotEmpty) ? name : existing.name,
        'e': newEmail,
        // A changed email/phone is unverified until proven again.
        'ev': emailChanged ? false : existing.emailVerified,
        'a': avatarUrl ?? existing.avatarUrl,
        'p': newPhone,
        'pv': phoneChanged ? false : existing.phoneVerified,
        'id': id,
      },
    );
    return _userFrom(rows.first.toColumnMap());
  }

  @override
  Future<bool> deleteUser(String id) async {
    final user = await userById(id);
    if (user == null) return false;
    if (user.phoneNumber != null) {
      await _pool.execute(
        Sql.named('DELETE FROM otp_codes WHERE phone_number = @p'),
        parameters: {'p': user.phoneNumber},
      );
    }
    if (user.email != null) {
      await _pool.execute(
        Sql.named('DELETE FROM email_otp_codes WHERE email = @e'),
        parameters: {'e': user.email},
      );
    }
    final res = await _pool.execute(
      Sql.named('DELETE FROM users WHERE id = @id'),
      parameters: {'id': id},
    );
    return res.affectedRows > 0;
  }

  Future<AuthUser> _findOrCreateByPhone(
    Session session,
    String phoneNumber,
  ) async {
    final found = await session.execute(
      Sql.named('SELECT * FROM users WHERE phone_number = @p LIMIT 1'),
      parameters: {'p': phoneNumber},
    );
    if (found.isNotEmpty) {
      final user = _userFrom(found.first.toColumnMap());
      if (!user.phoneVerified) {
        // OTP proved possession of the number.
        await session.execute(
          Sql.named('UPDATE users SET phone_verified = true WHERE id = @id'),
          parameters: {'id': user.id},
        );
        user.phoneVerified = true;
      }
      return user;
    }
    final created = await session.execute(
      Sql.named(
        'INSERT INTO users (id, phone_number, phone_verified, auth_provider) '
        "VALUES (@id, @p, true, 'phone') RETURNING *",
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
    phoneNumber: m['phone_number'] as String?,
    phoneVerified: (m['phone_verified'] as bool?) ?? false,
    createdAt: m['created_at'] as DateTime,
    name: m['name'] as String?,
    email: m['email'] as String?,
    emailVerified: (m['email_verified'] as bool?) ?? false,
    authProvider: m['auth_provider'] as String?,
    avatarUrl: m['avatar_url'] as String?,
    status: (m['status'] as String?) ?? 'active',
  );

  @override
  Future<AuthUser?> setStatus(String id, String status) async {
    final rows = await _pool.execute(
      Sql.named('UPDATE users SET status = @s WHERE id = @id RETURNING *'),
      parameters: {'id': id, 's': status},
    );
    if (rows.isEmpty) return null;
    return _userFrom(rows.first.toColumnMap());
  }

  @override
  Future<({List<AuthUser> items, int total})> listUsers({
    String? status,
    String? q,
    int page = 1,
    int pageSize = 20,
  }) async {
    final conditions = <String>[];
    final params = <String, Object?>{};
    if (status != null && status.isNotEmpty) {
      conditions.add('status = @status');
      params['status'] = status;
    }
    if (q != null && q.isNotEmpty) {
      conditions.add(
        '(name ILIKE @q OR phone_number ILIKE @q OR email ILIKE @q)',
      );
      params['q'] = '%$q%';
    }
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final count = await _pool.execute(
      Sql.named('SELECT COUNT(*)::int AS n FROM users $where'),
      parameters: params,
    );
    final rows = await _pool.execute(
      Sql.named(
        'SELECT * FROM users $where '
        'ORDER BY created_at DESC LIMIT @ps OFFSET @off',
      ),
      parameters: {...params, 'ps': pageSize, 'off': (page - 1) * pageSize},
    );
    return (
      items: rows.map((r) => _userFrom(r.toColumnMap())).toList(),
      total: count.first.toColumnMap()['n'] as int,
    );
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
}
