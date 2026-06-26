import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `/providers/{id}/gallery` — the salon's portfolio photo URLs. `GET` reads;
/// `PUT` replaces the list wholesale (`{ "imageUrls": [...] }`). Provider-only
/// and ownership-scoped (the token's account must manage `{id}`). Image bytes
/// are uploaded out of band to object storage; only URLs pass through here.
/// Design: docs/design/pro-gallery.md.
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
      final r = await catalog.gallery(principal.userId, id);
      return resultResponse(ok: r.ok, error: r.error, body: r.data);
    case HttpMethod.put:
      final Map<String, dynamic> body;
      try {
        body = await context.request.json() as Map<String, dynamic>;
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      final r = await catalog.updateGallery(principal.userId, id, body);
      return resultResponse(ok: r.ok, error: r.error, body: r.data);
    default:
      return methodNotAllowed();
  }
}
