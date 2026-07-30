import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart' show cronSecret;
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/subscription/subscription_scheduler.dart';

/// `POST /internal/cron/subscriptions` — the daily offer walk: trial warnings
/// (J-14/J-7/J-1), the grace notice, and — only when enforcement is on —
/// the past-grace unpublish. Guarded by `CRON_SECRET` exactly like the
/// reminders cron (404 when unset; 403 on mismatch). Idempotent per tick.
/// Design: docs/design/team-access-r2a-offers.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final secret = cronSecret;
  if (secret == null) return jsonError(HttpStatus.notFound, 'not_found');
  final provided =
      context.request.headers['x-cron-secret'] ??
      context.request.uri.queryParameters['secret'];
  if (provided != secret) return jsonError(HttpStatus.forbidden, 'forbidden');

  final r = await context.read<SubscriptionScheduler>().tick(
    DateTime.now().toUtc(),
  );
  return Response.json(
    body: {'notices': r.notices, 'unpublished': r.unpublished},
  );
}
