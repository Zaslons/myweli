import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `/providers/{id}/clients/{clientId}` — the client card. `GET` returns the
/// client + salon-scoped stats + upcoming + notes (read audited); `PATCH`
/// updates the tag set. Ownership-scoped; a foreign clientId is 404 (never
/// leaked). Design: docs/design/clients-c1.md.
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
  final service = context.read<ClientsService>();
  switch (context.request.method) {
    case HttpMethod.get:
      final r = await service.card(principal.userId, id, clientId);
      return resultResponse(ok: r.ok, error: r.error, body: r.data);
    case HttpMethod.patch:
      final Map<String, dynamic> body;
      try {
        body = await context.request.json() as Map<String, dynamic>;
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      final tags = (body['tags'] as List?)?.whereType<String>().toList();
      if (tags == null) return jsonError(HttpStatus.badRequest, 'invalid_tags');
      final r = await service.updateTags(principal.userId, id, clientId, tags);
      if (!r.ok && r.error == 'invalid_tags') {
        return jsonError(HttpStatus.badRequest, 'invalid_tags');
      }
      return resultResponse(ok: r.ok, error: r.error, body: r.data);
    default:
      return methodNotAllowed();
  }
}
