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

/// Admin authentication: email/password login → access JWT (role `admin`) + a
/// rotating opaque refresh token (hashed at rest; reuse revokes the family,
/// like the consumer/provider flows).
abstract interface class AdminAuthRepository {
  Future<AdminLoginResult> login(String email, String password);
  Future<RefreshResult> refresh(String refreshToken);
  Future<AdminAccount?> adminById(String id);

  /// Idempotent: create the seed super-admin if no admin with [email] exists.
  Future<void> ensureSeedAdmin({
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
       _throttle = throttle ?? LoginThrottle();

  final TokenService _tokens;
  final LoginThrottle _throttle;
  final Map<String, AdminAccount> _byId = {};
  final Map<String, String> _idByEmail = {};
  final Map<String, String> _hashByEmail = {};
  final Map<String, _Refresh> _refreshByHash = {};
  var _seq = 0;

  @override
  Future<void> ensureSeedAdmin({
    required String email,
    required String password,
  }) async {
    final e = email.trim().toLowerCase();
    if (_idByEmail.containsKey(e)) return;
    final id = 'admin_${_seq++}';
    _byId[id] = AdminAccount(id: id, email: e, status: 'active');
    _idByEmail[e] = id;
    _hashByEmail[e] = BCrypt.hashpw(password, BCrypt.gensalt());
  }

  @override
  Future<AdminAccount?> adminById(String id) async => _byId[id];

  @override
  Future<AdminLoginResult> login(String email, String password) async {
    final e = email.trim().toLowerCase();
    if (_throttle.isLocked(e)) {
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
      _throttle.recordFailure(e);
      return (ok: false, error: 'invalid_credentials', tokens: null);
    }
    _throttle.reset(e);
    return (
      ok: true,
      error: null,
      tokens: _issueInFamily(id, _tokens.generateRefreshToken()),
    );
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
