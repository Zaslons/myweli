import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/reviews_repository.dart';

/// `GET /providers/{id}` — full provider detail (public; reviews preview
/// embedded). `PATCH /providers/{id}` — the owner updates the salon's editable
/// public profile (name/description/address/city/commune/phone/whatsapp;
/// provider role + ownership; threat T30). Design: docs/design/consumer-reviews.md,
/// docs/design/web-m7-3e-profil.md.
Future<Response> onRequest(RequestContext context, String id) async {
  switch (context.request.method) {
    case HttpMethod.get:
      return _get(context, id);
    case HttpMethod.patch:
      return _patch(context, id);
    default:
      return methodNotAllowed();
  }
}

Future<Response> _get(RequestContext context, String id) async {
  final provider = await context.read<ProvidersRepository>().byId(id);
  if (provider == null) return jsonError(HttpStatus.notFound, 'not_found');

  final reviews = await context.read<ReviewsRepository>().recentForProvider(
    id,
    10,
  );
  return Response.json(body: {...provider, 'reviews': reviews});
}

Future<Response> _patch(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final r = await context.read<ProviderCatalogService>().updateProfile(
    principal.userId,
    id,
    body,
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
