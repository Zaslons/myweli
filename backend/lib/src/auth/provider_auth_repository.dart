import 'dart:math';

import 'auth_repository.dart' show OtpRequestResult, RefreshResult, TokenPair;
import 'tokens.dart';

/// Public-facing provider-account fields. Mirrors the app's `ProviderUser` DTO
/// (and the OpenAPI `ProviderUser` schema) field-for-field. `kycDocs` holds the
/// submitted KYC document metadata + private storage keys (design:
/// docs/design/pro-kyc.md).
class ProviderAccount {
  ProviderAccount({
    required this.id,
    required this.phoneNumber,
    required this.businessName,
    required this.businessType,
    required this.createdAt,
    this.name,
    this.email,
    this.address,
    this.verificationStatus = 'pending',
    this.rejectionReason,
    this.providerId,
    this.kycDocs = const [],
  });

  final String id;
  final String phoneNumber;
  final String businessName;
  final String businessType;
  final DateTime createdAt;
  String? name;
  String? email;
  String? address;
  String verificationStatus;
  String? rejectionReason;
  String? providerId;
  List<Map<String, dynamic>> kycDocs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'phoneNumber': phoneNumber,
    'name': name,
    'businessName': businessName,
    'businessType': businessType,
    'email': email,
    'address': address,
    'verificationStatus': verificationStatus,
    'rejectionReason': rejectionReason,
    'kycDocs': kycDocs,
    'createdAt': createdAt.toIso8601String(),
    'providerId': providerId,
  };
}

/// Register + send-OTP outcome (`devCode` only outside production).
typedef ProviderRegisterResult = ({
  bool ok,
  String? error,
  ProviderAccount? provider,
  String? devCode,
  int expiresInSeconds,
});

/// Verify outcome: the provider account + a freshly issued token pair (access
/// JWT role `provider` + a rotating opaque refresh token).
typedef ProviderVerifyResult = ({
  bool ok,
  String? error,
  ProviderAccount? provider,
  TokenPair? tokens,
});

/// Provider auth store + security logic (docs/BACKEND.md §3): hashed OTP with an
/// attempt/resend budget, mirroring the consumer flow. In-memory now; a Postgres
/// impl satisfies the same interface in a follow-up.
abstract interface class ProviderAuthRepository {
  Future<OtpRequestResult> requestOtp(String phoneNumber);
  Future<ProviderRegisterResult> register({
    required String phoneNumber,
    required String businessName,
    required String businessType,
    String? address,
    String? providerId,
  });
  Future<ProviderVerifyResult> verifyOtp(String phoneNumber, String code);

  /// Exchange a refresh token for a fresh pair. Rotates the presented token;
  /// replaying an already-rotated token is treated as theft and revokes the
  /// whole family (mirrors the consumer flow).
  Future<RefreshResult> refresh(String refreshToken);

  /// The provider account for an id (the access-token `sub`), or null — used to
  /// authorize pro actions (resolve the account → the Provider it manages).
  Future<ProviderAccount?> accountById(String id);

  /// Store submitted KYC [docs] for the account and reset verification to
  /// `pending` (clearing any prior rejection). Returns the updated account, or
  /// null if it doesn't exist. (Design: docs/design/pro-kyc.md.)
  Future<ProviderAccount?> submitKyc(
    String accountId,
    List<Map<String, dynamic>> docs,
  );

  /// Admin: accounts with the given verification [status] (e.g. `pending`),
  /// newest-first, paginated. (Design: docs/design/admin-console.md.)
  Future<({List<ProviderAccount> items, int total})> listByVerificationStatus(
    String status, {
    int page,
    int pageSize,
  });

  /// Admin: set an account's verification [status] (`verified`/`rejected`) and
  /// optional [rejectionReason]. Returns the updated account, or null if absent.
  Future<ProviderAccount?> setVerification(
    String accountId, {
    required String status,
    String? rejectionReason,
  });
}

class _Otp {
  _Otp({
    required this.codeHash,
    required this.expiresAt,
    required this.attemptsLeft,
    required this.resendsLeft,
  });
  final String codeHash;
  final DateTime expiresAt;
  int attemptsLeft;
  int resendsLeft;
}

class _Refresh {
  _Refresh({required this.accountId, required this.familyId});
  final String accountId;
  final String familyId;
  bool rotated = false;
}

