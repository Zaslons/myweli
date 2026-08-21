import 'package:bcrypt/bcrypt.dart';

import '../auth/auth_repository.dart' show RefreshResult, TokenPair;
import '../auth/login_throttle.dart';
import '../auth/tokens.dart';

/// An internal Myweli staff account. Email + password (bcrypt); seeded, never
/// self-signup. Design: docs/design/admin-console.md.
class AdminAccount {
  AdminAccount({required this.id, required this.email, required this.status});

  final String id;
  final String email;
  final String status; // active | disabled
}

typedef AdminLoginResult = ({bool ok, String? error, TokenPair? tokens});

typedef AdminPasswordChangeResult = ({bool ok, String? error});

/// The floor on a staff password, and the first one this codebase states.
///
/// The seeder has never had one: `ADMIN_PASSWORD` could be `x` and the admin
/// would exist. That is not fixed here — a floor applied at boot turns a weak
/// secret into a service that will not start — but every password set through
/// [AdminAuthRepository.changePassword] clears it.
const int kAdminPasswordMinLength = 12;

/// Admin authentication: email/password login → access JWT (role `admin`) + a
/// rotating opaque refresh token (hashed at rest; reuse revokes the family,
/// like the consumer/provider flows).
abstract interface class AdminAuthRepository {
  Future<AdminLoginResult> login(String email, String password);
  Future<RefreshResult> refresh(String refreshToken);
  Future<AdminAccount?> adminById(String id);

  /// Change [adminId]'s own password, proving possession of the current one.
  ///
  /// **The current password is required even though the caller already holds an
  /// admin token**, because otherwise a stolen access token — fifteen minutes
  /// of access — converts into permanent account takeover. With it, the thief
  /// must also know the password, which is the thing they were trying to get.
  ///
  /// On success every refresh token for the admin is revoked, so a leaked
  /// refresh token dies with the rotation. The caller's *access* token is not
  /// revoked and stays valid until it expires: access tokens are stateless JWTs
  /// and there is no denylist. A bounded (~15 min) residual, written down here
  /// rather than left to be discovered.
  ///
  /// Errors: `invalid_credentials`, `locked_out`, `throttle_unavailable`,
  /// `password_unchanged`, `weak_password`, `not_found`.
  /// Design: docs/design/backend-admin-password-change.md
  Future<AdminPasswordChangeResult> changePassword({
    required String adminId,
    required String currentPassword,
    required String newPassword,
  });

  /// **Bootstrap only — this does NOT rotate the password.**
  ///
  /// Creates the seed super-admin if no admin with [email] exists, and
  /// otherwise returns having done nothing. Changing `ADMIN_PASSWORD` and
  /// redeploying therefore has **no effect** on a database that already holds
  /// the admin, which is every database that has ever booted. Rotate through
  /// [changePassword]; `dependencies.dart` says so in the boot log when this
  /// call finds an existing row.
  ///
  /// Overwriting here instead would mean anyone who can set an environment
  /// variable owns the admin account, and a rollback to an old revision would
  /// silently restore an old password. Two tests pin the no-overwrite.
  ///
  /// Returns **true when it created the admin**, false when one already
  /// existed and the supplied password was therefore discarded. The caller
  /// says so in the boot log — a rotation that quietly fails is worse than one
  /// that errors, because the operator's belief updates and the system does not.
  Future<bool> ensureSeedAdmin({
    required String email,
    required String password,
  });
}

class _Refresh {
  _Refresh({required this.adminId, required this.familyId});
  final String adminId;
  final String familyId;
  bool rotated = false;
}

class InMemoryAdminAuthRepository implements AdminAuthRepository {
  InMemoryAdminAuthRepository({
    required TokenService tokens,
    LoginThrottle? throttle,
  }) : _tokens = tokens,
       _throttle = throttle ?? InMemoryLoginThrottle();

  final TokenService _tokens;
  final LoginThrottle _throttle;
  final Map<String, AdminAccount> _byId = {};
  final Map<String, String> _idByEmail = {};
  final Map<String, String> _hashByEmail = {};
  final Map<String, _Refresh> _refreshByHash = {};
  var _seq = 0;

  @override
  Future<bool> ensureSeedAdmin({
    required String email,
    required String password,
  }) async {
    final e = email.trim().toLowerCase();
    if (_idByEmail.containsKey(e)) return false;
    final id = 'admin_${_seq++}';
    _byId[id] = AdminAccount(id: id, email: e, status: 'active');
    _idByEmail[e] = id;
    _hashByEmail[e] = BCrypt.hashpw(password, BCrypt.gensalt());
    return true;
  }

