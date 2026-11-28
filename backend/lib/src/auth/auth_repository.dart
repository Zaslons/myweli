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

/// Outcome of [AuthRepository.changeEmail] (B16.3,
/// docs/design/account-email-change.md §3.1, §5.2). On success [user] holds
/// the address, proven, and [previousEmail] is the address it replaced **if
/// that one was proven** (the notice goes there, Q6); null otherwise.
///
/// [error] is one of: the new address's code refused (`otp_invalid`,
/// `otp_expired`, `otp_none`, `otp_locked`); the current address's code
/// refused or missing when required (the same four, prefixed `current_`);
/// `email_unchanged` (it is already this account's proven address);
/// `email_taken` (another account proved it); `account_suspended`;
/// `not_found`.
typedef EmailChangeResult = ({
  bool ok,
  String? error,
  AuthUser? user,
  String? previousEmail,
});

EmailChangeResult emailChangeRefused(String error) =>
    (ok: false, error: error, user: null, previousEmail: null);

/// What one refresh-token exchange did — the same four answers on every
/// principal (consumer, provider, admin) and in every store. Design:
/// docs/design/backend-refresh-rotation-atomic.md §5.
///
/// It is logged by the refresh routes (§6) and never sent: `ok` and `error`
/// keep their meaning, so the responses — and the API contract — are unchanged.
enum RefreshOutcome {
  /// This exchange claimed the token. Exactly one exchange per token can ever
  /// get here, however many arrive at once.
  rotated,

  /// The token was already rotated, within [kRefreshReuseGrace]: a concurrent
  /// or retried legitimate use (two calls 401 together on a cold start, a
  /// response lost on the way back). Answered with a SIBLING pair in the same
  /// family; nothing is revoked.
  grace,

  /// The token was rotated longer ago than the grace — or before the grace
  /// existed. Reuse: the whole family is revoked → `refresh_reused`.
  reused,

  /// No such token: never issued, or its family is already gone →
  /// `refresh_invalid`.
  invalid,
}

/// How long after its rotation a refresh token is still answered with a
/// sibling instead of revoking its family.
///
/// **The trade, stated** (design §3): a thief who replays a stolen token within
/// this window of the owner's own refresh gets a sibling instead of tripping
/// revocation — the standard "reuse interval" (Auth0, Okta). In return no
/// client race signs a user out. Reuse after the window is detected exactly as
/// before, and every acceptance inside it is logged (`outcome=grace`).
///
/// ONE constant for the three Postgres repositories (passed into the SQL as a
/// parameter, compared on the database clock) and the three in-memory twins.
const Duration kRefreshReuseGrace = Duration(seconds: 30);

/// Whether a token rotated at [rotatedAt] is still inside the grace at [now] —
/// inclusive at the boundary, as the SQL's `rotated_at >= now() - grace` is.
/// The in-memory twins' copy of that comparison, kept in one place.
bool withinRefreshGrace(DateTime rotatedAt, DateTime now) =>
    !now.isAfter(rotatedAt.add(kRefreshReuseGrace));

/// Outcome of a refresh-token exchange. [ok]/[error] are what the client sees;
/// [outcome] is what happened, for the log line.
typedef RefreshResult = ({
  bool ok,
  String? error,
  TokenPair? tokens,
  RefreshOutcome outcome,
});

/// The four result shapes, one per outcome, so no implementation can pair an
/// outcome with the wrong `ok`/`error`.
RefreshResult refreshRotated(TokenPair tokens) =>
    (ok: true, error: null, tokens: tokens, outcome: RefreshOutcome.rotated);

RefreshResult refreshGrace(TokenPair tokens) =>
    (ok: true, error: null, tokens: tokens, outcome: RefreshOutcome.grace);

const RefreshResult refreshInvalid = (
  ok: false,
  error: 'refresh_invalid',
  tokens: null,
  outcome: RefreshOutcome.invalid,
);

