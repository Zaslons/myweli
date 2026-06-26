import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/dispute_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/disputes/{id}/resolve` — body `{resolution}` (required); closes
/// the case with an outcome. Audited. Design: docs/design/admin-console.md §12.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<DisputeService>().resolve(
    adminId,
    id,
    body['resolution'],
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
