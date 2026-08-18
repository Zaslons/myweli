import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart' show cronAuth;
import 'package:myweli_backend/src/messaging/reminder_scheduler.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /internal/cron/reminders` — Cloud Scheduler hits this to dispatch the
/// due 24h/2h reminders. Idempotent per tick.
///
/// Authenticated by `CronAuth`: the Google-signed OIDC token Scheduler already
/// sends, and nothing else — the transitional `X-Cron-Secret` fallback was
/// retired on 2026-08-18 (see `cron_auth.dart` for the evidence). Deny-by-
/// default: 404 when the OIDC pair is unconfigured, so the surface does not
/// exist; 403 otherwise, including a token that fails verification.
/// Design: docs/design/messaging-notifications.md §PR-B.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  if (!cronAuth.isConfigured) {
    return jsonError(HttpStatus.notFound, 'not_found');
  }
  final auth = await cronAuth.authenticate(
    bearer: context.request.headers['authorization'],
  );
  if (!auth.ok) return jsonError(HttpStatus.forbidden, 'forbidden');

  final r = await context.read<ReminderScheduler>().tick(
    DateTime.now().toUtc(),
  );
  return Response.json(
    body: {'reminder24h': r.reminder24h, 'reminder2h': r.reminder2h},
  );
}
