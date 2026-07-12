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
/// the access token's `sub` resolves to a provider account whose journal scope
/// must cover the appointment (→ 403 otherwise). OWN-SCOPE members
/// (Collaborateur — T40, R4a) may complete/no-show THEIR OWN artist's
/// bookings only; accept/reject/arrive stay whole-journal actions. The server
/// is the authority on status; transitions are state-guarded.
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
        allowOwn: true, // Collaborateur: « Terminé » on own bookings (T40)
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
    // Module `access` R1/R4a: checked against the APPOINTMENT's salon
    // (multi-salon-safe). « Client arrivé » is a front-desk act — whole
    // journal only, never own-scope (staff actions = Terminé/Non présenté).
    final scope = await _members.journalScope(
      accountId,
      appointment['providerId'] as String? ?? '',
      manage: true,
    );
    if (!scope.all) {
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
        allowOwn: true, // Collaborateur: « Non présenté » on own bookings
      );

  Future<ProLifecycleResult> _transition(
    String appointmentId,
    String accountId, {
    required Set<String> from,
    required String to,
    bool allowOwn = false,
  }) async {
    final appointment = await _appointments.byId(appointmentId);
    if (appointment == null) {
      return (ok: false, error: 'not_found', appointment: null);
    }
    final scope = await _members.journalScope(
      accountId,
      appointment['providerId'] as String? ?? '',
      manage: true,
    );
    // T40: own-scope passes only where the ACTION allows it AND the booking
    // belongs to the member's own artist (server-resolved, never client-sent).
    final ownOk =
        allowOwn &&
        scope.ownArtistId != null &&
        appointment['artistId'] == scope.ownArtistId;
    if (!scope.all && !ownOk) {
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
