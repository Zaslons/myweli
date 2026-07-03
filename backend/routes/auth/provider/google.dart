import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
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
  return providerSessionResponse(result);
}
