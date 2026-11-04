import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/apple_tokens.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
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

  final identityToken = optionalString(body, 'identityToken')?.trim() ?? '';
  if (identityToken.isEmpty) {
    return jsonError(HttpStatus.badRequest, 'invalid_token');
  }
  final nonce = optionalString(body, 'nonce')?.trim();
  final fullName = optionalString(body, 'fullName')?.trim();
  // B6.7 — read with the other fields: a wrong type is 400 before sign-in.
  final appleCode = appleCodeOf(body);

  final verifier = context.read<AppleIdTokenVerifier>();
  final claims = await verifier.verify(
    identityToken,
    nonce: (nonce != null && nonce.isNotEmpty) ? nonce : null,
  );
  if (!claims.ok) return verifierError(claims.error!);

  final result = await context.read<AuthRepository>().loginWithSocial(
    provider: 'apple',
    sub: claims.sub!,
    email: claims.email,
    emailVerified: claims.emailVerified,
    name: (fullName != null && fullName.isNotEmpty) ? fullName : claims.name,
    avatarUrl: claims.avatarUrl,
  );
  // B6.7: the sign-in's code becomes the refresh token the account's
  // deletion revokes (docs/design/backend-integrity-batch6.md §13). After a
  // successful sign-in only; bounded, and never this sign-in's to fail.
  if (result.ok) {
    await keepAppleSignInCode(
      apple: appleCode,
      identityToken: identityToken,
      verifier: verifier,
      sub: claims.sub!,
      kind: 'user',
      accountId: result.user!.id,
      tokens: context.read<AppleTokenService>,
    );
  }
  return authSessionResponse(result);
}