class InMemoryProviderAuthRepository implements ProviderAuthRepository {
  InMemoryProviderAuthRepository({
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

  final TokenService _tokens;
  final bool _isProd;
  final Duration _otpValidity;
  final int _maxAttempts;
  final int _maxResends;
  final Random _random = Random.secure();

  final Map<String, _Refresh> _refreshByHash = {};
  final Map<String, ProviderAccount> _byPhone = {};
  final Map<String, ProviderAccount> _byId = {};
  final Map<String, _Otp> _otps = {};

  @override
  Future<ProviderAccount?> accountById(String id) async => _byId[id];

  @override
  Future<ProviderAccount?> submitKyc(
    String accountId,
    List<Map<String, dynamic>> docs,
  ) async {
    final account = _byId[accountId];
    if (account == null) return null;
    account
      ..kycDocs = List<Map<String, dynamic>>.from(docs)
      ..verificationStatus = 'pending'
      ..rejectionReason = null;
    return account;
  }

  @override
  Future<({List<ProviderAccount> items, int total})> listByVerificationStatus(
    String status, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final all =
        _byId.values.where((a) => a.verificationStatus == status).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <ProviderAccount>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return (items: items, total: all.length);
  }

  @override
  Future<ProviderAccount?> setVerification(
    String accountId, {
    required String status,
    String? rejectionReason,
  }) async {
    final account = _byId[accountId];
    if (account == null) return null;
    account
      ..verificationStatus = status
      ..rejectionReason = rejectionReason;
    return account;
  }

  @override
  Future<OtpRequestResult> requestOtp(String phoneNumber) async {
    final issued = _issueOtp(phoneNumber);
    if (issued == null) {
      return (
        ok: false,
        error: 'otp_resend_limit',
        code: null,
        devCode: null,
        expiresInSeconds: 0,
      );
    }
    return (
      ok: true,
      error: null,
      code: issued.code,
      devCode: issued.devCode,
      expiresInSeconds: issued.expiresInSeconds,
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
    if (_byPhone.containsKey(phoneNumber)) {
      return (
        ok: false,
        error: 'provider_exists',
        provider: null,
        devCode: null,
        expiresInSeconds: 0,
      );
    }
    final account = ProviderAccount(
      id: _newId('provider'),
      phoneNumber: phoneNumber,
      businessName: businessName,
      businessType: businessType,
      address: address,
      providerId: providerId,
      createdAt: DateTime.now().toUtc(),
    );
    _byPhone[phoneNumber] = account;
    _byId[account.id] = account;
    final otp = _issueOtp(phoneNumber)!; // fresh phone → always issues
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
    final otp = _otps[phoneNumber];
    if (otp == null) {
      return (ok: false, error: 'otp_none', provider: null, tokens: null);
    }
    if (DateTime.now().toUtc().isAfter(otp.expiresAt)) {
      _otps.remove(phoneNumber);
      return (ok: false, error: 'otp_expired', provider: null, tokens: null);
    }
    if (otp.attemptsLeft <= 0) {
      return (ok: false, error: 'otp_locked', provider: null, tokens: null);
    }
    if (otp.codeHash != _tokens.hashToken(code)) {
      otp.attemptsLeft -= 1;
      return (
        ok: false,
        error: otp.attemptsLeft <= 0 ? 'otp_locked' : 'otp_invalid',
        provider: null,
        tokens: null,
      );
    }
    final account = _byPhone[phoneNumber];
    if (account == null) {
      // Must register before logging in (unlike the lax mock).
      return (
        ok: false,
        error: 'provider_not_found',
        provider: null,
        tokens: null,
      );
    }
    _otps.remove(phoneNumber);
    return (
      ok: true,
      error: null,
      provider: account,
      tokens: _issueInFamily(account.id, _newId('fam')),
    );
  }

  @override
  Future<RefreshResult> refresh(String refreshToken) async {
    final rec = _refreshByHash[_tokens.hashToken(refreshToken)];
    if (rec == null) {
      return (ok: false, error: 'refresh_invalid', tokens: null);
    }
    if (rec.rotated) {
      _revokeFamily(rec.familyId);
      return (ok: false, error: 'refresh_reused', tokens: null);
    }
    rec.rotated = true;
    return (
      ok: true,
      error: null,
      tokens: _issueInFamily(rec.accountId, rec.familyId),
    );
  }

  /// Issues an access JWT (role `provider`) + a rotating opaque refresh token,
  /// storing only the refresh hash, tied to [familyId].
  TokenPair _issueInFamily(String accountId, String familyId) {
    final access = _tokens.issueAccessToken(
      subject: accountId,
      role: 'provider',
    );
    final refresh = _tokens.generateRefreshToken();
    _refreshByHash[_tokens.hashToken(refresh)] = _Refresh(
      accountId: accountId,
      familyId: familyId,
    );
    return (
      accessToken: access.token,
      refreshToken: refresh,
      expiresAt: access.expiresAt,
    );
  }

  void _revokeFamily(String familyId) =>
      _refreshByHash.removeWhere((_, r) => r.familyId == familyId);

  ({String? code, String? devCode, int expiresInSeconds})? _issueOtp(
    String phoneNumber,
  ) {
    final existing = _otps[phoneNumber];
    if (existing != null && existing.resendsLeft <= 0) return null;
    final resendsLeft = existing == null
        ? _maxResends
        : existing.resendsLeft - 1;
    final code = (100000 + _random.nextInt(900000)).toString();
    _otps[phoneNumber] = _Otp(
      codeHash: _tokens.hashToken(code),
      expiresAt: DateTime.now().toUtc().add(_otpValidity),
      attemptsLeft: _maxAttempts,
      resendsLeft: resendsLeft,
    );
    return (
      code: code,
      devCode: _isProd ? null : code,
      expiresInSeconds: _otpValidity.inSeconds,
    );
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
}
