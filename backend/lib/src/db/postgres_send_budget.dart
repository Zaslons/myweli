import 'package:postgres/postgres.dart';

import '../email/send_budget.dart';

/// Postgres-backed [SendBudget] (table `email_send_budget`, migration `0033`).
class PostgresSendBudget implements SendBudget {
  PostgresSendBudget(this._pool, {this.ceilings = kDefaultCeilings});

  final Pool<void> _pool;
  final SendCeilings ceilings;

  int _ceiling(EmailClass c) =>
      c == EmailClass.cold ? ceilings.cold : ceilings.warm;

  DateTime _window() {
    final n = DateTime.now().toUtc();
    return DateTime.utc(n.year, n.month, n.day, n.hour);
  }

  @override
  Future<SendReservation> reserve(EmailClass cls) async {
    // **One statement, and that is the point.** A read-then-write would race
    // across instances: two of them both read 59, both decide there is room,
    // and both send. The upsert increments and returns the post-increment
    // value in a single atomic step, so the Nth caller — whichever instance it
    // lands on — is the one that sees N.
    final rows = await _pool.execute(
      Sql.named(
        'INSERT INTO email_send_budget (bucket, window_start, sent) '
        'VALUES (@b, @w, 1) '
        'ON CONFLICT (bucket, window_start) '
        'DO UPDATE SET sent = email_send_budget.sent + 1 '
        'RETURNING sent',
      ),
      parameters: {'b': cls.bucket, 'w': _window()},
    );
    final sent = rows.first.toColumnMap()['sent'] as int;
    final ceiling = _ceiling(cls);
    return (ok: sent <= ceiling, sent: sent, ceiling: ceiling);
  }

  @override
  Future<int> used(EmailClass cls) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT sent FROM email_send_budget '
        'WHERE bucket = @b AND window_start = @w',
      ),
      parameters: {'b': cls.bucket, 'w': _window()},
    );
    if (rows.isEmpty) return 0;
    return rows.first.toColumnMap()['sent'] as int;
  }
}
