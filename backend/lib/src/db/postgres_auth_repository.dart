import 'dart:math';

import 'package:postgres/postgres.dart';

import '../auth/auth_repository.dart';
import '../auth/tokens.dart';
import 'refresh_exchange.dart';

/// Postgres-backed [AuthRepository]. Same security logic as
/// [InMemoryAuthRepository] (OTP hashed + attempt/resend budgets; refresh
/// hashed, rotated atomically, reuse past a 30 s grace → family revoke —
/// docs/design/backend-refresh-rotation-atomic.md) expressed in SQL. All
/// queries are parameterized; multi-write paths run in a transaction.
class PostgresAuthRepository implements AuthRepository {
  PostgresAuthRepository(
    this._pool, {
    required TokenService tokens,
    required bool echoDevCode,
    Duration otpValidity = const Duration(minutes: 5),
    int maxAttempts = 5,
    int maxResends = 3,
  }) : _tokens = tokens,
       _echoDevCode = echoDevCode,
       _otpValidity = otpValidity,
       _maxAttempts = maxAttempts,
       _maxResends = maxResends;

  final Pool<void> _pool;
  final TokenService _tokens;
  final bool _echoDevCode;
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

  @override
  Future<void> refundEmailOtpResend(String email) =>
      _refundResendIn('email_otp_codes', 'email', email.trim().toLowerCase());

