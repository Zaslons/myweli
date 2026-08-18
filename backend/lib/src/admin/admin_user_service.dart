import '../appointments/appointment_repository.dart';
import '../auth/auth_repository.dart';
import '../privacy/user_erasure_service.dart';
import 'admin_kyc_service.dart' show AdminResult;
import 'audit_log_repository.dart';

/// Admin consumer management (design: docs/design/admin-console.md §12). List /
/// view users, ban/unban (banned ⇒ login blocked) — every mutation audited.
/// Support views are read-only (no act-as).
class AdminUserService {
  AdminUserService(this._auth, this._appointments, this._audit, this._erasure);

  final AuthRepository _auth;
  final AppointmentRepository _appointments;
  final AuditLogRepository _audit;
  final UserErasureService _erasure;

  Future<AdminResult> list({
    String? status,
    String? q,
    int page = 1,
    int pageSize = 20,
  }) async {
    final r = await _auth.listUsers(
      status: status,
      q: q,
      page: page,
      pageSize: pageSize,
    );
    return (
      ok: true,
      error: null,
      data: {
        'items': [for (final u in r.items) u.toJson()],
        'page': page,
        'pageSize': pageSize,
        'total': r.total,
      },
    );
  }

  /// Read-only support view: the user + their recent bookings.
  Future<AdminResult> detail(String id) async {
    final u = await _auth.userById(id);
    if (u == null) return (ok: false, error: 'not_found', data: null);
    final appts = await _appointments.listForUser(id);
    return (
      ok: true,
      error: null,
      data: {...u.toJson(), 'recentAppointments': appts.take(20).toList()},
    );
  }

  /// Erase a consumer account on an admin's authority.
  ///
  /// **Delegates to the same [UserErasureService] as `DELETE /me`** rather than
  /// re-implementing anything. That service exists because the hand-rolled
  /// version got it wrong — it deleted the `users` row and the OTP rows, and
  /// every other table keys on `user_id` as a plain `text` column with no
  /// foreign key, so reviews kept the display name, appointments kept name and
  /// phone, and a deleted user's phone **kept receiving push**. A second
  /// implementation here would be a second chance to make exactly that mistake.
  ///
  /// **Why an admin path exists at all, when users can delete themselves.** An
  /// erasure request arrives by e-mail, from someone who may no longer be able
  /// to sign in — a lost phone, a closed mailbox, a changed number. The privacy
  /// policy promises erasure to that person too, and until now the only way to
  /// honour it was raw SQL against production, which is precisely how the
  /// cascade got missed the first time.
  ///
  /// **Not the same act as [ban].** Banning blocks login and is reversible;
  /// this removes the person and is not. Audited as `user.erase`, and the audit
  /// row is written **after** the cascade succeeds — a log line claiming an
  /// erasure that did not happen is worse than no log line.
  Future<AdminResult> erase(String adminId, String id, Object? reason) async {
    final r = await _erasure.eraseUser(id);
    if (!r.ok) return (ok: false, error: r.error, data: null);
    await _audit.append((
      actorAdminId: adminId,
      action: 'user.erase',
      targetType: 'user',
      targetId: id,
      reason: reason is String && reason.trim().isNotEmpty
          ? reason.trim()
          : null,
      // The identity is gone, so the audit row is the only remaining record
      // that it ever existed. It deliberately carries no PII — the id alone,
      // which is what makes the row a tombstone rather than a copy.
      metadata: const {},
    ));
    return (ok: true, error: null, data: null);
  }

  Future<AdminResult> ban(String adminId, String id, Object? reason) =>
      _setStatus(adminId, id, 'banned', 'user.ban', reason);

  Future<AdminResult> unban(String adminId, String id) =>
      _setStatus(adminId, id, 'active', 'user.unban', null);

  Future<AdminResult> _setStatus(
    String adminId,
    String id,
    String status,
    String action,
    Object? reason,
  ) async {
    final updated = await _auth.setStatus(id, status);
    if (updated == null) return (ok: false, error: 'not_found', data: null);
    await _audit.append((
      actorAdminId: adminId,
      action: action,
      targetType: 'user',
      targetId: id,
      reason: reason is String && reason.trim().isNotEmpty
          ? reason.trim()
          : null,
      metadata: const {},
    ));
    return (ok: true, error: null, data: updated.toJson());
  }
}
