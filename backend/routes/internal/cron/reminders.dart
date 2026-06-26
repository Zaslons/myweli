import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart' show cronSecret;
import 'package:myweli_backend/src/messaging/reminder_scheduler.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /internal/cron/reminders` — an external scheduler hits this to dispatch
/// the due 24h/2h reminders. Guarded by `CRON_SECRET` (deny-by-default: 404 when
/// unset so the surface doesn't exist; 403 on mismatch). Idempotent per tick.
/// Design: docs/design/messaging-notifications.md §PR-B.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final secret = cronSecret;
  if (secret == null) return jsonError(HttpStatus.notFound, 'not_found');
  final provided =
      context.request.headers['x-cron-secret'] ??
      context.request.uri.queryParameters['secret'];
  if (provided != secret) return jsonError(HttpStatus.forbidden, 'forbidden');

  final r = await context.read<ReminderScheduler>().tick(
    DateTime.now().toUtc(),
  );
  return Response.json(
    body: {'reminder24h': r.reminder24h, 'reminder2h': r.reminder2h},
  );
}
