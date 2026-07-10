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
    this.emailVerified = false,
    this.authProvider,
    this.googleSub,
    this.appleSub,
    this.address,
    this.verificationStatus = 'pending',
    this.rejectionReason,
    this.providerId,
    this.kycDocs = const [],
  });

  final String id;

  /// Salon CONTACT phone (required at registration — clients/Myweli must be
  /// able to call). Not an identity since the auth overhaul
  /// (docs/design/pro-auth-social.md).
  final String phoneNumber;
  final String businessName;
  final String businessType;
  final DateTime createdAt;
  String? name;

  /// Identity email (Google/Apple/email-OTP) — unique per account.
  String? email;
  bool emailVerified;
  String? authProvider; // google | apple | email | phone (legacy)
  String? googleSub;
  String? appleSub;
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
    'authProvider': authProvider,
    'address': address,
    'verificationStatus': verificationStatus,
    'rejectionReason': rejectionReason,
    'kycDocs': kycDocs,
    'createdAt': createdAt.toIso8601String(),
    'providerId': providerId,
  };
}

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
  /// Link a salon to an account (salon provisioning —
  /// docs/design/pro-salon-lifecycle.md §2). Idempotent.
  Future<void> linkProvider(String accountId, String providerId);

  // Phone OTP — dormant at launch (AUTH_METHODS gates the routes).
  Future<OtpRequestResult> requestOtp(String phoneNumber);
  Future<ProviderVerifyResult> verifyOtp(String phoneNumber, String code);

  // --- Auth overhaul (docs/design/pro-auth-social.md) ------------------------

  /// LOGIN-ONLY with verified identity-provider claims: match by [sub] → else
  /// by **verified** [email] (linking the sub). A salon is never auto-created
  /// (`provider_not_found`) — registration carries required business fields.
  Future<ProviderVerifyResult> loginWithSocial({
    required String provider,
    required String sub,
    String? email,
    bool emailVerified = false,
  });

  /// Email OTP, keyed on a provider-scoped store (a consumer with the same
  /// email must not collide).
  Future<OtpRequestResult> requestEmailOtp(String email);

  /// LOGIN-ONLY email verify: a correct code with no account returns
  /// `provider_not_found` **without consuming the code**, so the register
  /// screen can reuse it (it stays TTL/attempt-bounded).
  Future<ProviderVerifyResult> verifyEmailOtp(String email, String code);

  /// Registration = identity + business fields in one shot, returning a live
  /// session. The identity is proven EITHER by the route (Google/Apple token
  /// verification → [googleSub]/[appleSub]) OR by [emailCode] (checked here,
  /// atomically with creation) when [authProvider] is `email`.
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
  });

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
  @override
  Future<void> linkProvider(String accountId, String providerId) async {
    _byId[accountId]?.providerId = providerId;
  }

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
  final Map<String, ProviderAccount> _byEmail = {}; // lowercased email
  final Map<String, ProviderAccount> _bySocial = {}; // '<provider>:<sub>'
  final Map<String, _Otp> _otps = {};
  final Map<String, _Otp> _emailOtps = {}; // lowercased email

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
  Future<ProviderVerifyResult> loginWithSocial({
    required String provider,
    required String sub,
    String? email,
    bool emailVerified = false,
  }) async {
    final key = '$provider:$sub';
    final emailKey = email?.trim().toLowerCase();
    var account = _bySocial[key];
    if (account == null && emailKey != null && emailVerified) {
      // Link only on a verified email (threat T33/T35).
      account = _byEmail[emailKey];
      if (account != null) {
        _bySocial[key] = account;
        if (provider == 'google') account.googleSub = sub;
        if (provider == 'apple') account.appleSub = sub;
        account.emailVerified = true;
      }
    }
    if (account == null) {
      // Never auto-create a salon — registration carries business fields.
      return (
        ok: false,
        error: 'provider_not_found',
        provider: null,
        tokens: null,
      );
    }
    return (
      ok: true,
      error: null,
      provider: account,
      tokens: _issueInFamily(account.id, _newId('fam')),
    );
  }

  @override
  Future<OtpRequestResult> requestEmailOtp(String email) async {
    final key = email.trim().toLowerCase();
    final issued = _issueOtpIn(_emailOtps, key);
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
  Future<ProviderVerifyResult> verifyEmailOtp(String email, String code) async {
    final key = email.trim().toLowerCase();
    final error = _checkOtpIn(_emailOtps, key, code, consume: false);
    if (error != null) {
      return (ok: false, error: error, provider: null, tokens: null);
    }
    final account = _byEmail[key];
    if (account == null) {
      // Correct code, no salon → the register screen reuses this code.
      return (
        ok: false,
        error: 'provider_not_found',
        provider: null,
        tokens: null,
      );
    }
    _emailOtps.remove(key);
    account.emailVerified = true;
    return (
      ok: true,
      error: null,
      provider: account,
      tokens: _issueInFamily(account.id, _newId('fam')),
    );
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
    // Email-identity registrations prove inbox ownership here, atomically
    // with creation (Google/Apple were verified by the route).
    if (authProvider == 'email') {
      final error = _checkOtpIn(_emailOtps, emailKey, emailCode ?? '');
      if (error != null) {
        return (ok: false, error: error, provider: null, tokens: null);
      }
    }
    if (_byEmail.containsKey(emailKey) ||
        (googleSub != null && _bySocial.containsKey('google:$googleSub')) ||
        (appleSub != null && _bySocial.containsKey('apple:$appleSub'))) {
      return (
        ok: false,
        error: 'provider_exists',
        provider: null,
        tokens: null,
      );
    }
    final account = ProviderAccount(
      id: _newId('provider'),
      phoneNumber: phoneNumber,
      businessName: businessName,
      businessType: businessType,
      email: emailKey,
      emailVerified: true,
      authProvider: authProvider,
      googleSub: googleSub,
      appleSub: appleSub,
      address: address,
      providerId: providerId,
      createdAt: DateTime.now().toUtc(),
    );
    _byPhone[phoneNumber] = account;
    _byId[account.id] = account;
    _byEmail[emailKey] = account;
    if (googleSub != null) _bySocial['google:$googleSub'] = account;
    if (appleSub != null) _bySocial['apple:$appleSub'] = account;
    return (
      ok: true,
      error: null,
      provider: account,
      tokens: _issueInFamily(account.id, _newId('fam')),
    );
  }

  /// Check a code in [store]; null = valid. [consume] removes it on success —
  /// login keeps `consume: false` on the not-found path (see verifyEmailOtp).
  String? _checkOtpIn(
    Map<String, _Otp> store,
    String key,
    String code, {
    bool consume = true,
  }) {
    final otp = store[key];
    if (otp == null) return 'otp_none';
    if (DateTime.now().toUtc().isAfter(otp.expiresAt)) {
      store.remove(key);
      return 'otp_expired';
    }
    if (otp.attemptsLeft <= 0) return 'otp_locked';
    if (otp.codeHash != _tokens.hashToken(code)) {
      otp.attemptsLeft -= 1;
      return otp.attemptsLeft <= 0 ? 'otp_locked' : 'otp_invalid';
    }
    if (consume) store.remove(key);
    return null;
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
  ) => _issueOtpIn(_otps, phoneNumber);

  ({String? code, String? devCode, int expiresInSeconds})? _issueOtpIn(
    Map<String, _Otp> store,
    String key,
  ) {
    // An expired code (abandoned flow) doesn't count against the budget.
    final stored = store[key];
    final existing =
        stored != null && DateTime.now().toUtc().isAfter(stored.expiresAt)
        ? null
        : stored;
    if (existing != null && existing.resendsLeft <= 0) return null;
    final resendsLeft = existing == null
        ? _maxResends
        : existing.resendsLeft - 1;
    final code = (100000 + _random.nextInt(900000)).toString();
    store[key] = _Otp(
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
