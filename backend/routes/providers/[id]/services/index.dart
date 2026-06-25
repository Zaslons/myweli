import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `/providers/{id}/services` — the salon's catalogue. `GET` lists; `POST`
/// creates (server sets `id`/`providerId`/`active`). Provider-only and
/// ownership-scoped. Design:
/// docs/design/provider-services-availability-backend.md.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  final catalog = context.read<ProviderCatalogService>();

  switch (context.request.method) {
    case HttpMethod.get:
      final r = await catalog.listServices(principal.userId, id);
      if (!r.ok) return resultResponse(ok: false, error: r.error, body: null);
      final items = r.data as List;
      return Response.json(
        body: {
          'items': items,
          'page': 1,
          'pageSize': items.length,
          'total': items.length,
        },
      );
    case HttpMethod.post:
      final Map<String, dynamic> body;
      try {
        body = await context.request.json() as Map<String, dynamic>;
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      final r = await catalog.createService(principal.userId, id, body);
      if (!r.ok) return resultResponse(ok: false, error: r.error, body: null);
      return Response.json(statusCode: HttpStatus.created, body: r.data);
    default:
      return methodNotAllowed();
  }
}
