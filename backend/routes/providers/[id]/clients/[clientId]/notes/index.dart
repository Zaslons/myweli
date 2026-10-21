import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:myweli_backend/src/idempotency/idempotent.dart';
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

  // The same key twice adds the note once (docs/design/write-idempotency.md).
  return idempotent(
    context,
    accountId: principal.userId,
    run: () => _add(context, principal.userId, id, clientId),
  );
}

Future<Response> _add(
  RequestContext context,
  String accountId,
  String id,
  String clientId,
) async {
  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final r = await context.read<ClientsService>().addNote(
    accountId,
    id,
    clientId,
    optionalString(body, 'body') ?? '',
  );
  if (!r.ok && r.error == 'note_too_long') {
    return jsonError(HttpStatus.badRequest, 'note_too_long');
  }
  if (!r.ok) return resultResponse(ok: false, error: r.error, body: null);
  return Response.json(statusCode: HttpStatus.created, body: r.data);
}
