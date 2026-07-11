import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/capabilities.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';

/// `POST /providers/{id}/publish` — the owner takes their salon live
/// (docs/design/pro-salon-lifecycle.md; PRD FR-PRO-ONB-001's « go live »).
/// Provider-only + ownership-scoped (T50); the completeness gate is computed
/// from SERVER state (profile · ≥3 services · ≥3 photos · opening hours) —
/// incomplete → 409 `incomplete` + the missing checklist keys. Idempotent.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  // Module `access` R1 (sign-off: go-live is owner-only → salon.publish).
  final allowed = await context.read<MembershipService>().can(
    principal.userId,
    id,
    Cap.salonPublish,
  );
  if (!allowed) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final r = await context.read<SalonProvisioningService>().publish(id);
  if (r.ok) return Response.json(body: r.data);
  if (r.error == 'not_found') {
    return jsonError(HttpStatus.notFound, 'not_found');
  }
  // incomplete → 409 with the missing checklist keys.
  return Response.json(
    statusCode: HttpStatus.conflict,
    body: {'error': r.error, ...(r.data as Map<String, dynamic>? ?? {})},
  );
}
