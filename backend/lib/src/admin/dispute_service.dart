import '../appointments/appointment_repository.dart';
import '../deposit_service.dart';
import 'admin_kyc_service.dart' show AdminResult;
import 'audit_log_repository.dart';
import 'disputes_repository.dart';

/// Admin dispute case management (design: docs/design/admin-console.md §12).
/// A dispute is recorded against a booking with evidence (status history +
/// deposit screenshot) and resolved with an outcome — **no money moves**
/// (no-custody); resolution is advisory + any consequence applied separately.
class DisputeService {
  DisputeService(
    this._disputes,
    this._appointments,
    this._deposit,
    this._audit,
  );

  final DisputesRepository _disputes;
  final AppointmentRepository _appointments;
  final DepositService _deposit;
  final AuditLogRepository _audit;

  Future<AdminResult> open(
    String adminId,
    Object? appointmentId,
    Object? reason,
  ) async {
    if (appointmentId is! String || appointmentId.isEmpty) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    if (reason is! String || reason.trim().isEmpty) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    if (await _appointments.byId(appointmentId) == null) {
      return (ok: false, error: 'not_found', data: null);
    }
    final dispute = await _disputes.create(
      appointmentId: appointmentId,
      openedBy: adminId,
      reason: reason.trim(),
    );
    await _audit.append((
      actorAdminId: adminId,
      action: 'dispute.open',
      targetType: 'appointment',
      targetId: appointmentId,
      reason: reason.trim(),
      metadata: {'disputeId': dispute['id']},
    ));
    return (ok: true, error: null, data: dispute);
  }

  Future<AdminResult> list({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final r = await _disputes.list(
      status: status,
      page: page,
      pageSize: pageSize,
    );
    return (
      ok: true,
      error: null,
      data: {
        'items': r.items,
        'page': page,
        'pageSize': pageSize,
        'total': r.total,
      },
    );
  }

  /// Dispute + its booking + (if any) a signed deposit-screenshot URL — the
  /// evidence an admin needs to adjudicate.
  Future<AdminResult> detail(String adminId, String id) async {
    final dispute = await _disputes.byId(id);
    if (dispute == null) return (ok: false, error: 'not_found', data: null);
    final appt = await _appointments.byId(dispute['appointmentId'] as String);
    final shot = await _deposit.screenshotUrl(
      dispute['appointmentId'] as String,
      sub: adminId,
      role: 'admin',
    );
    return (
      ok: true,
      error: null,
      data: {
        'dispute': dispute,
        'appointment': appt,
        'depositScreenshotUrl': shot.ok ? (shot.data! as Map)['url'] : null,
      },
    );
  }

  Future<AdminResult> resolve(
    String adminId,
    String id,
    Object? resolution,
  ) async {
    if (resolution is! String || resolution.trim().isEmpty) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final updated = await _disputes.resolve(
      id,
      resolution: resolution.trim(),
      resolvedBy: adminId,
    );
    if (updated == null) return (ok: false, error: 'not_found', data: null);
    await _audit.append((
      actorAdminId: adminId,
      action: 'dispute.resolve',
      targetType: 'dispute',
      targetId: id,
      reason: resolution.trim(),
      metadata: const {},
    ));
    return (ok: true, error: null, data: updated);
  }
}
