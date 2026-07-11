import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';

import '../auth/auth_repository.dart'
    show OtpRequestResult, RefreshResult, TokenPair;
import '../auth/provider_auth_repository.dart'
    show ProviderAccount, ProviderAuthRepository, ProviderVerifyResult;
import '../auth/tokens.dart';

/// Postgres-backed [ProviderAuthRepository]. Same security logic as the
/// in-memory impl (hashed OTP + attempt/resend budgets; registration required
/// before login; provider-role JWT on verify) expressed in SQL, parameterized.
/// OTP lives in its own table so it can't collide with consumer OTPs.
class PostgresProviderAuthRepository implements ProviderAuthRepository {
  @override
  Future<void> linkProvider(String accountId, String providerId) async {
    await _pool.execute(
      Sql.named('UPDATE provider_users SET provider_id = @pid WHERE id = @id'),
      parameters: {'pid': providerId, 'id': accountId},
    );
  }

  PostgresProviderAuthRepository(
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
      _requestOtpIn('provider_otp_codes', 'phone_number', phoneNumber);

  @override
  Future<OtpRequestResult> requestEmailOtp(String email) => _requestOtpIn(
    'provider_email_otp_codes',
    'email',
    email.trim().toLowerCase(),
  );

  Future<OtpRequestResult> _requestOtpIn(
    String table,
    String keyColumn,
    String key,
  ) async {
    // An expired code (abandoned flow) doesn't count against the budget.
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
  Future<ProviderVerifyResult> loginWithSocial({
    required String provider,
    required String sub,
    String? email,
    bool emailVerified = false,
  }) async {
    final subColumn = switch (provider) {
      'google' => 'google_sub',
      'apple' => 'apple_sub',
      _ => throw ArgumentError.value(provider, 'provider'),
    };
    final emailKey = email?.trim().toLowerCase();
    return _pool.runTx((tx) async {
      var rows = await tx.execute(
        Sql.named('SELECT * FROM provider_users WHERE $subColumn = @s'),
        parameters: {'s': sub},
      );
      if (rows.isEmpty && emailKey != null && emailVerified) {
        // Link only on a verified email (threat T33/T35).
        rows = await tx.execute(
          Sql.named('SELECT * FROM provider_users WHERE lower(email) = @e'),
          parameters: {'e': emailKey},
        );
        if (rows.isNotEmpty) {
          await tx.execute(
            Sql.named(
              'UPDATE provider_users SET $subColumn = @s, '
              'email_verified = true WHERE id = @id',
            ),
            parameters: {'s': sub, 'id': rows.first.toColumnMap()['id']},
          );
        }
      }
      if (rows.isEmpty) {
        // Never auto-create a salon — registration carries business fields.
        return (
          ok: false,
          error: 'provider_not_found',
          provider: null,
          tokens: null,
        );
      }
      final account = _toAccount(rows.first.toColumnMap());
      final tokens = await _issueInFamily(tx, account.id, _newId('fam'));
      return (ok: true, error: null, provider: account, tokens: tokens);
    });
  }

  @override
  Future<ProviderVerifyResult> verifyEmailOtp(String email, String code) async {
    final key = email.trim().toLowerCase();
    final error = await _checkEmailOtp(key, code);
    if (error != null) {
      return (ok: false, error: error, provider: null, tokens: null);
    }
    final rows = await _pool.execute(
      Sql.named('SELECT * FROM provider_users WHERE lower(email) = @e'),
      parameters: {'e': key},
    );
    if (rows.isEmpty) {
      // Correct code, no salon → NOT consumed; the register screen reuses it.
      return (
        ok: false,
        error: 'provider_not_found',
        provider: null,
        tokens: null,
      );
    }
    final account = _toAccount(rows.first.toColumnMap());
    return _pool.runTx((tx) async {
      await tx.execute(
        Sql.named('DELETE FROM provider_email_otp_codes WHERE email = @e'),
        parameters: {'e': key},
      );
      await tx.execute(
        Sql.named(
          'UPDATE provider_users SET email_verified = true WHERE id = @id',
        ),
        parameters: {'id': account.id},
      );
      final tokens = await _issueInFamily(tx, account.id, _newId('fam'));
      return (ok: true, error: null, provider: account, tokens: tokens);
    });
  }

  @override
  Future<ProviderVerifyResult> register({
    required String businessName,
    required String businessType,
    required String phoneNumber,
    required String email,
    required String authProvider,
    String? emailCode,
    String? googleSub,
    String? appleSub,
    String? address,
    String? providerId,
  }) async {
    final emailKey = email.trim().toLowerCase();
    // Email-identity registrations prove inbox ownership here (Google/Apple
    // tokens were verified by the route).
    if (authProvider == 'email') {
      final error = await _checkEmailOtp(emailKey, emailCode ?? '');
      if (error != null) {
        return (ok: false, error: error, provider: null, tokens: null);
      }
    }
    final exists = await _pool.execute(
      Sql.named(
        'SELECT 1 FROM provider_users WHERE lower(email) = @e '
        'OR (google_sub IS NOT NULL AND google_sub = @gs:text) '
        'OR (apple_sub IS NOT NULL AND apple_sub = @asub:text)',
      ),
      parameters: {'e': emailKey, 'gs': googleSub, 'asub': appleSub},
    );
    if (exists.isNotEmpty) {
      return (
        ok: false,
        error: 'provider_exists',
        provider: null,
        tokens: null,
      );
    }
    return _pool.runTx((tx) async {
      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO provider_users '
          '(id, phone_number, business_name, business_type, email, '
          'email_verified, auth_provider, google_sub, apple_sub, address, '
          'provider_id) '
          'VALUES (@id, @p, @bn, @bt, @e, true, @ap, @gs:text, @asub:text, '
          '@addr:text, @pid:text) RETURNING *',
        ),
        parameters: {
          'id': _newId('provider'),
          'p': phoneNumber,
          'bn': businessName,
          'bt': businessType,
          'e': emailKey,
          'ap': authProvider,
          'gs': googleSub,
          'asub': appleSub,
          'addr': address,
          'pid': providerId,
        },
      );
      await tx.execute(
        Sql.named('DELETE FROM provider_email_otp_codes WHERE email = @e'),
        parameters: {'e': emailKey},
      );
      final account = _toAccount(rows.first.toColumnMap());
      final tokens = await _issueInFamily(tx, account.id, _newId('fam'));
      return (ok: true, error: null, provider: account, tokens: tokens);
    });
  }