  @override
  Future<AdminAccount?> adminById(String id) async => _byId[id];

  @override
  Future<AdminLoginResult> login(String email, String password) async {
    final e = adminThrottleKey(email);
    // **Fail closed.** A `null` means the store could not answer, and it gets a
    // code of its own — not `locked_out`, which would tell an operator at 2am
    // that someone guessed too often when the truth is that Postgres is sick.
    final locked = await throttleValue(() => _throttle.isLocked(e));
    if (locked == null) {
      return (ok: false, error: 'throttle_unavailable', tokens: null);
    }
    if (locked) {
      return (ok: false, error: 'locked_out', tokens: null);
    }
    final id = _idByEmail[e];
    final hash = _hashByEmail[e];
    final account = id == null ? null : _byId[id];
    if (id == null ||
        hash == null ||
        account == null ||
        account.status != 'active' ||
        !BCrypt.checkpw(password, hash)) {
      // Also fail closed: a failure that bcrypt rejected but the store did
      // not COUNT is a repeatable free guess, which is the whole attack.
      if (!await throttleOk(() => _throttle.recordFailure(e))) {
        return (ok: false, error: 'throttle_unavailable', tokens: null);
      }
      return (ok: false, error: 'invalid_credentials', tokens: null);
    }
    // **The one exception, and the asymmetry is the point: the operations that
    // bound the ATTACKER fail closed; the one that forgives the USER fails
    // open.** If this throws the count simply is not cleared — strictly
    // stricter, never looser — and 503-ing someone who just proved they hold
    // the password would be a self-inflicted outage with no security benefit.
    await throttleOk(() => _throttle.reset(e));
    return (
      ok: true,
      error: null,
      tokens: _issueInFamily(id, _tokens.generateRefreshToken()),
    );
  }

  @override
  Future<AdminPasswordChangeResult> changePassword({
    required String adminId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final account = _byId[adminId];
    if (account == null) return (ok: false, error: 'not_found');
    final e = adminThrottleKey(account.email);
    // Same key as `login`, deliberately: a key of its own would hand a stolen
    // access token a FRESH five-guess budget that login's lockout never sees.
    final locked = await throttleValue(() => _throttle.isLocked(e));
    if (locked == null) return (ok: false, error: 'throttle_unavailable');
    if (locked) return (ok: false, error: 'locked_out');
    final hash = _hashByEmail[e];
    if (hash == null || !BCrypt.checkpw(currentPassword, hash)) {
      if (!await throttleOk(() => _throttle.recordFailure(e))) {
        return (ok: false, error: 'throttle_unavailable');
      }
      return (ok: false, error: 'invalid_credentials');
    }
    if (newPassword.length < kAdminPasswordMinLength) {
      return (ok: false, error: 'weak_password');
    }
    if (BCrypt.checkpw(newPassword, hash)) {
      return (ok: false, error: 'password_unchanged');
    }
    _hashByEmail[e] = BCrypt.hashpw(newPassword, BCrypt.gensalt());
    _refreshByHash.removeWhere((_, r) => r.adminId == adminId);
    await throttleOk(() => _throttle.reset(e));
    return (ok: true, error: null);
  }

  @override
  Future<RefreshResult> refresh(String refreshToken) async {
    final rec = _refreshByHash[_tokens.hashToken(refreshToken)];
    if (rec == null) {
      return (ok: false, error: 'refresh_invalid', tokens: null);
    }
    if (rec.rotated) {
      _refreshByHash.removeWhere((_, r) => r.familyId == rec.familyId);
      return (ok: false, error: 'refresh_reused', tokens: null);
    }
    rec.rotated = true;
    return (
      ok: true,
      error: null,
      tokens: _issueInFamily(rec.adminId, rec.familyId),
    );
  }

  TokenPair _issueInFamily(String adminId, String familyId) {
    final access = _tokens.issueAccessToken(subject: adminId, role: 'admin');
    final refresh = _tokens.generateRefreshToken();
    _refreshByHash[_tokens.hashToken(refresh)] = _Refresh(
      adminId: adminId,
      familyId: familyId,
    );
    return (
      accessToken: access.token,
      refreshToken: refresh,
      expiresAt: access.expiresAt,
    );
  }
}
