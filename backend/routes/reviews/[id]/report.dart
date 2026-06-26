import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/moderation_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /reviews/{id}/report` — a consumer flags a review (FR-REV-005). The
/// review stays visible; the report enters the admin moderation queue. Idempotent
/// per (review, reporter). Design: docs/design/admin-console.md.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'user') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  Map<String, dynamic> body = const {};
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    // reason is optional — tolerate an empty/absent body
  }

  final r = await context.read<ModerationService>().report(
    principal.userId,
    id,
    body['reason'],
  );
  if (r.ok) return Response.json(body: r.data);
  if (r.error == 'not_found') {
    return jsonError(HttpStatus.notFound, 'not_found');
  }
  return jsonError(HttpStatus.badRequest, r.error ?? 'invalid_input');
}
