import 'dart:math';

import 'tokens.dart';

/// An issued token pair + access expiry, returned to the client.
typedef TokenPair = ({
  String accessToken,
  String refreshToken,
  DateTime expiresAt,
});

/// Outcome of an OTP request. [code] is the plaintext for **delivery** (always
/// set on success, in-memory only — handed to the SMS/email sender, never
/// logged). [devCode] is the same value echoed to clients **only** outside
/// production.
typedef OtpRequestResult = ({
  bool ok,
  String? error,
  String? code,
  String? devCode,
  int expiresInSeconds,
});

/// Outcome of a login (OTP verification or social sign-in).
typedef OtpVerifyResult = ({
  bool ok,
  String? error,
  AuthUser? user,
  TokenPair? tokens,
});

/// Outcome of a refresh-token exchange.
typedef RefreshResult = ({bool ok, String? error, TokenPair? tokens});

/// Public-facing user fields. Mirrors the app's `User` DTO and the OpenAPI
/// `User` schema field-for-field. Since the auth overhaul
/// (docs/design/auth-social-email.md) the canonical identity is the verified
/// **email** (Google/Apple/email-OTP); [phoneNumber] is an optional contact
/// attribute, verified later via SMS ([phoneVerified]).
class AuthUser {
  AuthUser({
    required this.id,
    required this.createdAt,
    this.phoneNumber,
    this.phoneVerified = false,
    this.email,
    this.emailVerified = false,
    this.authProvider,
    this.name,
    this.avatarUrl,
    this.status = 'active',
  });

  final String id;
  final DateTime createdAt;
  String? phoneNumber;
  bool phoneVerified;
  String? email;
  bool emailVerified;
  String? authProvider; // google | apple | email | phone
  String? name;
  String? avatarUrl;
  String status; // active | banned (admin-controlled)

  Map<String, dynamic> toJson() => {
    'id': id,
    'phoneNumber': phoneNumber,
    'phoneVerified': phoneVerified,
    'name': name,
    'email': email,
    'authProvider': authProvider,
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
  // --- Phone OTP (dormant at launch — AUTH_METHODS gates the routes) --------
  Future<OtpRequestResult> requestOtp(String phoneNumber);
  Future<OtpVerifyResult> verifyOtp(String phoneNumber, String code);

  // --- Email OTP (docs/design/auth-social-email.md §7) ----------------------
  Future<OtpRequestResult> requestEmailOtp(String email);
  Future<OtpVerifyResult> verifyEmailOtp(String email, String code);

  /// Login with **verified** identity-provider claims (Google/Apple). Link
  /// rules (§4): match by provider [sub] → else by **verified** [email]
  /// (linking the sub) → else create. Never links on an unverified email
  /// (threat model T33).
  Future<OtpVerifyResult> loginWithSocial({
    required String provider,
    required String sub,
    String? email,
    bool emailVerified = false,
    String? name,
    String? avatarUrl,
  });

  Future<RefreshResult> refresh(String refreshToken);
  Future<AuthUser?> userById(String id);

  /// Update mutable profile fields. Empty string clears [email]/[phone];
  /// setting a new [phone] resets `phoneVerified` (contact until verified).
  Future<AuthUser?> updateUser(
    String id, {
    String? name,
    String? email,
    String? avatarUrl,
    String? phone,
  });
  Future<bool> deleteUser(String id);

  // --- Admin user management — design: docs/design/admin-console.md §12 ------
  /// Set a user's `status` (`active`/`banned`). Banned → login blocked. Returns
  /// the updated user, or null if absent.
  Future<AuthUser?> setStatus(String id, String status);

  /// Admin list, filterable by status + free-text (name/phone/email), paginated.
  Future<({List<AuthUser> items, int total})> listUsers({
    String? status,
    String? q,
    int page,
    int pageSize,
  });
}

/// In-memory implementation: per-phone/per-email OTP state (hashed code + an
/// attempt/resend budget), social-sub indexes, and refresh-token families
/// (hashed, rotating, reuse detection).
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
  final Map<String, AuthUser> _usersByEmail = {}; // lowercased email
  final Map<String, AuthUser> _usersBySocial = {}; // '<provider>:<sub>'
  final Map<String, _Otp> _otps = {}; // phone OTPs
  final Map<String, _Otp> _emailOtps = {}; // email OTPs (lowercased)
  final Map<String, _Refresh> _refreshByHash = {};

  /// Issue (or resend) an OTP for [phoneNumber]. Enforces the resend budget.
  @override
  Future<OtpRequestResult> requestOtp(String phoneNumber) async =>
      _requestOtpIn(_otps, phoneNumber);

  @override
  Future<OtpRequestResult> requestEmailOtp(String email) async =>
      _requestOtpIn(_emailOtps, email.trim().toLowerCase());

