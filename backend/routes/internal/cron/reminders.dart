import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart' show cronAuth;
import 'package:myweli_backend/src/messaging/reminder_scheduler.dart';
import 'package:myweli_backend/src/messaging/reminders_cron.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validation/salon_place_notice_service.dart';

/// `POST /internal/cron/reminders` — Cloud Scheduler hits this to dispatch the
/// due 24h/2h reminders. Idempotent per tick. Since B0.18's decision 133 it
/// also sends the admin's place-change summaries that are due, AFTER the
/// reminders and best effort (`runRemindersCron`): a failed summary step
/// never fails the reminders, and a failed reminders step still fails the
/// tick only once the summaries have run. Each summary is claimed by one
/// tick only.
///
/// Authenticated by `CronAuth`: the Google-signed OIDC token Scheduler already
/// sends, and nothing else — the transitional `X-Cron-Secret` fallback was
/// retired on 2026-08-18 (see `cron_auth.dart` for the evidence). Deny-by-
/// default: 404 when the OIDC pair is unconfigured, so the surface does not
/// exist; 403 otherwise, including a token that fails verification.
/// Design: docs/design/messaging-notifications.md §PR-B;
/// docs/design/salon-go-live-approval.md §5.1 (the summaries).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  if (!cronAuth.isConfigured) {
    return jsonError(HttpStatus.notFound, 'not_found');
  }
  final auth = await cronAuth.authenticate(
    bearer: context.request.headers['authorization'],
  );
  if (!auth.ok) return jsonError(HttpStatus.forbidden, 'forbidden');

  return Response.json(
    body: await runRemindersCron(
      reminders: context.read<ReminderScheduler>().tick,
      // Read inside the step, so even a wiring fault stays in the summaries'
      // best effort and never costs the reminders.
      placeChangeSummaries: (now) =>
          context.read<SalonPlaceNoticeService>().tick(now),
      now: DateTime.now().toUtc(),
    ),
  );
}
