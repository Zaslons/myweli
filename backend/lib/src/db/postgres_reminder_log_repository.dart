import 'package:postgres/postgres.dart';

import '../messaging/reminder_log_repository.dart';

/// Postgres-backed reminder idempotency log (table `appointment_reminders`,
/// migration `0016`). `markIfNew` relies on the (appointment, kind) PK +
/// `ON CONFLICT DO NOTHING` so concurrent ticks never double-send.
class PostgresReminderLogRepository implements ReminderLogRepository {
  PostgresReminderLogRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<bool> markIfNew(String appointmentId, String kind) async {
    final rows = await _pool.execute(
      Sql.named(
        'INSERT INTO appointment_reminders (appointment_id, kind) '
        'VALUES (@a, @k) ON CONFLICT DO NOTHING RETURNING appointment_id',
      ),
      parameters: {'a': appointmentId, 'k': kind},
    );
    return rows.isNotEmpty;
  }
}