  /// One statement, and LEAST() is the guard: the refund can never lift an
  /// allowance above the maximum, however many times it is called. Scoped to an
  /// unexpired row so a stale code cannot be revived. Design:
  /// docs/design/backend-email-send-budget.md §9.
  Future<void> _refundResendIn(
    String table,
    String keyColumn,
    String key,
  ) async {
    await _pool.execute(
      Sql.named(
        'UPDATE $table SET resends_left = LEAST(resends_left + 1, @m) '
        'WHERE $keyColumn = @p AND expires_at > now()',
      ),
      parameters: {'p': key, 'm': _maxResends},
    );
  }

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
      devCode: _echoDevCode ? code : null,
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
    return _retried(
      raced: true,
      () => _pool.runTx((tx) async {
        // Checked and consumed in this transaction, its row locked: one code is
        // redeemable here and at `/me/email/otp/verify`, so a check outside the
        // consumption would let both redeem it (B16.3 §5.3). A refusal returns
        // normally, so its attempt accounting commits.
        final error = await _inspectEmailCode(tx, key, code);
        if (error != null) {
          return (ok: false, error: error, user: null, tokens: null);
        }
        await _consumeEmailCode(tx, key);
        // B16.3 §5.1: the address reaches only an account that PROVED it; one
        // holding it unproven loses it to the prover.
        var user = await _userWhere(
          tx,
          'lower(email) = @e AND email_verified',
          {'e': key},
        );
        if (user == null) {
          await _takeUnproven(tx, key);
          final created = await tx.execute(
            Sql.named(
              'INSERT INTO users (id, email, email_verified, auth_provider) '
              "VALUES (@id, @e, true, 'email') RETURNING *",
            ),
            parameters: {'id': _newId('user'), 'e': key},
          );
          user = _userFrom(created.first.toColumnMap());
        }
        return _loginAs(tx, user);
      }),
    );
  }

  /// Runs [run] — one whole transaction, every effect inside it — again when
  /// Postgres aborted it for a reason a re-run resolves (B16.3, review):
  /// - `40P01`, a deadlock: a code sign-in locks the code row, then the
  ///   account (its take, or its refresh token's foreign key); an e-mail change
  ///   locks the account, then the code rows. Postgres aborts one of the two;
  ///   re-run, it queues behind the other.
  /// - with [raced], a `23505`: a sign-in found no proven holder and inserted
  ///   one, while another committed the address first (a concurrent sign-in,
  ///   or a holder proving it). Re-run, it finds that holder.
  /// Each run rolled back whole, a code's consumption included, so a re-run
  /// is the first run against newer data. Three runs at most, then the error.
  Future<T> _retried<T>(Future<T> Function() run, {bool raced = false}) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await run();
      } on ServerException catch (e) {
        final again =
            e.code == '40P01' || (raced && e is UniqueViolationException);
        if (!again || attempt >= 3) rethrow;
      }
    }
  }

  /// The holder of an address it never proved loses it (B16.3 §5.1): its
  /// account, sessions and other sign-ins stay. [except] keeps the changing
  /// account's own row out of it.
  Future<void> _takeUnproven(Session tx, String key, {String? except}) =>
      tx.execute(
        Sql.named(
          'UPDATE users SET email = NULL, email_verified = false '
          'WHERE lower(email) = @e AND NOT email_verified'
          '${except == null ? '' : ' AND id <> @x'}',
        ),
        parameters: {'e': key, if (except != null) 'x': except},
      );

  /// An e-mail code checked under its row's lock, NOT consumed: null means
  /// valid. A refusal is accounted here (an expired row deleted, a wrong code
  /// spending an attempt), as `_checkOtpIn` does on the pool.
  Future<String?> _inspectEmailCode(Session tx, String key, String code) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT code_hash, attempts_left, expires_at <= now() AS expired '
        'FROM email_otp_codes WHERE email = @p FOR UPDATE',
      ),
      parameters: {'p': key},
    );
    if (rows.isEmpty) return 'otp_none';
    final row = rows.first.toColumnMap();
    if (row['expired'] as bool) {
      await _consumeEmailCode(tx, key);
      return 'otp_expired';
    }
    final attemptsLeft = row['attempts_left'] as int;
    if (attemptsLeft <= 0) return 'otp_locked';
    if ((row['code_hash'] as String) != _tokens.hashToken(code)) {
      final left = attemptsLeft - 1;
      await tx.execute(
        Sql.named(
          'UPDATE email_otp_codes SET attempts_left = @a WHERE email = @p',
        ),
        parameters: {'a': left, 'p': key},
      );
      return left <= 0 ? 'otp_locked' : 'otp_invalid';
    }
    return null;
  }

  Future<void> _consumeEmailCode(Session tx, String key) => tx.execute(
    Sql.named('DELETE FROM email_otp_codes WHERE email = @p'),
    parameters: {'p': key},
  );

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
    final proves = emailKey != null && emailVerified;
    return _retried(
      raced: true,
      () => _pool.runTx((tx) async {
        Future<AuthUser> create({
          required String? address,
          required bool proven,
        }) async {
          final created = await tx.execute(
            Sql.named(
              'INSERT INTO users '
              '(id, email, email_verified, $subColumn, auth_provider, name, avatar_url) '
              'VALUES (@id, @e:text, @v, @s, @p, @n:text, @a:text) RETURNING *',
            ),
            parameters: {
              'id': _newId('user'),
              'e': address,
              'v': proven,
              's': sub,
              'p': provider,
              'n': name,
              'a': avatarUrl,
            },
          );
          return _userFrom(created.first.toColumnMap());
        }

        // 1. By sub. Its own unproven address, asserted by the provider, is
        //    proven now; it takes nothing from anyone else (B16.3 §5.1).
        final bySub = await _userWhere(tx, '$subColumn = @s', {'s': sub});
        if (bySub != null) {
          if (proves &&
              !bySub.emailVerified &&
              bySub.email?.toLowerCase() == emailKey) {
            await tx.execute(
              Sql.named(
                'UPDATE users SET email_verified = true WHERE id = @id',
              ),
              parameters: {'id': bySub.id},
            );
            bySub.emailVerified = true;
          }
          return _loginAs(tx, bySub);
        }
        if (!proves) {
          // Kept out: an unverified address is stored only when nobody holds
          // it, and takes nothing (T33).
          final held =
              emailKey != null &&
              await _userWhere(tx, 'lower(email) = @e', {'e': emailKey}) !=
                  null;
          return _loginAs(
            tx,
            await create(address: held ? null : emailKey, proven: false),
          );
        }
        // 2. A proven holder: link when its sub for this provider is EMPTY. A
        //    sub already there is never replaced — it used to be, which handed
        //    the account to whoever the provider now says owns the address
        //    (B16.3 §5.1) — so this sign-in gets an account of its own.
        final holder = await _userWhere(
          tx,
          'lower(email) = @e AND email_verified',
          {'e': emailKey},
        );
        if (holder != null) {
          final linked = await tx.execute(
            Sql.named(
              'UPDATE users SET $subColumn = @s, '
              'name = COALESCE(name, @n:text), '
              'avatar_url = COALESCE(avatar_url, @a:text) '
              'WHERE id = @id AND $subColumn IS NULL RETURNING *',
            ),
            parameters: {'s': sub, 'n': name, 'a': avatarUrl, 'id': holder.id},
          );
          if (linked.isNotEmpty) {
            return _loginAs(tx, _userFrom(linked.first.toColumnMap()));
          }
          return _loginAs(tx, await create(address: null, proven: false));
        }
        // 3. Take it from an unproven holder, then create.
        await _takeUnproven(tx, emailKey);
        return _loginAs(tx, await create(address: emailKey, proven: true));
      }),
    );
  }

  @override
  Future<bool> emailIsOnlySignIn(String userId) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT (email IS NOT NULL AND email_verified AND google_sub IS NULL '
        'AND apple_sub IS NULL) AS only FROM users WHERE id = @id',
      ),
      parameters: {'id': userId},
    );
    return rows.isNotEmpty && rows.first.toColumnMap()['only'] as bool;
  }

  /// One transaction (§5.3): the account locked, the new address's code
  /// checked first — so « taken » is said only to whoever proves the inbox
  /// (decision 262) — then the holder, then decision 265's second code, and
  /// only then both codes consumed, the take, and the set. The partial unique
  /// index stays the last guard: a race past the holder read throws `23505`,
  /// rolls everything back (the codes included) and answers `email_taken`.
  @override
  Future<EmailChangeResult> changeEmail(
    String userId,
    String email,
    String code, {
    String? currentCode,
  }) async {
    final key = email.trim().toLowerCase();
    try {
      return await _retried(
        () => _pool.runTx((tx) async {
          final rows = await tx.execute(
            Sql.named(
              'SELECT *, (google_sub IS NOT NULL OR apple_sub IS NOT NULL) '
              'AS linked FROM users WHERE id = @id FOR NO KEY UPDATE',
            ),
            parameters: {'id': userId},
          );
          if (rows.isEmpty) return emailChangeRefused('not_found');
          final row = rows.first.toColumnMap();
          final user = _userFrom(row);
          if (user.status == 'banned') {
            return emailChangeRefused('account_suspended');
          }
          final current = user.email?.toLowerCase();
          if (current == key && user.emailVerified) {
            return emailChangeRefused('email_unchanged');
          }
          final refused = await _inspectEmailCode(tx, key, code);
          if (refused != null) return emailChangeRefused(refused);
          final holder = await _userWhere(
            tx,
            'lower(email) = @e AND id <> @id',
            {'e': key, 'id': userId},
          );
          if (holder != null && holder.emailVerified) {
            // Nothing consumed: the code still signs its owner in (§3.1).
            return emailChangeRefused('email_taken');
          }
          final needsCurrent =
              current != null && user.emailVerified && !(row['linked'] as bool);
          if (needsCurrent) {
            if (currentCode == null) {
              return emailChangeRefused('current_otp_none');
            }
            final refusedCurrent = await _inspectEmailCode(
              tx,
              current,
              currentCode,
            );
            if (refusedCurrent != null) {
              return emailChangeRefused('current_$refusedCurrent');
            }
            await _consumeEmailCode(tx, current);
          }
          await _consumeEmailCode(tx, key);
          await _takeUnproven(tx, key, except: userId);
          final updated = await tx.execute(
            Sql.named(
              'UPDATE users SET email = @e, email_verified = true '
              'WHERE id = @id RETURNING *',
            ),
            parameters: {'e': key, 'id': userId},
          );
          return (
            ok: true,
            error: null,
            user: _userFrom(updated.first.toColumnMap()),
            previousEmail: user.emailVerified ? current : null,
          );
        }),
      );
    } on UniqueViolationException {
      return emailChangeRefused('email_taken');
    }
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

  /// One transaction: atomic claim, 30 s grace on the database clock, family
  /// revoke past it. Design: docs/design/backend-refresh-rotation-atomic.md.
  @override
  Future<RefreshResult> refresh(String refreshToken) {
    final hash = _tokens.hashToken(refreshToken);
    return _pool.runTx(
      (tx) => exchangeRefreshToken(
        tx,
        table: 'refresh_tokens',
        ownerColumns: 'user_id, role',
        tokenHash: hash,
        issueChild: (row) => _issueInFamily(
          tx,
          row['user_id'] as String,
          row['role'] as String,
          row['family_id'] as String,
        ),
      ),
    );
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
    String? avatarUrl,
    String? phone,
  }) async {
    final existing = await userById(id);
    if (existing == null) return null;
    final newPhone = phone == null
        ? existing.phoneNumber
        : (phone.isEmpty ? null : phone.trim());
    final phoneChanged = newPhone != existing.phoneNumber;
    final rows = await _pool.execute(
      Sql.named(
        'UPDATE users SET name = @n:text, avatar_url = @a:text, '
        'phone_number = @p:text, phone_verified = @pv '
        'WHERE id = @id RETURNING *',
      ),
      parameters: {
        'n': (name != null && name.isNotEmpty) ? name : existing.name,
        // A changed phone is unverified until proven again. The address is
        // not written here (B16.3): `changeEmail` only.
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
