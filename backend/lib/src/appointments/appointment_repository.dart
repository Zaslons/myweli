/// Stored appointments. Each appointment is a `Map` in the `Appointment`
/// DTO shape (see docs/api/openapi.yaml). In-memory now; a Postgres impl
/// satisfies the same interface in a follow-up.
abstract interface class AppointmentRepository {
  /// Persist a new appointment. Returns the stored record, or **null** when the
  /// slot is already taken at the database level (the partial unique index on
  /// `(provider_id, appointment_date)` for non-cancelled statuses) — atomic
  /// double-booking prevention. The in-memory impl never returns null (the
  /// app-level slot check guards it).
  Future<Map<String, dynamic>?> create(Map<String, dynamic> appointment);

  /// The caller's appointments, newest first, optionally filtered by status.
  ///
  /// When [matchPhone] is given, also returns provider-entered (manual) bookings
  /// whose `clientPhone` equals it — the auto-sync of FR-APPT-008. The caller
  /// passes the account's **OTP-verified** phone (never a client-supplied value).
  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    String? status,
    String? matchPhone,
  });

  /// A provider's appointments, newest first, optionally filtered by status.
  /// With no [status] it returns every status — the slot engine relies on that
  /// to exclude already-booked times (it filters out cancelled itself).
  Future<List<Map<String, dynamic>>> listForProvider(
    String providerId, {
    String? status,
  });

  Future<Map<String, dynamic>?> byId(String id);

  /// Merge [changes] into the stored appointment; returns the updated record,
  /// or null if it doesn't exist.
  Future<Map<String, dynamic>?> update(String id, Map<String, dynamic> changes);
  // ---- Privacy (L1 erasure) ------------------------------------------------

  /// Strip the person out of their bookings, and hand back the deposit
  /// screenshot keys that were cleared so the caller can erase the objects.
  ///
  /// The row survives: once the name, phone and notes are gone, a dangling
  /// opaque `user_id` is a business record, not an identity, and the salon
  /// needs its booking history to reconcile takings.
  ///
  /// **Not expressible through [update]** — `clientName`, `clientPhone` and
  /// `notes` are not in its `sets` builder, so it cannot clear them.
  Future<List<String>> anonymizeUser(String userId);

  /// Deletes EVERY appointment of [providerId] and returns the count.
  ///
  /// **Exists for exactly one caller: the demo-salon reset (T69).** Account
  /// erasure deliberately KEEPS appointments (business history ≠ identity —
  /// `provider_account_service.dart`), so any new caller of this method is
  /// almost certainly wrong; the reset service re-verifies the target is the
  /// demo salon before calling it.
  Future<int> wipeForProvider(String providerId);

  /// Admin analytics: a count of appointments per `status`
  /// (`pending`/`confirmed`/`completed`/`cancelled`/`noShow`).
  Future<Map<String, int>> countsByStatus();

  /// Admin analytics (North Star): completed appointments with
  /// `appointment_date >= from`, as `{providerId, appointmentDate}` — the
  /// caller buckets by week + resolves the provider's commune.
  Future<List<Map<String, dynamic>>> completedForAnalytics(DateTime from);

  /// `confirmed` appointments with `from < appointment_date <= to` — the reminder
  /// scheduler's window. Full records (it needs recipient + params).
  Future<List<Map<String, dynamic>>> confirmedInWindow(
    DateTime from,
    DateTime to,
  );
}

class InMemoryAppointmentRepository implements AppointmentRepository {
  final List<Map<String, dynamic>> _all = [];

  @override
  Future<int> wipeForProvider(String providerId) async {
    final before = _all.length;
    _all.removeWhere((a) => a['providerId'] == providerId);
    return before - _all.length;
  }

  @override
  Future<Map<String, int>> countsByStatus() async {
    final counts = <String, int>{};
    for (final a in _all) {
      final s = a['status'] as String;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Future<List<Map<String, dynamic>>> completedForAnalytics(
    DateTime from,
  ) async {
    return [
      for (final a in _all)
        if (a['status'] == 'completed' &&
            !DateTime.parse(
              a['appointmentDate'] as String,
            ).toUtc().isBefore(from))
          {
            'providerId': a['providerId'],
            'appointmentDate': a['appointmentDate'],
          },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> confirmedInWindow(
    DateTime from,
    DateTime to,
  ) async {
    return [
      for (final a in _all)
        if (a['status'] == 'confirmed')
          if (_within(a['appointmentDate'] as String?, from, to)) a,
    ];
  }

  static bool _within(String? iso, DateTime from, DateTime to) {
    final at = iso == null ? null : DateTime.tryParse(iso)?.toUtc();
    return at != null && at.isAfter(from) && !at.isAfter(to);
  }

  @override
  Future<Map<String, dynamic>?> create(Map<String, dynamic> appointment) async {
    _all.add(appointment);
    return appointment;
  }

  @override
  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    String? status,
    String? matchPhone,
  }) async {
    final list =
        _all
            .where(
              (a) =>
                  a['userId'] == userId ||
                  (matchPhone != null &&
                      matchPhone.isNotEmpty &&
                      a['clientPhone'] == matchPhone),
            )
            .where((a) => status == null || a['status'] == status)
            .toList()
          ..sort(
            (a, b) => (b['appointmentDate'] as String).compareTo(
              a['appointmentDate'] as String,
            ),
          );
    return list;
  }

  @override
  Future<List<Map<String, dynamic>>> listForProvider(
    String providerId, {
    String? status,
  }) async {
    return _all
        .where((a) => a['providerId'] == providerId)
        .where((a) => status == null || a['status'] == status)
        .toList()
      ..sort(
        (a, b) => (b['appointmentDate'] as String).compareTo(
          a['appointmentDate'] as String,
        ),
      );
  }

  @override
  Future<Map<String, dynamic>?> byId(String id) async {
    for (final a in _all) {
      if (a['id'] == id) return a;
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> update(
    String id,
    Map<String, dynamic> changes,
  ) async {
    for (final a in _all) {
      if (a['id'] == id) {
        a.addAll(changes);
        return a;
      }
    }
    return null;
  }

  @override
  Future<List<String>> anonymizeUser(String userId) async {
    final keys = <String>[];
    for (final a in _all) {
      if (a['userId'] != userId) continue;
      final key = a['depositScreenshotUrl'];
      if (key is String && key.isNotEmpty) keys.add(key);
      a['clientName'] = null;
      a['clientPhone'] = null;
      a['notes'] = null;
      a['depositScreenshotUrl'] = null;
    }
    return keys;
  }
}
