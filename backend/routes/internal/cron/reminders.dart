import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/cron_auth.dart';
import 'package:myweli_backend/src/dependencies.dart' show cronAuth;
import 'package:myweli_backend/src/messaging/reminder_scheduler.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /internal/cron/reminders` — Cloud Scheduler hits this to dispatch the
/// due 24h/2h reminders. Idempotent per tick.
///
/// Authenticated by `CronAuth`: the Google-signed OIDC token Scheduler already
/// sends, with `CRON_SECRET` as the transitional fallback (see `cron_auth.dart`
/// for why both, and when the header goes). Deny-by-default — 404 when neither
/// is configured, so the surface does not exist; 403 otherwise.
/// Design: docs/design/messaging-notifications.md §PR-B.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  if (!cronAuth.isConfigured) {
    return jsonError(HttpStatus.notFound, 'not_found');
  }
  final auth = await cronAuth.authenticate(
    bearer: context.request.headers['authorization'],
    headerSecret: context.request.headers['x-cron-secret'],
  );
  if (!auth.ok) return jsonError(HttpStatus.forbidden, 'forbidden');
  if (auth.method == CronAuthMethod.sharedSecret) {
    // The evidence gate: the header stays until a real Scheduler run is seen
    // arriving on the OIDC token instead (docs/design/infra-staging.md §7).
    // ignore: avoid_print — this is the signal that says when it can go.
    print(
      'INFO: cron_auth_legacy — /internal/cron/reminders authenticated on the '
      'shared secret, not the OIDC token',
    );
  }

  final r = await context.read<ReminderScheduler>().tick(
    DateTime.now().toUtc(),
  );
  return Response.json(
    body: {'reminder24h': r.reminder24h, 'reminder2h': r.reminder2h},
  );
}
