import 'appointment_repository.dart';
import 'slot_service.dart';

typedef LifecycleResult = ({
  bool ok,
  String? error,
  Map<String, dynamic>? appointment,
});

/// Consumer-driven appointment lifecycle (docs/BACKEND.md §1, §3.3): cancel and
/// reschedule the caller's **own** bookings, with ownership + state guards. The
/// server is the authority on status; the deposit is salon↔client (no custody),
/// so cancel just records the status — no refund logic here. Reschedule
/// re-validates the new time against [SlotService] (no double-booking).
///
/// Pro-side transitions (accept/complete/no-show) are a separate slice — they
/// need the provider-account ↔ Provider link + provider authz.
class AppointmentLifecycleService {
  AppointmentLifecycleService(this._appointments, this._slots);

  final AppointmentRepository _appointments;
  final SlotService _slots;

  static const _terminal = {'cancelled', 'completed', 'noShow'};

  Future<LifecycleResult> cancel(String id, String userId) async {
    return _transition(id, userId, (_) => {'status': 'cancelled'});
  }

  Future<LifecycleResult> reschedule(
    String id,
    String userId,
    DateTime newDateTime,
  ) async {
    final appointment = await _appointments.byId(id);
    if (appointment == null) {
      return (ok: false, error: 'not_found', appointment: null);
    }
    if (appointment['userId'] != userId) {
      return (ok: false, error: 'forbidden', appointment: null);
    }
    if (_terminal.contains(appointment['status'])) {
      return (ok: false, error: 'invalid_state', appointment: null);
    }

    // The new time must be a free slot (rejects past/closed/already-taken).
    final slotResult = await _slots.availableSlots(
      providerId: appointment['providerId'] as String,
      date: newDateTime,
      serviceIds: (appointment['serviceIds'] as List).cast<String>(),
    );
    final wanted = newDateTime.toUtc();
    final isFree = (slotResult.slots ?? const []).any(
      (s) => s.isAtSameMomentAs(wanted),
    );
    if (!isFree) {
      return (ok: false, error: 'slot_unavailable', appointment: null);
    }

    // Deposit/balance carry over unchanged; only the date moves.
    final updated = await _appointments.update(id, {
      'appointmentDate': newDateTime.toUtc().toIso8601String(),
    });
    return (ok: true, error: null, appointment: updated);
  }

  /// Shared ownership + state guard, then apply [changes].
  Future<LifecycleResult> _transition(
    String id,
    String userId,
    Map<String, dynamic> Function(Map<String, dynamic> current) changes,
  ) async {
    final appointment = await _appointments.byId(id);
    if (appointment == null) {
      return (ok: false, error: 'not_found', appointment: null);
    }
    if (appointment['userId'] != userId) {
      return (ok: false, error: 'forbidden', appointment: null);
    }
    if (_terminal.contains(appointment['status'])) {
      return (ok: false, error: 'invalid_state', appointment: null);
    }
    final updated = await _appointments.update(id, changes(appointment));
    return (ok: true, error: null, appointment: updated);
  }
}
