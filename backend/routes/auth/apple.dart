import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /auth/apple` — Sign in with Apple. The identity token is verified
/// against Apple's JWKS (signature, iss, aud, exp, nonce) before any account
/// is touched. Apple sends the user's name only on FIRST authorization as a
/// separate field — accept it as a display-name hint (it is not part of the
/// signed token; never used for linking). Design:
/// docs/design/auth-social-email.md §4–5, §7.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  if (!context.read<AuthMethods>().contains('apple')) {
    return jsonError(HttpStatus.notFound, 'auth_method_disabled');
  }

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final identityToken = (body['identityToken'] as String?)?.trim() ?? '';
  if (identityToken.isEmpty) {
    return jsonError(HttpStatus.badRequest, 'invalid_token');
  }
  final nonce = (body['nonce'] as String?)?.trim();
  final fullName = (body['fullName'] as String?)?.trim();

  final claims = await context.read<AppleIdTokenVerifier>().verify(
    identityToken,
    nonce: (nonce != null && nonce.isNotEmpty) ? nonce : null,
  );
  if (!claims.ok) return _verifierError(claims.error!);

  final result = await context.read<AuthRepository>().loginWithSocial(
    provider: 'apple',
    sub: claims.sub!,
    email: claims.email,
    emailVerified: claims.emailVerified,
    name: (fullName != null && fullName.isNotEmpty) ? fullName : claims.name,
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