const RefreshResult refreshReused = (
  ok: false,
  error: 'refresh_reused',
  tokens: null,
  outcome: RefreshOutcome.reused,
);

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
    'emailVerified': emailVerified,
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

  /// When this token was rotated; null while it is still unused.
  DateTime? rotatedAt;
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

  /// Give back one resend spent on a message we ourselves declined to send.
  ///
  /// The budget refuses AFTER `requestEmailOtp` has already decremented the
  /// allowance, so without this a global ceiling becomes a per-user lockout
  /// that outlasts the hour causing it — the user burns all four resends on
  /// mail that never left, then gets a hard `otp_resend_limit` that survives
  /// the window reset. Clamped at the maximum and scoped to an unexpired row,
  /// so it can neither inflate an allowance nor revive a stale one.
  ///
  /// Deliberately NOT called for a provider failure: that was a real delivery
  /// attempt. Design: docs/design/backend-email-send-budget.md §9.
  Future<void> refundEmailOtpResend(String email);
  Future<OtpVerifyResult> verifyEmailOtp(String email, String code);

  /// Login with identity-provider claims (Google/Apple). The rules
  /// (docs/design/account-email-change.md §5.1, B16.3):
  /// 1. by provider [sub]; an account found so, holding [email] unproven,
  ///    has it marked proven when the provider verified it;
  /// 2. else by a **verified** [email] that an account has **proven**: the sub
  ///    links to it when its own sub for this provider is empty, and is
  ///    **never replaced** otherwise (a new account without the address);
  /// 3. else create, taking a verified [email] from any account holding it
  ///    unproven. An unverified [email] is stored only when no account holds
  ///    it, and never takes anything (threat model T33).
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

  /// Update mutable profile fields. Empty string clears [phone]; setting a
  /// new [phone] resets `phoneVerified` (contact until verified).
  ///
  /// **The address is not here** (B16.3): it changes only through
  /// [changeEmail], proven. A profile edit that could write it stored an
  /// address nobody had proven, and every sign-in found an account by it.
  Future<AuthUser?> updateUser(
    String id, {
    String? name,
    String? avatarUrl,
    String? phone,
  });
  Future<bool> deleteUser(String id);

  // --- An account's e-mail — docs/design/account-email-change.md (B16.3) --
  /// Whether changing [userId]'s address also takes a code sent to its
  /// current one (decision 265): the account has a proven address and no
  /// Google or Apple link, so that address is its only way in.
  Future<bool> emailIsOnlySignIn(String userId);

  /// Proves [email] by [code] (and the current address by [currentCode] when
  /// [emailIsOnlySignIn]), then makes it [userId]'s address, proven, taking
  /// it from any account holding it unproven. Atomic: nothing is consumed
  /// unless the change is made, and on `email_taken` the code stays valid
  /// for its owner's sign-in (§3.1, §5.3).
  Future<EmailChangeResult> changeEmail(
    String userId,
    String email,
    String code, {
    String? currentCode,
  });

  // --- Admin user management — design: docs/design/admin-console.md §12 ------
  /// Set a user's `status` (`active`/`banned`). Banned → login blocked. Returns
  /// the updated user, or null if absent.
  Future<AuthUser?> setStatus(String id, String status);

  /// Admin list, filterable by status + free-text, paginated. One rule on
  /// both twins (docs/design/auth-store-twins.md §5.3, decision 286): newest
  /// first, a tie broken by the id in byte order, both descending; [q]
  /// matches name, phone or e-mail **each on its own**, case ignored, with
  /// `%`, `_`, `\` and accents taken as typed. Pinned by
  /// `test/auth/user_list_contract.dart` on both twins.
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
    required bool echoDevCode,
    Duration otpValidity = const Duration(minutes: 5),
    int maxAttempts = 5,
    int maxResends = 3,
    DateTime Function()? clock,
  }) : _tokens = tokens,
       _echoDevCode = echoDevCode,
       _otpValidity = otpValidity,
       _maxAttempts = maxAttempts,
       _maxResends = maxResends,
       _clock = clock ?? DateTime.now;

  final TokenService _tokens;
  final bool _echoDevCode;
  final Duration _otpValidity;
  final int _maxAttempts;
  final int _maxResends;
  final Random _random = Random.secure();

  /// Drives the refresh reuse grace only — the Postgres twin reads the
  /// database's `now()` there, and a test must step past 30 s without
  /// sleeping. OTP expiry still reads the wall clock.
  final DateTime Function() _clock;

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

  @override
  Future<void> refundEmailOtpResend(String email) async {
    final stored = _emailOtps[email.trim().toLowerCase()];
    if (stored == null) return;
    if (DateTime.now().isAfter(stored.expiresAt)) return;
    if (stored.resendsLeft >= _maxResends) return;
    stored.resendsLeft += 1;
  }

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
      devCode: _echoDevCode ? code : null,
      expiresInSeconds: _otpValidity.inSeconds,
    );
  }

  /// Check a code against [store]; null means valid — and consumed, unless
  /// [consume] is false (the e-mail change checks both codes before it
  /// consumes either, §5.3). A refusal is accounted either way.
  String? _checkOtp(
    Map<String, _Otp> store,
    String key,
    String code, {
    bool consume = true,
  }) {
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
    if (consume) store.remove(key);
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
    // B16.3 §5.1: the code proves the inbox, so the address reaches only an
    // account that PROVED it; one holding it unproven loses it to the prover.
    final holder = _usersByEmail[key];
    if (holder != null && holder.emailVerified) return _loginAs(holder);
    if (holder != null) _take(holder);
    return _loginAs(
      _addUser(
        AuthUser(
          id: _newId('user'),
          createdAt: DateTime.now().toUtc(),
          email: key,
          emailVerified: true,
          authProvider: 'email',
        ),
      ),
    );
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
    final proves = emailKey != null && emailVerified;
    // 1. By sub. Its own unproven address, asserted by the provider, is
    //    proven now; it takes nothing from anyone else (B16.3 §5.1).
    final bySub = _usersBySocial[key];
    if (bySub != null) {
      if (proves && bySub.email == emailKey) bySub.emailVerified = true;
      return _loginAs(bySub);
    }
    final holder = emailKey == null ? null : _usersByEmail[emailKey];
    AuthUser create({required String? address, required bool proven}) =>
        _addUser(
          AuthUser(
            id: _newId('user'),
            createdAt: DateTime.now().toUtc(),
            email: address,
            emailVerified: proven,
            authProvider: provider,
            name: name,
            avatarUrl: avatarUrl,
          ),
          socialKey: key,
        );
    if (!proves) {
      // Kept out: an unverified address is stored only when nobody holds it,
      // and takes nothing (T33).
      return _loginAs(
        create(address: holder == null ? emailKey : null, proven: false),
      );
    }
    // 2. A proven holder: link when its sub for this provider is empty; a
    //    sub already there is NEVER replaced (the account it reaches stays
    //    its holder's) — this sign-in gets an account of its own.
    if (holder != null && holder.emailVerified) {
      if (_linkedTo(holder.id, provider)) {
        return _loginAs(create(address: null, proven: false));
      }
      _usersBySocial[key] = holder;
      holder
        ..name ??= name
        ..avatarUrl ??= avatarUrl;
      return _loginAs(holder);
    }
    // 3. Take it from an unproven holder, then create.
    if (holder != null) _take(holder);
    return _loginAs(create(address: emailKey, proven: true));
  }

  /// Whether account [id] already has a sub for [provider].
  bool _linkedTo(String id, String provider) => _usersBySocial.entries.any(
    (e) => e.value.id == id && e.key.startsWith('$provider:'),
  );

  /// The holder of an address it never proved loses it (B16.3 §5.1). Its
  /// account, sessions and other sign-ins stay.
  void _take(AuthUser holder) {
    _usersByEmail.remove(holder.email);
    holder
      ..email = null
      ..emailVerified = false;
  }

  /// **A test seam, not a writer:** puts [email] on account [id] unproven,
  /// the state a profile edit left before B16.3 — and the state such accounts
  /// keep in production — so the contract can set a trap on this twin as it
  /// does on Postgres by SQL. No route reaches it.
  void plantUnprovenEmailForTest(String id, String email) {
    final user = _usersById[id]!;
    if (user.email != null) _usersByEmail.remove(user.email);
    final key = email.trim().toLowerCase();
    user
      ..email = key
      ..emailVerified = false;
    _usersByEmail[key] = user;
  }

  /// **A test seam, not a writer:** gives account [id] the creation time
  /// [at], so the user list's contract can make two accounts tie on it, as
  /// it does on Postgres by SQL (docs/design/auth-store-twins.md §5.3). The
  /// account is rebuilt (`createdAt` is final) and every index repointed. No
  /// route reaches it.
  void plantCreatedAtForTest(String id, DateTime at) {
    final old = _usersById[id]!;
    final copy = AuthUser(
      id: old.id,
      createdAt: at,
      phoneNumber: old.phoneNumber,
      phoneVerified: old.phoneVerified,
      email: old.email,
      emailVerified: old.emailVerified,
      authProvider: old.authProvider,
      name: old.name,
      avatarUrl: old.avatarUrl,
      status: old.status,
    );
    for (final index in [
      _usersById,
      _usersByPhone,
      _usersByEmail,
      _usersBySocial,
    ]) {
      for (final key in [
        for (final e in index.entries)
          if (identical(e.value, old)) e.key,
      ]) {
        index[key] = copy;
      }
    }
  }

  @override
  Future<bool> emailIsOnlySignIn(String userId) async {
    final user = _usersById[userId];
    return user != null &&
        user.email != null &&
        user.emailVerified &&
        !_linkedTo(userId, 'google') &&
        !_linkedTo(userId, 'apple');
  }

  /// No `await` between the reads and the writes: atomic by construction on
  /// the one isolate, as Postgres's transaction is (§5.3).
  @override
  Future<EmailChangeResult> changeEmail(
    String userId,
    String email,
    String code, {
    String? currentCode,
  }) async {
    final user = _usersById[userId];
    if (user == null) return emailChangeRefused('not_found');
    if (user.status == 'banned') return emailChangeRefused('account_suspended');
    final key = email.trim().toLowerCase();
    if (user.email == key && user.emailVerified) {
      return emailChangeRefused('email_unchanged');
    }
    // The new address's code FIRST, so « taken » is said only to whoever
    // proves the inbox (decision 262); checked, not yet consumed.
    final refused = _checkOtp(_emailOtps, key, code, consume: false);
    if (refused != null) return emailChangeRefused(refused);
    final holder = _usersByEmail[key];
    if (holder != null && holder.id != userId && holder.emailVerified) {
      // Nothing consumed: the code still signs its owner in (§3.1).
      return emailChangeRefused('email_taken');
    }
    final current = user.email;
    final needsCurrent =
        current != null &&
        user.emailVerified &&
        !_linkedTo(userId, 'google') &&
        !_linkedTo(userId, 'apple');
    if (needsCurrent) {
      if (currentCode == null) return emailChangeRefused('current_otp_none');
      final refusedCurrent = _checkOtp(
        _emailOtps,
        current,
        currentCode,
        consume: false,
      );
      if (refusedCurrent != null) {
        return emailChangeRefused('current_$refusedCurrent');
      }
      _emailOtps.remove(current);
    }
    _emailOtps.remove(key);
    if (holder != null && holder.id != userId) _take(holder);
    final previous = user.emailVerified ? current : null;
    if (current != null) _usersByEmail.remove(current);
    user
      ..email = key
      ..emailVerified = true;
    _usersByEmail[key] = user;
    return (ok: true, error: null, user: user, previousEmail: previous);
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

  /// Exchange a refresh token for a fresh pair, with the Postgres twin's
  /// semantics (docs/design/backend-refresh-rotation-atomic.md §5): the first
  /// exchange rotates it; another within [kRefreshReuseGrace] of that gets a
  /// sibling in the same family; after the grace it is reuse and the whole
  /// family is revoked. No `await` between the read and the write, so the
  /// claim is atomic by construction on the one isolate.
  @override
  Future<RefreshResult> refresh(String refreshToken) async {
    final rec = _refreshByHash[_tokens.hashToken(refreshToken)];
    if (rec == null) return refreshInvalid;
    final rotatedAt = rec.rotatedAt;
    if (rotatedAt == null) {
      rec.rotatedAt = _clock();
      return refreshRotated(_issueInFamily(rec.userId, rec.role, rec.familyId));
    }
    if (withinRefreshGrace(rotatedAt, _clock())) {
      return refreshGrace(_issueInFamily(rec.userId, rec.role, rec.familyId));
    }
    _revokeFamily(rec.familyId);
    return refreshReused;
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
    final needle = q?.toLowerCase();
    final all =
        _usersById.values.where((u) {
          if (status != null && status.isNotEmpty && u.status != status) {
            return false;
          }
          if (needle != null && needle.isNotEmpty) {
            // Each field on its own, as Postgres's three ILIKEs
            // (docs/design/auth-store-twins.md §5.3).
            return [
              u.name,
              u.phoneNumber,
              u.email,
            ].any((f) => f != null && f.toLowerCase().contains(needle));
          }
          return true;
        }).toList()..sort((a, b) {
          final byTime = b.createdAt.compareTo(a.createdAt);
          return byTime != 0 ? byTime : b.id.compareTo(a.id);
        });
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <AuthUser>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return (items: items, total: all.length);
  }

  /// Update mutable profile fields. `phone: ''` clears; null leaves.
  @override
  Future<AuthUser?> updateUser(
    String id, {
    String? name,
    String? avatarUrl,
    String? phone,
  }) async {
    final user = _usersById[id];
    if (user == null) return null;
    if (name != null && name.isNotEmpty) user.name = name;
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
