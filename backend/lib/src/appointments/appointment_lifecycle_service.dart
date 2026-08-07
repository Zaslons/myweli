import '../providers_repository.dart';
import '../salon_visibility.dart';
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
  AppointmentLifecycleService(this._appointments, this._slots, this._providers);

  final AppointmentRepository _appointments;
  final SlotService _slots;

  /// **Positional and required as of PR1d**, where it used to be an optional
  /// named argument documented as *« null keeps older constructions (and
  /// consumer paths) unchanged »*. That is now backwards: the CONSUMER path is
  /// exactly the one that needs it, to refuse a reschedule at a salon that has
  /// stopped taking bookings (Decision C).
  ///
  /// Positional, so an omission is a parameter-count error that no `?.` and no
  /// default can absorb. Nullable, it would have made the new gate silently
  /// unreachable in the one test file that covers reschedule — a gate that
  /// cannot fail (§21 row 70), which is PR1b's own miss in miniature.
  final ProvidersRepository _providers;

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
    // Decision C. The ownership check above ran FIRST on purpose: this caller
    // owns the booking, so telling them which state their salon is in leaks
    // nothing they do not already know — unlike `/availability`, which answers
    // to anyone and therefore flattens both states into `provider_not_found`.
    //
    // Both codes already render (`api_appointment_service._messageFor`,
    // web's `conflictMessage`), and the mobile detail screen already CLAIMS
    // this behaviour in a comment: « the server refuses the move … hiding is a
    // courtesy OVER the server gate, never instead of one. » This is the gate
    // that sentence was describing.
    final refusal = clientBookingRefusal(
      await _providers.byId(appointment['providerId'] as String),
    );
    if (refusal != null) {
      return (ok: false, error: refusal, appointment: null);
    }
    return _moveTo(id, appointment, newDateTime);
  }

  /// Pro-side reschedule: the **salon** moves one of its own bookings (design:
  /// docs/design/pro-reschedule.md). Same state + slot guards as [reschedule],
  /// but ownership is by salon — [managedProviderId] is the resolved Provider
  /// the calling account manages (the route resolves it from the token).
  Future<LifecycleResult> rescheduleByProvider(
    String id,
    String managedProviderId,
    DateTime newDateTime, {
    String? artistId,
  }) async {
    final appointment = await _appointments.byId(id);
    if (appointment == null) {
      return (ok: false, error: 'not_found', appointment: null);
    }
    if (appointment['providerId'] != managedProviderId) {
      return (ok: false, error: 'forbidden', appointment: null);
    }
    if (_terminal.contains(appointment['status'])) {
      return (ok: false, error: 'invalid_state', appointment: null);
    }
    // Decision A, the OTHER half. Its rule reads « a salon that has not
    // published yet owns its calendar; a salon that has been SUSPENDED does
    // not », and `bookManual` has always obeyed it — this path never checked at
    // all, so the written rule was half true. A draft salon keeps moving its
    // own bookings; a suspended one does not.
    final salon = await _providers.byId(managedProviderId);
    if (salon?['status'] == 'suspended') {
      return (ok: false, error: 'provider_suspended', appointment: null);
    }
    // Drag across columns (journal J1): the target artist must belong to
    // THIS salon — the grid is never trusted (threat T42).
    if (artistId != null && artistId.isNotEmpty) {
      final owns = ((salon?['artists'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .any((a) => a['id'] == artistId);
      if (!owns) {
        return (ok: false, error: 'invalid_artist', appointment: null);
      }
    }
    return _moveTo(
      id,
      appointment,
      newDateTime,
      artistId: artistId,
      enforceBookingWindow: false,
      requireVisibleSalon: false,
    );
  }

  /// Shared by both reschedule paths: the new time must be a free slot
  /// (rejects past/closed/already-taken), then move the date only —
  /// deposit/balance/services carry over unchanged.
  Future<LifecycleResult> _moveTo(
    String id,
    Map<String, dynamic> appointment,
    DateTime newDateTime, {
    String? artistId,
    // A14d. The bookable window is a CLIENT-facing rule, so the salon moving
    // its own booking is exempt — the same principle that exempts `bookManual`
    // from the slot engine entirely. Both consumer and pro reschedule share
    // this method, which is exactly why the distinction has to be a parameter
    // rather than a property of the code path.
    bool enforceBookingWindow = true,
    // Decision C's sibling of the flag above, and it moves with it: the salon
    // moving its own booking is exempt from BOTH client-facing rules. They
    // always travel together, which is the trigger for folding them into one
    // audience enum the day a third caller-kind appears (§9).
    bool requireVisibleSalon = true,
  }) async {
    // Capacity model: validate against the TARGET artist's calendar (the
    // drag's new column when given, else the booking's current artist).
    final effectiveArtist = (artistId != null && artistId.isNotEmpty)
        ? artistId
        : appointment['artistId'] as String?;
    final slotResult = await _slots.availableSlots(
      providerId: appointment['providerId'] as String,
      date: newDateTime,
      serviceIds: (appointment['serviceIds'] as List).cast<String>(),
      artistId: effectiveArtist,
      enforceBookingWindow: enforceBookingWindow,
      requireVisibleSalon: requireVisibleSalon,
    );
    if (!slotResult.ok) {
      return (ok: false, error: slotResult.error, appointment: null);
    }
    final wanted = newDateTime.toUtc();
    final isFree = (slotResult.slots ?? const []).any(
      (s) => s.isAtSameMomentAs(wanted),
    );
    if (!isFree) {
      return (ok: false, error: 'slot_unavailable', appointment: null);
    }

    // Shift the stored end with the start (= start + duration) so the overlap
    // exclusion guards the new window.
    final start = newDateTime.toUtc();
    final dur = (appointment['durationMinutes'] as num?)?.toInt() ?? 30;
    final updated = await _appointments.update(id, {
      'appointmentDate': start.toIso8601String(),
      'endsAt': start.add(Duration(minutes: dur)).toIso8601String(),
      if (artistId != null && artistId.isNotEmpty) 'artistId': artistId,
    });
    // Null here means the DB rejected a concurrent overlap (exclusion guard).
    if (updated == null) {
      return (ok: false, error: 'slot_unavailable', appointment: null);
    }
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
