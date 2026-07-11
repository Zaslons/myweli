import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/team_service.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/provider/invitations/decline` — refuse an invitation without
/// creating anything (module `access` R2b). The same identity proof as the
/// accept: `{invitationId, idToken}` or `{invitationId, email, code}` —
/// declining must prove the email too (T37: a third party can't clear
/// someone's invitations).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final invitationId = (body['invitationId'] as String?)?.trim() ?? '';
  if (invitationId.isEmpty) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  String verifiedEmail;
  final idToken = (body['idToken'] as String?)?.trim() ?? '';
  if (idToken.isNotEmpty) {
    if (!context.read<AuthMethods>().contains('google')) {
      return jsonError(HttpStatus.notFound, 'auth_method_disabled');
    }
    final claims = await context.read<GoogleIdTokenVerifier>().verify(idToken);
    if (!claims.ok) return verifierError(claims.error!);
    if (claims.email == null || !claims.emailVerified) {
      return jsonError(HttpStatus.badRequest, 'email_not_verified');
    }
    verifiedEmail = claims.email!;
  } else {
    if (!context.read<AuthMethods>().contains('email')) {
      return jsonError(HttpStatus.notFound, 'auth_method_disabled');
    }
    final email = (body['email'] as String?)?.trim() ?? '';
    final code = (body['code'] as String?)?.trim() ?? '';
    if (!isValidEmail(email) || !isValidOtpCode(code)) {
      return jsonError(HttpStatus.badRequest, 'invalid_input');
    }
    // Validate the code WITHOUT consuming it (the invitee may still accept
    // another invitation with the same code).
    final probe = await context.read<ProviderAuthRepository>().verifyEmailOtp(
      email,
      code,
    );
    if (!probe.ok && probe.error != 'provider_not_found') {
      return providerSessionResponse(probe);
    }
    verifiedEmail = email;
  }

  final r = await context.read<TeamService>().declineById(
    invitationId,
    email: verifiedEmail,
  );
  if (!r.ok) {
    return switch (r.error) {
      'forbidden' => jsonError(HttpStatus.forbidden, 'forbidden'),
      'not_found' => jsonError(HttpStatus.notFound, 'not_found'),
      _ => jsonError(HttpStatus.badRequest, r.error ?? 'invalid_input'),
    };
  }
  return Response.json(body: {'declined': true});
}
