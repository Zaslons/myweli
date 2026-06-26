import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/favorites_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST` / `DELETE /me/favorites/{providerId}` — add or remove a saved
/// provider for the signed-in consumer. Both idempotent; add 404s on an unknown
/// provider. Design: docs/design/consumer-favorites.md.
Future<Response> onRequest(RequestContext context, String providerId) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'user') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final favorites = context.read<FavoritesService>();
  switch (context.request.method) {
    case HttpMethod.post:
      final r = await favorites.add(principal.userId, providerId);
      if (!r.ok) return jsonError(HttpStatus.notFound, 'not_found');
      return Response(statusCode: HttpStatus.noContent);
    case HttpMethod.delete:
      await favorites.remove(principal.userId, providerId);
      return Response(statusCode: HttpStatus.noContent);
    default:
      return methodNotAllowed();
  }
}
