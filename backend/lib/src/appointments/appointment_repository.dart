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

  /// Writes [changes] to the stored appointment and returns the updated
  /// record, or null if it doesn't exist.
  ///
  /// **Only the keys of [kAppointmentUpdatableKeys], with values Postgres can
  /// store** — anything else throws [ArgumentError] before any write, in both
  /// twins ([checkAppointmentChanges]). `currency`, `serviceLines` and
  /// `channel` are not among them: what a booking was sold as, for how much
  /// and where, is immutable. `endsAt` is written and never read back.
  ///
  /// Postgres also returns null when a reschedule lands on a slot a
  /// concurrent request just took (the exclusion constraint, 23P01). The
  /// in-memory impl never does: the service's own slot check runs first, and
  /// only a race between two requests reaches the constraint.
  ///
  /// docs/design/appointment-twin-update.md §5.1–§5.2, §5.5.
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

/// The keys [AppointmentRepository.update] writes: exactly the seven the
/// Postgres `SET` builder knows. Both twins read this set.
///
/// `artistNameKept` is the collaborateur's name kept with the booking (R1),
/// accepted only together with `artistId` ([checkAppointmentChanges]): a
/// reassignment writes both, so a booking's revenue is never filed under a
/// collaborateur it is no longer with.
///
/// Design: docs/design/appointment-twin-update.md §5.1 (decision 214);
/// docs/design/pro-revenue-analytics.md §8.1.
const Set<String> kAppointmentUpdatableKeys = {
  'status',
  'appointmentDate',
  'endsAt',
  'depositScreenshotUrl',
  'arrivedAt',
  'artistId',
  'artistNameKept',
};

/// Throws [ArgumentError] for a key outside [kAppointmentUpdatableKeys], or a
/// value the Postgres builder cannot store. Both twins call it before any
/// write, so a mistake is refused the same way in a test and in production,
/// instead of being kept by one twin and silently dropped by the other.
///
/// Design: docs/design/appointment-twin-update.md §5.2 (decision 214).
void checkAppointmentChanges(Map<String, dynamic> changes) {
  final unknown = changes.keys.toSet().difference(kAppointmentUpdatableKeys);
  if (unknown.isNotEmpty) {
    throw ArgumentError.value(
      unknown.toList()..sort(),
      'changes',
      'AppointmentRepository.update writes only $kAppointmentUpdatableKeys',
    );
  }
  bool isInstant(Object? v) => v is String && DateTime.tryParse(v) != null;
  void refuse(String key) => throw ArgumentError.value(
    changes[key],
    key,
    'not a value the appointments table can store',
  );
  if (changes.containsKey('status')) {
    final s = changes['status'];
    if (s is! String || s.isEmpty) refuse('status');
  }
  for (final key in const ['appointmentDate', 'endsAt']) {
    if (changes.containsKey(key) && !isInstant(changes[key])) refuse(key);
  }
  if (changes.containsKey('arrivedAt')) {
    final v = changes['arrivedAt'];
    if (v != null && !isInstant(v)) refuse('arrivedAt');
  }
  for (final key in const [
    'depositScreenshotUrl',
    'artistId',
    'artistNameKept',
  ]) {
    if (changes.containsKey(key)) {
      final v = changes[key];
      if (v != null && v is! String) refuse(key);
    }
  }
  // A name without the id it names would leave the booking with one
  // collaborateur and its revenue with another (pro-revenue-analytics.md §8.1).
  if (changes.containsKey('artistNameKept') &&
      !changes.containsKey('artistId')) {
    throw ArgumentError.value(
      changes['artistNameKept'],
      'artistNameKept',
      'written only together with artistId',
    );
  }
}

/// The in-memory twin. It behaves as Postgres does where a caller can see it:
/// [update] writes the same keys and refuses the same values, and every read
/// returns a fresh deep copy in the shape Postgres returns (no `endsAt`), so
/// editing what a read handed out never changes what is stored.
///
/// Design: docs/design/appointment-twin-update.md §5 (decisions 214–217).
class InMemoryAppointmentRepository implements AppointmentRepository {
  final List<Map<String, dynamic>> _all = [];

  /// A deep copy: maps and lists all the way down, so nothing nested is
  /// shared between the store and a caller.
  static Object? _deep(Object? v) => switch (v) {
    final Map<dynamic, dynamic> m => <String, dynamic>{
      for (final e in m.entries) e.key as String: _deep(e.value),
    },
    final List<dynamic> l => [for (final e in l) _deep(e)],
    _ => v,
  };

  /// What a read hands out: a deep copy, without `endsAt` — the one stored
  /// key Postgres's `_toDto` never returns.
  static Map<String, dynamic> _out(Map<String, dynamic> stored) =>
      (_deep(stored)! as Map<String, dynamic>)..remove('endsAt');

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
          if (_within(a['appointmentDate'] as String?, from, to)) _out(a),
    ];
  }

  static bool _within(String? iso, DateTime from, DateTime to) {
    final at = iso == null ? null : DateTime.tryParse(iso)?.toUtc();
    return at != null && at.isAfter(from) && !at.isAfter(to);
  }

  @override
  Future<Map<String, dynamic>?> create(Map<String, dynamic> appointment) async {
    // A copy of the caller's map, not the map itself: editing it afterwards
    // must not change what is stored, as on Postgres.
    final stored = _deep(appointment)! as Map<String, dynamic>;
    _all.add(stored);
    return _out(stored);
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
            .map(_out)
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
        .map(_out)
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
      if (a['id'] == id) return _out(a);
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> update(
    String id,
    Map<String, dynamic> changes,
  ) async {
    // The same keys and values as Postgres, refused before any write
    // (`currency` included: the stamp is immutable). The guest-phone change
    // has its own [moveGuestPhone], so nothing writes `clientPhone` here.
    checkAppointmentChanges(changes);
    for (final a in _all) {
      if (a['id'] == id) {
        a.addAll(_deep(changes)! as Map<String, dynamic>);
        return _out(a);
      }
    }
    return null;
  }

  /// The in-memory twin of `PostgresClientsRepository.changeGuestPhone`'s
  /// UPDATE (`postgres_clients_repository.dart`): the salon's own manual
  /// bookings carrying [from] move to [to] — `provider_id = @pid AND
  /// user_id = 'manual' AND client_phone = @old`, and nothing else. Returns
  /// how many moved.
  ///
  /// Synchronous on purpose: the caller's checks and every write happen with
  /// nothing yielding in between, the twin of the row lock. Not on the
  /// interface: the Postgres move must share the client card's transaction,
  /// which a method here could not.
  ///
  /// Design: docs/design/appointment-twin-update.md §5.3 (decision 215).
  int moveGuestPhone({
    required String providerId,
    required String from,
    required String to,
  }) {
    var moved = 0;
    for (final a in _all) {
      if (a['providerId'] == providerId &&
          a['userId'] == 'manual' &&
          a['clientPhone'] == from) {
        a['clientPhone'] = to;
        moved++;
      }
    }
    return moved;
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
