import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart' show cronAuth;
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/subscription/subscription_scheduler.dart';

/// `POST /internal/cron/subscriptions` — the daily offer walk: trial warnings
/// (J-14/J-7/J-1), the grace notice, and — only when enforcement is on —
/// the past-grace unpublish. Authenticated by `CronAuth` — the OIDC token
/// only, exactly like the reminders cron (404 when the OIDC pair is unset; 403
/// otherwise). Idempotent per tick.
/// Design: docs/design/team-access-r2a-offers.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  if (!cronAuth.isConfigured) {
    return jsonError(HttpStatus.notFound, 'not_found');
  }
  final auth = await cronAuth.authenticate(
    bearer: context.request.headers['authorization'],
  );
  if (!auth.ok) return jsonError(HttpStatus.forbidden, 'forbidden');

  final r = await context.read<SubscriptionScheduler>().tick(
    DateTime.now().toUtc(),
  );
  return Response.json(
    body: {'notices': r.notices, 'unpublished': r.unpublished},
  );
}
