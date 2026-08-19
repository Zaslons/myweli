import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart'
    show cronAuth, pruneAdminLoginThrottle;
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

  // **The admin-throttle prune rides here rather than on a job of its own.**
  // This one already runs daily, is already OIDC-authenticated, and is already
  // covered by the missed-cron alert — so it costs no new Scheduler job, no new
  // audience to keep in sync, and nothing new that can stop silently. A third
  // maintenance task is when to extract `/internal/cron/maintenance`.
  //
  // **And the window is a security parameter, not housekeeping.** A `fail_count`
  // whose `locked_until` is NULL never decays on its own, so without this four
  // failures spread over a year would still be four. The prune is what gives
  // the counter a decay, which is why 24h sits beside maxAttempts and lockout
  // in the design rather than in a maintenance note.
  //
  // The count is returned so the operation is observable rather than silent —
  // a prune nobody can see is the shape this repo keeps finding.
  final pruned = await pruneAdminLoginThrottle(const Duration(hours: 24));

  return Response.json(
    body: {
      'notices': r.notices,
      'unpublished': r.unpublished,
      'throttleRowsPruned': pruned,
    },
  );
}
