import 'dart:math';

import 'package:postgres/postgres.dart';

import '../auth/auth_repository.dart' show OtpRequestResult;
import '../auth/provider_auth_repository.dart'
    show
        ProviderAccount,
        ProviderAuthRepository,
        ProviderRegisterResult,
        ProviderVerifyResult;
import '../auth/tokens.dart';

/// Postgres-backed [ProviderAuthRepository]. Same security logic as the
/// in-memory impl (hashed OTP + attempt/resend budgets; registration required
/// before login; provider-role JWT on verify) expressed in SQL, parameterized.
/// OTP lives in its own table so it can't collide with consumer OTPs.
class PostgresProviderAuthRepository implements ProviderAuthRepository {
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
  Future<OtpRequestResult> requestOtp(String phoneNumber) async {
    final existing = await _pool.execute(
      Sql.named(
        'SELECT resends_left FROM provider_otp_codes WHERE phone_number = @p',
      ),
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
        'INSERT INTO provider_otp_codes '
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
  Future<ProviderRegisterResult> register({
    required String phoneNumber,
    required String businessName,
    required String businessType,
    String? address,
    String? providerId,
  }) async {
    final exists = await _pool.execute(
      Sql.named('SELECT 1 FROM provider_users WHERE phone_number = @p'),
      parameters: {'p': phoneNumber},
    );
    if (exists.isNotEmpty) {
      return (
        ok: false,
        error: 'provider_exists',
        provider: null,
        devCode: null,
        expiresInSeconds: 0,
      );
    }
    final rows = await _pool.execute(
      Sql.named(
        'INSERT INTO provider_users '
        '(id, phone_number, business_name, business_type, address, provider_id) '
        'VALUES (@id, @p, @bn, @bt, @addr:text, @pid:text) RETURNING *',
      ),
      parameters: {
        'id': _newId('provider'),
        'p': phoneNumber,
        'bn': businessName,
        'bt': businessType,
        'addr': address,
        'pid': providerId,
      },
    );
    final account = _toAccount(rows.first.toColumnMap());
    final otp = await requestOtp(phoneNumber);
    return (
      ok: true,
      error: null,
      provider: account,
      devCode: otp.devCode,
      expiresInSeconds: otp.expiresInSeconds,
    );
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
      return (ok: false, error: 'otp_none', provider: null, accessToken: null);
    }
    final row = rows.first.toColumnMap();
    if (DateTime.now().toUtc().isAfter(
      (row['expires_at'] as DateTime).toUtc(),
    )) {
      await _deleteOtp(phoneNumber);
      return (
        ok: false,
        error: 'otp_expired',
        provider: null,
        accessToken: null,
      );
    }
    final attemptsLeft = row['attempts_left'] as int;
    if (attemptsLeft <= 0) {
      return (
        ok: false,
        error: 'otp_locked',
        provider: null,
        accessToken: null,
      );
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
        accessToken: null,
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
        accessToken: null,
      );
    }
    await _deleteOtp(phoneNumber);
    final account = _toAccount(accountRows.first.toColumnMap());
    final access = _tokens.issueAccessToken(
      subject: account.id,
      role: 'provider',
    );
    return (
      ok: true,
      error: null,
      provider: account,
      accessToken: access.token,
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
    address: r['address'] as String?,
    verificationStatus: (r['verification_status'] as String?) ?? 'pending',
    rejectionReason: r['rejection_reason'] as String?,
    providerId: r['provider_id'] as String?,
  );

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
}
