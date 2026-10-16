import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:myweli_backend/src/responses.dart';

/// `/providers/{id}/clients/{clientId}` — the client card. `GET` returns the
/// client + salon-scoped stats + upcoming + notes (read audited); `PATCH`
/// updates the tag set and/or a guest card's number (the history follows
/// it — docs/design/phone-leftovers.md §8) and answers with the card.
/// Ownership-scoped; a foreign clientId is 404 (never leaked). Design:
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
      final tags = optionalList(body, 'tags')?.whereType<String>().toList();
      final phone = optionalString(body, 'phone');
      // Neither field: today's code for a body without tags, kept.
      if (tags == null && phone == null) {
        return jsonError(HttpStatus.badRequest, 'invalid_tags');
      }
      final r = await service.updateClient(
        principal.userId,
        id,
        clientId,
        phone: phone,
        tags: tags,
      );
      switch (r.error) {
        case 'client_linked':
          return jsonError(HttpStatus.conflict, 'client_linked');
        case 'client_anonymized':
          return jsonError(HttpStatus.conflict, 'client_anonymized');
        case 'client_exists':
          return Response.json(
            statusCode: HttpStatus.conflict,
            body: {'error': 'client_exists', ...?r.data},
          );
      }
      // invalid_tags / invalid_phone → 400 with the code; forbidden → 403;
      // not_found → 404.
      return resultResponse(ok: r.ok, error: r.error, body: r.data);
    default:
      return methodNotAllowed();
  }
}