  /// Check an email code; null = valid (NOT consumed — callers consume).
  Future<String?> _checkEmailOtp(String key, String code) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT code_hash, expires_at, attempts_left '
        'FROM provider_email_otp_codes WHERE email = @e',
      ),
      parameters: {'e': key},
    );
    if (rows.isEmpty) return 'otp_none';
    final row = rows.first.toColumnMap();
    if (DateTime.now().toUtc().isAfter(
      (row['expires_at'] as DateTime).toUtc(),
    )) {
      await _pool.execute(
        Sql.named('DELETE FROM provider_email_otp_codes WHERE email = @e'),
        parameters: {'e': key},
      );
      return 'otp_expired';
    }
    final attemptsLeft = row['attempts_left'] as int;
    if (attemptsLeft <= 0) return 'otp_locked';
    if ((row['code_hash'] as String) != _tokens.hashToken(code)) {
      final left = attemptsLeft - 1;
      await _pool.execute(
        Sql.named(
          'UPDATE provider_email_otp_codes SET attempts_left = @a '
          'WHERE email = @e',
        ),
        parameters: {'a': left, 'e': key},
      );
      return left <= 0 ? 'otp_locked' : 'otp_invalid';
    }
    return null;
  }

  @override
  Future<ProviderVerifyResult> verifyOtp(
    String phoneNumber,
    String code,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT code_hash, expires_at, attempts_left '
        'FROM provider_otp_codes WHERE phone_number = @p',
      ),
      parameters: {'p': phoneNumber},
    );
    if (rows.isEmpty) {
      return (ok: false, error: 'otp_none', provider: null, tokens: null);
    }
    final row = rows.first.toColumnMap();
    if (DateTime.now().toUtc().isAfter(
      (row['expires_at'] as DateTime).toUtc(),
    )) {
      await _deleteOtp(phoneNumber);
      return (ok: false, error: 'otp_expired', provider: null, tokens: null);
    }
    final attemptsLeft = row['attempts_left'] as int;
    if (attemptsLeft <= 0) {
      return (ok: false, error: 'otp_locked', provider: null, tokens: null);
    }
    if ((row['code_hash'] as String) != _tokens.hashToken(code)) {
      final left = attemptsLeft - 1;
      await _pool.execute(
        Sql.named(
          'UPDATE provider_otp_codes SET attempts_left = @a '
          'WHERE phone_number = @p',
        ),
        parameters: {'a': left, 'p': phoneNumber},
      );
      return (
        ok: false,
        error: left <= 0 ? 'otp_locked' : 'otp_invalid',
        provider: null,
        tokens: null,
      );
    }
    final accountRows = await _pool.execute(
      Sql.named('SELECT * FROM provider_users WHERE phone_number = @p'),
      parameters: {'p': phoneNumber},
    );
    if (accountRows.isEmpty) {
      // Must register before logging in.
      return (
        ok: false,
        error: 'provider_not_found',
        provider: null,
        tokens: null,
      );
    }
    final account = _toAccount(accountRows.first.toColumnMap());
    return _pool.runTx((tx) async {
      await tx.execute(
        Sql.named('DELETE FROM provider_otp_codes WHERE phone_number = @p'),
        parameters: {'p': phoneNumber},
      );
      final tokens = await _issueInFamily(tx, account.id, _newId('fam'));
      return (ok: true, error: null, provider: account, tokens: tokens);
    });
  }

  @override
  Future<RefreshResult> refresh(String refreshToken) async {
    final hash = _tokens.hashToken(refreshToken);
    final rows = await _pool.execute(
      Sql.named(
        'SELECT account_id, family_id, rotated '
        'FROM provider_refresh_tokens WHERE token_hash = @h',
      ),
      parameters: {'h': hash},
    );
    if (rows.isEmpty) {
      return (ok: false, error: 'refresh_invalid', tokens: null);
    }
    final row = rows.first.toColumnMap();
    if (row['rotated'] as bool) {
      await _pool.execute(
        Sql.named('DELETE FROM provider_refresh_tokens WHERE family_id = @f'),
        parameters: {'f': row['family_id']},
      );
      return (ok: false, error: 'refresh_reused', tokens: null);
    }
    return _pool.runTx((tx) async {
      await tx.execute(
        Sql.named(
          'UPDATE provider_refresh_tokens SET rotated = true '
          'WHERE token_hash = @h',
        ),
        parameters: {'h': hash},
      );
      final tokens = await _issueInFamily(
        tx,
        row['account_id'] as String,
        row['family_id'] as String,
      );
      return (ok: true, error: null, tokens: tokens);
    });
  }

  Future<TokenPair> _issueInFamily(
    Session session,
    String accountId,
    String familyId,
  ) async {
    final access = _tokens.issueAccessToken(
      subject: accountId,
      role: 'provider',
    );
    final refresh = _tokens.generateRefreshToken();
    await session.execute(
      Sql.named(
        'INSERT INTO provider_refresh_tokens '
        '(token_hash, account_id, family_id) VALUES (@h, @a, @f)',
      ),
      parameters: {
        'h': _tokens.hashToken(refresh),
        'a': accountId,
        'f': familyId,
      },
    );
    return (
      accessToken: access.token,
      refreshToken: refresh,
      expiresAt: access.expiresAt,
    );
  }

  @override
  Future<ProviderAccount?> accountById(String id) async {
    final rows = await _pool.execute(
      Sql.named('SELECT * FROM provider_users WHERE id = @id'),
      parameters: {'id': id},
    );
    if (rows.isEmpty) return null;
    return _toAccount(rows.first.toColumnMap());
  }

  @override
  Future<ProviderAccount?> submitKyc(
    String accountId,
    List<Map<String, dynamic>> docs,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        "UPDATE provider_users SET kyc_docs = @docs:jsonb, "
        "verification_status = 'pending', rejection_reason = NULL "
        "WHERE id = @id RETURNING *",
      ),
      parameters: {'id': accountId, 'docs': jsonEncode(docs)},
    );
    if (rows.isEmpty) return null;
    return _toAccount(rows.first.toColumnMap());
  }

  @override
  Future<({List<ProviderAccount> items, int total})> listByVerificationStatus(
    String status, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final count = await _pool.execute(
      Sql.named(
        'SELECT COUNT(*)::int FROM provider_users '
        'WHERE verification_status = @s',
      ),
      parameters: {'s': status},
    );
    final total = count.first[0]! as int;
    final rows = await _pool.execute(
      Sql.named(
        'SELECT * FROM provider_users WHERE verification_status = @s '
        'ORDER BY created_at DESC LIMIT @ps OFFSET @off',
      ),
      parameters: {'s': status, 'ps': pageSize, 'off': (page - 1) * pageSize},
    );
    return (
      items: rows.map((r) => _toAccount(r.toColumnMap())).toList(),
      total: total,
    );
  }

  @override
  Future<ProviderAccount?> setVerification(
    String accountId, {
    required String status,
    String? rejectionReason,
  }) async {
    final rows = await _pool.execute(
      Sql.named(
        'UPDATE provider_users SET verification_status = @s, '
        'rejection_reason = @r WHERE id = @id RETURNING *',
      ),
      parameters: {'id': accountId, 's': status, 'r': rejectionReason},
    );
    if (rows.isEmpty) return null;
    return _toAccount(rows.first.toColumnMap());
  }

  Future<void> _deleteOtp(String phoneNumber) => _pool.execute(
    Sql.named('DELETE FROM provider_otp_codes WHERE phone_number = @p'),
    parameters: {'p': phoneNumber},
  );

  ProviderAccount _toAccount(Map<String, dynamic> r) => ProviderAccount(
    id: r['id'] as String,
    phoneNumber: r['phone_number'] as String,
    businessName: r['business_name'] as String,
    businessType: r['business_type'] as String,
    createdAt: r['created_at'] as DateTime,
    name: r['name'] as String?,
    email: r['email'] as String?,
    emailVerified: (r['email_verified'] as bool?) ?? false,
    authProvider: r['auth_provider'] as String?,
    googleSub: r['google_sub'] as String?,
    appleSub: r['apple_sub'] as String?,
    address: r['address'] as String?,
    verificationStatus: (r['verification_status'] as String?) ?? 'pending',
    rejectionReason: r['rejection_reason'] as String?,
    providerId: r['provider_id'] as String?,
    kycDocs: _kycDocs(r['kyc_docs']),
  );

  List<Map<String, dynamic>> _kycDocs(Object? raw) {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! List) return const [];
    return [for (final e in decoded) Map<String, dynamic>.from(e as Map)];
  }

  @override
  Future<bool> deleteAccount(String accountId) async {
    final account = await accountById(accountId);
    if (account == null) return false;
    // Sessions first: every refresh token of the account dies.
    await _pool.execute(
      Sql.named('DELETE FROM provider_refresh_tokens WHERE account_id = @a'),
      parameters: {'a': accountId},
    );
    final email = account.email?.toLowerCase();
    if (email != null) {
      await _pool.execute(
        Sql.named('DELETE FROM provider_email_otp_codes WHERE email = @e'),
        parameters: {'e': email},
      );
    }
    if (account.phoneNumber.isNotEmpty) {
      await _pool.execute(
        Sql.named('DELETE FROM provider_otp_codes WHERE phone_number = @p'),
        parameters: {'p': account.phoneNumber},
      );
    }
    // The row carries the KYC docs (kyc_docs jsonb) — they go with it.
    final res = await _pool.execute(
      Sql.named('DELETE FROM provider_users WHERE id = @id'),
      parameters: {'id': accountId},
    );
    return res.affectedRows > 0;
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
}
