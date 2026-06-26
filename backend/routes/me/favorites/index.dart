import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/favorites_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /me/favorites` — the signed-in consumer's saved provider ids. Scoped to
/// the token's `sub`. Design: docs/design/consumer-favorites.md.
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'user') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final r = await context.read<FavoritesService>().list(principal.userId);
  return Response.json(body: {'providerIds': r.providerIds});
}
