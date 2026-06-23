/// Stored appointments. Each appointment is a `Map` in the `Appointment`
/// DTO shape (see docs/api/openapi.yaml). In-memory now; a Postgres impl
/// satisfies the same interface in a follow-up.
abstract interface class AppointmentRepository {
  Future<Map<String, dynamic>> create(Map<String, dynamic> appointment);

  /// The caller's appointments, newest first, optionally filtered by status.
  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    String? status,
  });

  /// All of a provider's appointments (any status) — used by the slot engine to
  /// exclude booked times. The caller filters out cancelled.
  Future<List<Map<String, dynamic>>> listForProvider(String providerId);

  Future<Map<String, dynamic>?> byId(String id);
}

class InMemoryAppointmentRepository implements AppointmentRepository {
  final List<Map<String, dynamic>> _all = [];

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> appointment) async {
    _all.add(appointment);
    return appointment;
  }

  @override
  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    String? status,
  }) async {
    final list =
        _all
            .where((a) => a['userId'] == userId)
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
  Future<List<Map<String, dynamic>>> listForProvider(String providerId) async {
    return _all.where((a) => a['providerId'] == providerId).toList();
  }

  @override
  Future<Map<String, dynamic>?> byId(String id) async {
    for (final a in _all) {
      if (a['id'] == id) return a;
    }
    return null;
  }
}
