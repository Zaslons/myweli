import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `/providers/{id}/artists/{artistId}` — `PATCH` edits a staff member;
/// `DELETE` removes them. Provider-only and ownership-scoped.
/// Design: docs/design/pro-artists.md.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String artistId,
) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  final catalog = context.read<ProviderCatalogService>();

  switch (context.request.method) {
    case HttpMethod.patch:
      final Map<String, dynamic> body;
      try {
        body = await context.request.json() as Map<String, dynamic>;
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      final r = await catalog.updateArtist(
        principal.userId,
        id,
        artistId,
        body,
      );
      return resultResponse(ok: r.ok, error: r.error, body: r.data);
    case HttpMethod.delete:
      final r = await catalog.deleteArtist(principal.userId, id, artistId);
      if (!r.ok) return resultResponse(ok: false, error: r.error, body: null);
      return Response(statusCode: HttpStatus.noContent);
    default:
      return methodNotAllowed();
  }
}
