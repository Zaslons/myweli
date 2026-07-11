import '../access/capabilities.dart';
import '../access/membership_service.dart';
import '../clients/clients_service.dart';
import 'appointment_repository.dart';

typedef ProLifecycleResult = ({
  bool ok,
  String? error,
  Map<String, dynamic>? appointment,
});

/// Pro-side appointment transitions (docs/BACKEND.md §3.3). The salon accepts /
/// rejects / completes / marks-no-show bookings for **its own** Provider only:
/// the access token's `sub` resolves to a provider account, and that account's
/// `providerId` must match the appointment's `providerId` (→ 403 otherwise).
/// The server is the authority on status; transitions are state-guarded.
class ProAppointmentService {
  ProAppointmentService(
    this._members,
    this._appointments, {
    ClientsService? clients,
  }) : _clients = clients;

  final MembershipService _members;
  final AppointmentRepository _appointments;

  /// Module `clients`: a completed visit bumps the client's `lastVisitAt`
  /// (docs/design/clients-c1.md). Best-effort.
  final ClientsService? _clients;

  Future<ProLifecycleResult> accept(String appointmentId, String accountId) =>
      _transition(
        appointmentId,
        accountId,
        from: const {'pending'},
        to: 'confirmed',
      );

  Future<ProLifecycleResult> reject(String appointmentId, String accountId) =>
      _transition(
        appointmentId,
        accountId,
        from: const {'pending'},
        to: 'cancelled',
      );

  Future<ProLifecycleResult> complete(String appointmentId, String accountId) =>
      _transition(
        appointmentId,
        accountId,
        from: const {'confirmed'},
        to: 'completed',
      );

  /// « Client arrivé » (journal J2 — docs/design/journal-j1-grid.md §2.2):
  /// stamps `arrivedAt` on a CONFIRMED booking, only on its calendar day
  /// (UTC — Abidjan time), idempotently. Threat T43 guards. [now] is
  /// injectable for tests.
  Future<ProLifecycleResult> arrive(
    String appointmentId,
    String accountId, {
    DateTime? now,
  }) async {
    final appointment = await _appointments.byId(appointmentId);
    if (appointment == null) {
      return (ok: false, error: 'not_found', appointment: null);
    }
    // Module `access` R1: the capability is checked against the APPOINTMENT's
    // salon (already multi-salon-safe).
    final allowed = await _members.can(
      accountId,
      appointment['providerId'] as String? ?? '',
      Cap.journalManageAll,
    );
    if (!allowed) {
      return (ok: false, error: 'forbidden', appointment: null);
    }
    if (appointment['status'] != 'confirmed') {
      return (ok: false, error: 'invalid_state', appointment: null);
    }
    final at = (now ?? DateTime.now()).toUtc();
    final start = DateTime.tryParse(
      appointment['appointmentDate'] as String? ?? '',
    )?.toUtc();
    if (start == null ||
        start.year != at.year ||
        start.month != at.month ||
        start.day != at.day) {
      return (ok: false, error: 'not_today', appointment: null);
    }
    if (appointment['arrivedAt'] != null) {
      return (ok: true, error: null, appointment: appointment); // idempotent
    }
    final updated = await _appointments.update(appointmentId, {
      'arrivedAt': at.toIso8601String(),
    });
    return (ok: true, error: null, appointment: updated);
  }

  Future<ProLifecycleResult> noShow(String appointmentId, String accountId) =>
      _transition(
        appointmentId,
        accountId,
        from: const {'pending', 'confirmed'},
        to: 'noShow',
      );

  Future<ProLifecycleResult> _transition(
    String appointmentId,
    String accountId, {
    required Set<String> from,
    required String to,
  }) async {
    final appointment = await _appointments.byId(appointmentId);
    if (appointment == null) {
      return (ok: false, error: 'not_found', appointment: null);
    }
    final allowed = await _members.can(
      accountId,
      appointment['providerId'] as String? ?? '',
      Cap.journalManageAll,
    );
    if (!allowed) {
      // Authenticated provider, but no capability inside this salon.
      return (ok: false, error: 'forbidden', appointment: null);
    }
    if (!from.contains(appointment['status'])) {
      return (ok: false, error: 'invalid_state', appointment: null);
    }
    final updated = await _appointments.update(appointmentId, {'status': to});
    if (to == 'completed' && updated != null) {
      await _clients?.recordCompletion(updated);
    }
    return (ok: true, error: null, appointment: updated);
  }
}
