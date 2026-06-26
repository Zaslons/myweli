import 'dart:math';

import 'tokens.dart';

/// An issued token pair + access expiry, returned to the client.
typedef TokenPair = ({
  String accessToken,
  String refreshToken,
  DateTime expiresAt,
});

/// Outcome of an OTP request. [code] is the plaintext for **delivery** (always
/// set on success, in-memory only — handed to the SMS sender, never logged).
/// [devCode] is the same value echoed to clients **only** outside production.
typedef OtpRequestResult = ({
  bool ok,
  String? error,
  String? code,
  String? devCode,
  int expiresInSeconds,
});

/// Outcome of an OTP verification.
typedef OtpVerifyResult = ({
  bool ok,
  String? error,
  AuthUser? user,
  TokenPair? tokens,
});

/// Outcome of a refresh-token exchange.
typedef RefreshResult = ({bool ok, String? error, TokenPair? tokens});

/// Public-facing user fields. Mirrors the app's `User` DTO and the OpenAPI
/// `User` schema field-for-field.
class AuthUser {
  AuthUser({
    required this.id,
    required this.phoneNumber,
    required this.createdAt,
    this.name,
    this.email,
    this.avatarUrl,
    this.status = 'active',
  });

  final String id;
  final String phoneNumber;
  final DateTime createdAt;
  String? name;
  String? email;
  String? avatarUrl;
  String status; // active | banned (admin-controlled)

  Map<String, dynamic> toJson() => {
    'id': id,
    'phoneNumber': phoneNumber,
    'name': name,
    'email': email,
    'avatarUrl': avatarUrl,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
  };
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
  _Refresh({required this.userId, required this.role, required this.familyId});

  final String userId;
  final String role;
  final String familyId;
  bool rotated = false;
}

/// Auth storage + security logic behind the auth routes (docs/BACKEND.md §3).
/// In-memory now; a Postgres impl (B3b) satisfies the same interface, so the
/// routes are unchanged when the store swaps.
abstract interface class AuthRepository {
  Future<OtpRequestResult> requestOtp(String phoneNumber);
  Future<OtpVerifyResult> verifyOtp(String phoneNumber, String code);
  Future<RefreshResult> refresh(String refreshToken);
  Future<AuthUser?> userById(String id);
  Future<AuthUser?> updateUser(
    String id, {
    String? name,
    String? email,
    String? avatarUrl,
  });
  Future<bool> deleteUser(String id);

  // --- Admin user management — design: docs/design/admin-console.md §12 ------
  /// Set a user's `status` (`active`/`banned`). Banned → login blocked. Returns
  /// the updated user, or null if absent.
  Future<AuthUser?> setStatus(String id, String status);

  /// Admin list, filterable by status + free-text (name/phone), paginated.
  Future<({List<AuthUser> items, int total})> listUsers({
    String? status,
    String? q,
    int page,
    int pageSize,
  });
}

