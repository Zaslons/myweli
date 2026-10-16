import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/salon_directory_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
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
/// directory entry · 403 `reseau_required` · 403 `demo_account_locked`
/// (the store-review demo account, T69) · 409 `salon_limit` · 400
/// `invalid_input` · 400 `invalid_body` (not an object, or a field of the
/// wrong JSON type) · 400 `invalid_phone` (a sent `phoneNumber` that is not
/// a valid number — docs/design/phone-national-length.md §2.4).
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
      // A sent `phoneNumber` must be text: anything else is the API-wide
      // `400 invalid_body` from the reader (docs/design/phone-leftovers.md
      // §3) — #611 refused it as `invalid_phone` inside the service. Never
      // silently swapped for the account's number either way.
      final phoneNumber = optionalString(body, 'phoneNumber');
      // Multi-pays MP1: an optional locality pick — validated against the
      // tree; the salon's market facts derive from it (threat T57).
      final areaId = optionalString(body, 'areaId')?.trim();
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
        phoneNumber: phoneNumber,
        address: body['address'],
        market: market,
      );
      if (!r.ok) {
        return switch (r.error) {
          'reseau_required' => jsonError(
            HttpStatus.forbidden,
            'reseau_required',
          ),
          // Its own arm, not the `forbidden` default below: the app shows
          // the demo sentence only when it can tell the two apart.
          'demo_account_locked' => jsonError(
            HttpStatus.forbidden,
            'demo_account_locked',
          ),
          'salon_limit' => jsonError(HttpStatus.conflict, 'salon_limit'),
          'invalid_input' => jsonError(HttpStatus.badRequest, 'invalid_input'),
          'invalid_phone' => jsonError(HttpStatus.badRequest, 'invalid_phone'),
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
