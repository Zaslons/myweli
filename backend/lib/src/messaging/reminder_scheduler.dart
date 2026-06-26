import '../appointments/appointment_repository.dart';
import 'booking_notifier.dart';
import 'messaging_models.dart';
import 'reminder_log_repository.dart';

/// How many of each reminder a tick dispatched.
typedef ReminderTickResult = ({int reminder24h, int reminder2h});

/// Sends the 24h / 2h appointment reminders. Designed to be driven by an
/// external cron hitting the internal route; each [tick] is **idempotent** via
/// the [ReminderLogRepository] (no double-sends across ticks). Côte d'Ivoire is
/// UTC, so windows are computed in UTC. Design:
/// docs/design/messaging-notifications.md §PR-B.
class ReminderScheduler {
  ReminderScheduler(this._appointments, this._reminders, this._notifier);

  final AppointmentRepository _appointments;
  final ReminderLogRepository _reminders;
  final BookingNotifier _notifier;

  Future<ReminderTickResult> tick(DateTime now) async {
    final until = now.add(const Duration(hours: 24));
    final due = await _appointments.confirmedInWindow(now, until);
    var sent24 = 0;
    var sent2 = 0;
    for (final a in due) {
      final id = a['id'] as String?;
      final at = DateTime.tryParse('${a['appointmentDate'] ?? ''}')?.toUtc();
      if (id == null || at == null) continue;

      // 24h reminder: fires once, when the appointment first enters the window.
      if (await _reminders.markIfNew(id, 'reminder24h')) {
        await _notifier.notify(a, MessageTemplate.reminder24h);
        sent24++;
      }
      // 2h reminder: only once the appointment is within 2 hours.
      if (at.difference(now) <= const Duration(hours: 2) &&
          await _reminders.markIfNew(id, 'reminder2h')) {
        await _notifier.notify(a, MessageTemplate.reminder2h);
        sent2++;
      }
    }
    return (reminder24h: sent24, reminder2h: sent2);
  }
}
