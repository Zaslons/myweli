/// Idempotency log for sent reminders — one row per (appointment, kind) so the
/// scheduler never double-sends across ticks. Design:
/// docs/design/messaging-notifications.md.
abstract interface class ReminderLogRepository {
  /// Atomically records that [kind] was sent for [appointmentId]. Returns true
  /// only if it was newly recorded (i.e. the caller should send now).
  Future<bool> markIfNew(String appointmentId, String kind);
}

class InMemoryReminderLogRepository implements ReminderLogRepository {
  final Set<String> _sent = {};

  @override
  Future<bool> markIfNew(String appointmentId, String kind) async =>
      _sent.add('$appointmentId:$kind');
}
