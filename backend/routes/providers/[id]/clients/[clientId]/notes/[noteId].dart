import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `DELETE /providers/{id}/clients/{clientId}/notes/{noteId}` — remove a note
/// (author or owner). Design: docs/design/clients-c1.md.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String clientId,
  String noteId,
) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.delete) return methodNotAllowed();

  final r = await context.read<ClientsService>().deleteNote(
    principal.userId,
    id,
    clientId,
    noteId,
  );
  if (!r.ok) return resultResponse(ok: false, error: r.error, body: null);
  return Response(statusCode: HttpStatus.noContent);
}
