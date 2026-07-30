import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/team_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /me/provider/invitations/{invitationId}/accept` — join the salon
/// under the CURRENT session (module `access` R2b). The session is the
/// identity proof; the invitation must target the account's own verified
/// email (mismatch → 403, T37). Expired → 409 `invitation_expired`.
Future<Response> onRequest(RequestContext context, String invitationId) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  final account = await context.read<ProviderAuthRepository>().accountById(
    principal.userId,
  );
  if (account == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  final r = await context.read<TeamService>().accept(
    invitationId,
    accountId: account.id,
    accountEmail: account.email ?? '',
  );
  return teamResponse(r);
}
