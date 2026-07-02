import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /auth/google` — sign in with a Google ID token. The token is verified
/// against Google's JWKS (signature, iss, aud, exp, verified email) before any
/// account is touched; on success the user is found/created/linked and our own
/// session (JWT + rotating refresh) is issued.
/// Design: docs/design/auth-social-email.md §5, §7.
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
  if (!claims.ok) return _verifierError(claims.error!);

  final result = await context.read<AuthRepository>().loginWithSocial(
    provider: 'google',
    sub: claims.sub!,
    email: claims.email,
    emailVerified: claims.emailVerified,
    name: claims.name,
    avatarUrl: claims.avatarUrl,
  );
  return authSessionResponse(result);
}

Response _verifierError(String error) => switch (error) {
  'invalid_token' => jsonError(HttpStatus.badRequest, 'invalid_token'),
  'verifier_not_configured' => jsonError(
    HttpStatus.serviceUnavailable,
    'auth_not_configured',
  ),
  _ => jsonError(HttpStatus.unauthorized, 'token_rejected'),
};
