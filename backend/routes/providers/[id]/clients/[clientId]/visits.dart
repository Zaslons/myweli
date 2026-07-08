import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /providers/{id}/clients/{clientId}/visits` — the client's visit
/// history AT THIS SALON only (paginated, newest first; never cross-salon —
/// threat T45). Design: docs/design/clients-c1.md.
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
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final params = context.request.uri.queryParameters;
  final r = await context.read<ClientsService>().visits(
    principal.userId,
    id,
    clientId,
    page: int.tryParse(params['page'] ?? '') ?? 1,
    pageSize: int.tryParse(params['pageSize'] ?? '') ?? 20,
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
