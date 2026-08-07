import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/favorites_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /me/favorites` — the signed-in consumer's saved salons, ids AND the
/// hydrated documents. Scoped to the token's `sub`.
///
/// `providers` is **not** filtered on salon status: a favourite is a
/// relationship the client already has, and this route is authenticated, so it
/// is the one place that may serve a hidden salon's document without giving an
/// anonymous caller an oracle (`salon-state-and-refusals.md` §5, Decision C).
/// Each entry carries its `status`, so the list can mark a stopped salon
/// rather than lose the row. `providerIds` is retained for app builds already
/// in the field. Design: docs/design/consumer-favorites.md.
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
  return Response.json(
    body: {'providerIds': r.providerIds, 'providers': r.providers},
  );
}