/// In-memory implementation: per-phone OTP state (hashed code + an attempt/
/// resend budget) and refresh-token families (hashed, rotating, reuse
/// detection).
class InMemoryAuthRepository implements AuthRepository {
  InMemoryAuthRepository({
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

  final Map<String, AuthUser> _usersByPhone = {};
  final Map<String, AuthUser> _usersById = {};
  final Map<String, _Otp> _otps = {};
  final Map<String, _Refresh> _refreshByHash = {};

  /// Issue (or resend) an OTP for [phoneNumber]. Enforces the resend budget.
  @override
  Future<OtpRequestResult> requestOtp(String phoneNumber) async {
    final existing = _otps[phoneNumber];
    if (existing != null && existing.resendsLeft <= 0) {
      return (
        ok: false,
        error: 'otp_resend_limit',
        code: null,
        devCode: null,
        expiresInSeconds: 0,
      );
    }
    final resendsLeft = existing == null
        ? _maxResends
        : existing.resendsLeft - 1;
    final code = (100000 + _random.nextInt(900000)).toString(); // 6 digits
    _otps[phoneNumber] = _Otp(
      codeHash: _tokens.hashToken(code),
      expiresAt: DateTime.now().add(_otpValidity),
      attemptsLeft: _maxAttempts,
      resendsLeft: resendsLeft,
    );
    return (
      ok: true,
      error: null,
      code: code,
      devCode: _isProd ? null : code,
      expiresInSeconds: _otpValidity.inSeconds,
    );
  }

  /// Verify a code; on success find-or-create the user and issue a token pair.
  @override
  Future<OtpVerifyResult> verifyOtp(String phoneNumber, String code) async {
    final otp = _otps[phoneNumber];
    if (otp == null) {
      return (ok: false, error: 'otp_none', user: null, tokens: null);
    }
    if (DateTime.now().isAfter(otp.expiresAt)) {
      _otps.remove(phoneNumber);
      return (ok: false, error: 'otp_expired', user: null, tokens: null);
    }
    if (otp.attemptsLeft <= 0) {
      return (ok: false, error: 'otp_locked', user: null, tokens: null);
    }
    if (otp.codeHash != _tokens.hashToken(code)) {
      otp.attemptsLeft -= 1;
      final error = otp.attemptsLeft <= 0 ? 'otp_locked' : 'otp_invalid';
      return (ok: false, error: error, user: null, tokens: null);
    }
    _otps.remove(phoneNumber);
    final user = _findOrCreateUser(phoneNumber);
    if (user.status == 'banned') {
      return (ok: false, error: 'account_suspended', user: null, tokens: null);
    }
    return (
      ok: true,
      error: null,
      user: user,
      tokens: _issueInFamily(user.id, 'user', _newId('fam')),
    );
  }

  /// Exchange a refresh token for a fresh pair. Rotates the token; presenting
  /// an already-rotated token is treated as theft and revokes the whole family.
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
      tokens: _issueInFamily(rec.userId, rec.role, rec.familyId),
    );
  }

  @override
  Future<AuthUser?> userById(String id) async => _usersById[id];

  @override
  Future<AuthUser?> setStatus(String id, String status) async {
    final user = _usersById[id];
    if (user == null) return null;
    user.status = status;
    return user;
  }

  @override
  Future<({List<AuthUser> items, int total})> listUsers({
    String? status,
    String? q,
    int page = 1,
    int pageSize = 20,
  }) async {
    final all = _usersById.values.where((u) {
      if (status != null && status.isNotEmpty && u.status != status) {
        return false;
      }
      if (q != null && q.isNotEmpty) {
        final hay = '${u.name ?? ''} ${u.phoneNumber}'.toLowerCase();
        if (!hay.contains(q.toLowerCase())) return false;
      }
      return true;
    }).toList();
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <AuthUser>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return (items: items, total: all.length);
  }

  /// Update mutable profile fields. `email: ''` clears it; null leaves it.
  @override
  Future<AuthUser?> updateUser(
    String id, {
    String? name,
    String? email,
    String? avatarUrl,
  }) async {
    final user = _usersById[id];
    if (user == null) return null;
    if (name != null && name.isNotEmpty) user.name = name;
    if (email != null) user.email = email.isEmpty ? null : email;
    if (avatarUrl != null) user.avatarUrl = avatarUrl;
    return user;
  }

  @override
  Future<bool> deleteUser(String id) async {
    final user = _usersById.remove(id);
    if (user == null) return false;
    _usersByPhone.remove(user.phoneNumber);
    _otps.remove(user.phoneNumber);
    _refreshByHash.removeWhere((_, r) => r.userId == id);
    return true;
  }

  TokenPair _issueInFamily(String userId, String role, String familyId) {
    final access = _tokens.issueAccessToken(subject: userId, role: role);
    final refresh = _tokens.generateRefreshToken();
    _refreshByHash[_tokens.hashToken(refresh)] = _Refresh(
      userId: userId,
      role: role,
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

  AuthUser _findOrCreateUser(String phoneNumber) {
    final existing = _usersByPhone[phoneNumber];
    if (existing != null) return existing;
    final user = AuthUser(
      id: _newId('user'),
      phoneNumber: phoneNumber,
      createdAt: DateTime.now().toUtc(),
    );
    _usersByPhone[phoneNumber] = user;
    _usersById[user.id] = user;
    return user;
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
}
