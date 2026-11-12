import 'reminder_scheduler.dart';

/// What `POST /internal/cron/reminders` does once `CronAuth` has let the
/// call in, and the body it answers: the 24h/2h reminders, then the
/// admin's place-change summaries that are due (B0.18, decision 133 —
/// docs/design/salon-go-live-approval.md §5.1). The summaries ride this
/// 15-minute tick rather than a Scheduler job of their own.
///
/// **The reminders come first and never depend on the summaries.** The
/// summary step is best effort: if it throws, the tick still answers the
/// reminders' counts with `placeChangeSummaries: 0`, and the failure is
/// logged as its type only — no salon, no address. A reminders failure
/// still fails the tick, exactly as before.
Future<Map<String, int>> runRemindersCron({
  required Future<ReminderTickResult> Function(DateTime now) reminders,
  required Future<int> Function(DateTime now) placeChangeSummaries,
  required DateTime now,
  void Function(String)? log,
}) async {
  final r = await reminders(now);
  var summaries = 0;
  try {
    summaries = await placeChangeSummaries(now);
  } catch (e) {
    (log ?? print)(
      'cron_reminders step=place_change_summaries outcome=failed '
      'error=${e.runtimeType}',
    );
  }
  return {
    'reminder24h': r.reminder24h,
    'reminder2h': r.reminder2h,
    'placeChangeSummaries': summaries,
  };
}
