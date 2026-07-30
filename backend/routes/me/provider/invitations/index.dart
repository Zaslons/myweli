import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/team_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /me/provider/invitations` — the signed-in pro identity's pending
/// invitations (module `access` R2b), keyed on the ACCOUNT's verified email —
/// never a client-supplied one (T37).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

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
  final email = account.email;
  if (email == null || email.isEmpty) {
    return Response.json(body: {'invitations': <Object>[]});
  }
  final invitations = await context.read<TeamService>().pendingInvitationsFor(
    email,
  );
  return Response.json(body: {'invitations': invitations});
}
