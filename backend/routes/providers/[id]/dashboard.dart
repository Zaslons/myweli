import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/provider_dashboard_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /providers/{id}/dashboard` — server-computed `DashboardStats` for the
/// salon. Provider-only and ownership-scoped (the token's account must manage
/// `{id}`). Design: docs/design/provider-dashboard-stats.md.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final r = await context.read<ProviderDashboardService>().statsFor(
    principal.userId,
    id,
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
