import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/access/team_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /me/provider/members/{memberId}/revoke` — revoke access (owner-only,
/// idempotent). Effective on the member's very next request (T38 — the
/// resolver never caches). Audited.
Future<Response> onRequest(RequestContext context, String memberId) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

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
  final r = await context.read<TeamService>().revoke(
    principal.userId,
    providerId,
    memberId,
  );
  return teamResponse(r);
}
