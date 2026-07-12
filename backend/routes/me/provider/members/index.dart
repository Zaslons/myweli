import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/access/team_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// The salon's team (module `access` R2b — docs/design/
/// team-access-r2b-invitations.md). Owner-only (`members.manage`, T36);
/// the salon DEFAULTS from the caller's membership; R6: `?salonId=` selects
/// among the caller's ACTIVE memberships (invalid → uniform 403, T55).
///
/// `GET /me/provider/members` — the member list, owner first, pending
/// invitations included (with artist names + expiry flags).
/// `POST /me/provider/members` `{email, role, artistId?}` — invite. Gates:
/// role ∈ manager/reception/staff · staff ⇒ a salon-owned artist ·
/// 409 `member_exists`/`offer_required`/`seat_limit` · 429
/// `invite_rate_limited` (T37).
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  // R6: the salon defaults from the caller's membership; an explicit
  // `?salonId=` is honored only against an ACTIVE membership (T55).
  final providerId = await context.read<MembershipService>().salonForRequest(
    principal.userId,
    salonId: context.request.uri.queryParameters['salonId'],
  );
  if (providerId == null) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  final team = context.read<TeamService>();

  switch (context.request.method) {
    case HttpMethod.get:
      final r = await team.list(principal.userId, providerId);
      return teamResponse(r);

    case HttpMethod.post:
      final Map<String, dynamic> body;
      try {
        body = await context.request.json() as Map<String, dynamic>;
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      final r = await team.invite(
        principal.userId,
        providerId,
        email: body['email'],
        role: body['role'],
        artistId: body['artistId'],
      );
      return teamResponse(r, successStatus: HttpStatus.created);

    default:
      return methodNotAllowed();
  }
}
