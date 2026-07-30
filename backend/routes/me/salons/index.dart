import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/salon_directory_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/localities/localities_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// Module `access` R6 — « Mes salons » (docs/design/
/// team-access-r6-multi-salons.md).
///
/// `GET /me/salons` — every salon the caller holds an ACTIVE membership in
/// (owned first) + the server-computed `canAddSalon` gate. A bare account
/// gets `{items: [], canAddSalon: false}` — a valid state, not an error.
///
/// `POST /me/salons` `{businessName, businessType, phoneNumber?, address?}`
/// — « Ajouter un salon » (Réseau-gated, T55): 201 the new draft salon's
/// directory entry · 403 `reseau_required` · 409 `salon_limit` · 400
/// `invalid_input`/`invalid_body`.
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  final directory = context.read<SalonDirectoryService>();

  switch (context.request.method) {
    case HttpMethod.get:
      return Response.json(
        body: {
          'items': await directory.listForAccount(principal.userId),
          'canAddSalon': await directory.canAddSalon(principal.userId),
        },
      );

    case HttpMethod.post:
      final Map<String, dynamic> body;
      try {
        body = await context.request.json() as Map<String, dynamic>;
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      // Multi-pays MP1: an optional locality pick — validated against the
      // tree; the salon's market facts derive from it (threat T57).
      final areaId = (body['areaId'] as String?)?.trim();
      SalonMarket? market;
      if (areaId != null && areaId.isNotEmpty) {
        market = await context.read<LocalitiesService>().resolveArea(areaId);
        if (market == null) {
          return jsonError(HttpStatus.badRequest, 'invalid_area');
        }
      }
      final r = await directory.addSalon(
        principal.userId,
        businessName: body['businessName'],
        businessType: body['businessType'],
        phoneNumber: body['phoneNumber'],
        address: body['address'],
        market: market,
      );
      if (!r.ok) {
        return switch (r.error) {
          'reseau_required' => jsonError(
            HttpStatus.forbidden,
            'reseau_required',
          ),
          'salon_limit' => jsonError(HttpStatus.conflict, 'salon_limit'),
          'invalid_input' => jsonError(HttpStatus.badRequest, 'invalid_input'),
          _ => jsonError(HttpStatus.forbidden, 'forbidden'),
        };
      }
      return Response.json(
        statusCode: HttpStatus.created,
        body: {'salon': r.data},
      );

    default:
      return methodNotAllowed();
  }
}
