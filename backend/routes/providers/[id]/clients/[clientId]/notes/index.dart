import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /providers/{id}/clients/{clientId}/notes` — add an internal note
/// (≤500 chars; author = the authenticated principal, never client-sent —
/// threat T47; notes are never consumer-visible). Design:
/// docs/design/clients-c1.md.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String clientId,
) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final r = await context.read<ClientsService>().addNote(
    principal.userId,
    id,
    clientId,
    (body['body'] as String?) ?? '',
  );
  if (!r.ok && r.error == 'note_too_long') {
    return jsonError(HttpStatus.badRequest, 'note_too_long');
  }
  if (!r.ok) return resultResponse(ok: false, error: r.error, body: null);
  return Response.json(statusCode: HttpStatus.created, body: r.data);
}
