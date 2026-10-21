import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart' show cronAuth;
import 'package:myweli_backend/src/maintenance/maintenance_tick.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /internal/cron/maintenance` — the daily housekeeping (job
/// `myweli-maintenance`, 03:30 UTC): the admin-throttle and rate-limit
/// prunes, the kept answers' prune and the demo-salon reset, with each count
/// in the response. They rode `/internal/cron/subscriptions` until a fourth
/// arrived; since the move a failed offers walk no longer skips them, and the
/// name no longer hides security prunes under « subscriptions ».
///
/// The same door as the two other crons: `CronAuth`, the Google-signed OIDC
/// token and nothing else — 404 when the OIDC pair is unconfigured (the
/// surface does not exist), 403 otherwise. Idempotent per tick: every prune
/// is, and the reset is due-gated.
/// Design: docs/design/infra-cron-maintenance.md.
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
    body: await context.read<MaintenanceTick>().run(DateTime.now().toUtc()),
  );
}
