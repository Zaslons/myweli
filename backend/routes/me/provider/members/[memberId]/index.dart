import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/access/team_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `PATCH /me/provider/members/{memberId}` `{role, artistId?}` — change a
/// member's role (owner-only; the OWNER row is immutable → 403
/// `owner_protected`, threat T36). Audited.
Future<Response> onRequest(RequestContext context, String memberId) async {
  if (context.request.method != HttpMethod.patch) return methodNotAllowed();

  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  final providerId = await context.read<MembershipService>().activeSalonFor(
    principal.userId,
  );
  if (providerId == null) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final r = await context.read<TeamService>().changeRole(
    principal.userId,
    providerId,
    memberId,
    role: body['role'],
    artistId: body['artistId'],
  );
  return teamResponse(r);
}
