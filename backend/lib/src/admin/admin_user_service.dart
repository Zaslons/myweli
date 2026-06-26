import '../appointments/appointment_repository.dart';
import '../auth/auth_repository.dart';
import 'admin_kyc_service.dart' show AdminResult;
import 'audit_log_repository.dart';

/// Admin consumer management (design: docs/design/admin-console.md §12). List /
/// view users, ban/unban (banned ⇒ login blocked) — every mutation audited.
/// Support views are read-only (no act-as).
class AdminUserService {
  AdminUserService(this._auth, this._appointments, this._audit);

  final AuthRepository _auth;
  final AppointmentRepository _appointments;
  final AuditLogRepository _audit;

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