  OtpRequestResult _requestOtpIn(Map<String, _Otp> store, String key) {
    // An expired code (never verified, e.g. the user abandoned the flow)
    // doesn't count against the resend budget — treat it as absent.
    final stored = store[key];
    final existing = stored != null && DateTime.now().isAfter(stored.expiresAt)
        ? null
        : stored;
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
    store[key] = _Otp(
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

  /// Check a code against [store]; null means valid (and consumed).
  String? _checkOtp(Map<String, _Otp> store, String key, String code) {
    final otp = store[key];
    if (otp == null) return 'otp_none';
    if (DateTime.now().isAfter(otp.expiresAt)) {
      store.remove(key);
      return 'otp_expired';
    }
    if (otp.attemptsLeft <= 0) return 'otp_locked';
    if (otp.codeHash != _tokens.hashToken(code)) {
      otp.attemptsLeft -= 1;
      return otp.attemptsLeft <= 0 ? 'otp_locked' : 'otp_invalid';
    }
    store.remove(key);
    return null;
  }

  /// Verify a code; on success find-or-create the user and issue a token pair.
  @override
  Future<OtpVerifyResult> verifyOtp(String phoneNumber, String code) async {
    final error = _checkOtp(_otps, phoneNumber, code);
    if (error != null) {
      return (ok: false, error: error, user: null, tokens: null);
    }
    final user = _findOrCreateByPhone(phoneNumber);
    return _loginAs(user);
  }

  @override
  Future<OtpVerifyResult> verifyEmailOtp(String email, String code) async {
    final key = email.trim().toLowerCase();
    final error = _checkOtp(_emailOtps, key, code);
    if (error != null) {
      return (ok: false, error: error, user: null, tokens: null);
    }
    // Inbox ownership proven → the email is verified.
    final existing = _usersByEmail[key];
    final user =
        existing ??
        _addUser(
          AuthUser(
            id: _newId('user'),
            createdAt: DateTime.now().toUtc(),
            email: key,
            emailVerified: true,
            authProvider: 'email',
          ),
        );
    user.emailVerified = true;
    return _loginAs(user);
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
    final key = '$provider:$sub';
    final emailKey = email?.trim().toLowerCase();
    var user = _usersBySocial[key];
    if (user == null && emailKey != null && emailVerified) {
      // Link rule §4: a verified email joins this provider to the existing
      // account (never on an unverified email — T33).
      user = _usersByEmail[emailKey];
      if (user != null) {
        _usersBySocial[key] = user;
        user
          ..emailVerified = true
          ..name ??= name
          ..avatarUrl ??= avatarUrl;
      }
    }
    user ??= _addUser(
      AuthUser(
        id: _newId('user'),
        createdAt: DateTime.now().toUtc(),
        email: emailKey,
        emailVerified: emailVerified && emailKey != null,
        authProvider: provider,
        name: name,
        avatarUrl: avatarUrl,
      ),
      socialKey: key,
    );
    return _loginAs(user);
  }

  OtpVerifyResult _loginAs(AuthUser user) {
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
        final hay = '${u.name ?? ''} ${u.phoneNumber ?? ''} ${u.email ?? ''}'
            .toLowerCase();
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

  /// Update mutable profile fields. `email: ''`/`phone: ''` clear; null leaves.
  @override
  Future<AuthUser?> updateUser(
    String id, {
    String? name,
    String? email,
    String? avatarUrl,
    String? phone,
  }) async {
    final user = _usersById[id];
    if (user == null) return null;
    if (name != null && name.isNotEmpty) user.name = name;
    if (email != null) {
      final newEmail = email.isEmpty ? null : email.trim().toLowerCase();
      if (newEmail != user.email) {
        if (user.email != null) _usersByEmail.remove(user.email);
        user
          ..email = newEmail
          ..emailVerified = false;
        if (newEmail != null) _usersByEmail[newEmail] = user;
      }
    }
    if (avatarUrl != null) user.avatarUrl = avatarUrl;
    if (phone != null) {
      final newPhone = phone.isEmpty ? null : phone.trim();
      if (newPhone != user.phoneNumber) {
        if (user.phoneNumber != null) _usersByPhone.remove(user.phoneNumber);
        user
          ..phoneNumber = newPhone
          ..phoneVerified = false; // contact until verified (via SMS later)
        if (newPhone != null) _usersByPhone[newPhone] = user;
      }
    }
    return user;
  }

  @override
  Future<bool> deleteUser(String id) async {
    final user = _usersById.remove(id);
    if (user == null) return false;
    if (user.phoneNumber != null) {
      _usersByPhone.remove(user.phoneNumber);
      _otps.remove(user.phoneNumber);
    }
    if (user.email != null) {
      _usersByEmail.remove(user.email);
      _emailOtps.remove(user.email);
    }
    _usersBySocial.removeWhere((_, u) => u.id == id);
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

  AuthUser _findOrCreateByPhone(String phoneNumber) {
    final existing = _usersByPhone[phoneNumber];
    if (existing != null) {
      // OTP proved possession of the number.
      existing.phoneVerified = true;
      return existing;
    }
    return _addUser(
      AuthUser(
        id: _newId('user'),
        createdAt: DateTime.now().toUtc(),
        phoneNumber: phoneNumber,
        phoneVerified: true,
        authProvider: 'phone',
      ),
    );
  }

  AuthUser _addUser(AuthUser user, {String? socialKey}) {
    _usersById[user.id] = user;
    if (user.phoneNumber != null) _usersByPhone[user.phoneNumber!] = user;
    if (user.email != null) _usersByEmail[user.email!] = user;
    if (socialKey != null) _usersBySocial[socialKey] = user;
    return user;
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
}
