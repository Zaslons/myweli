import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/team_service.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /auth/provider/google` — salon sign-in with a Google ID token.
/// LOGIN-ONLY: a salon is never auto-created (`provider_not_found` → the
/// client offers registration). Design: docs/design/pro-auth-social.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  if (!context.read<AuthMethods>().contains('google')) {
    return jsonError(HttpStatus.notFound, 'auth_method_disabled');
  }

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final idToken = (body['idToken'] as String?)?.trim() ?? '';
  if (idToken.isEmpty) return jsonError(HttpStatus.badRequest, 'invalid_token');

  final claims = await context.read<GoogleIdTokenVerifier>().verify(idToken);
  if (!claims.ok) return verifierError(claims.error!);

  final result = await context.read<ProviderAuthRepository>().loginWithSocial(
    provider: 'google',
    sub: claims.sub!,
    email: claims.email,
    emailVerified: claims.emailVerified,
  );
  return _withInvitationBridge(
    context,
    result,
    claims.emailVerified ? claims.email : null,
  );
}

/// The invitation bridge (module `access` R2b): a verified identity with no
/// account but PENDING invitations gets 202 {invitations} instead of the
/// 404 — the client shows « {Salon} vous invite comme {Rôle} ».
Future<Response> _withInvitationBridge(
  RequestContext context,
  ProviderVerifyResult result,
  String? verifiedEmail,
) async {
  if (result.error == 'provider_not_found' &&
      verifiedEmail != null &&
      verifiedEmail.isNotEmpty) {
    final invitations = await context.read<TeamService>().pendingInvitationsFor(
      verifiedEmail,
    );
    if (invitations.isNotEmpty) {
      return Response.json(
        statusCode: HttpStatus.accepted,
        body: {'invitations': invitations},
      );
    }
  }
  return providerSessionResponse(result);
}
