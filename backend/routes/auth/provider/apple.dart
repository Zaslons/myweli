import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/apple_tokens.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /auth/provider/apple` — salon Sign in with Apple (login-only; the
/// seam mirrors /auth/provider/google). Design: docs/design/pro-auth-social.md.
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
  // B6.7 — read with the other fields: a wrong type is 400 before sign-in.
  final appleCode = appleCodeOf(body);

  final verifier = context.read<AppleIdTokenVerifier>();
  final claims = await verifier.verify(
    identityToken,
    nonce: (nonce != null && nonce.isNotEmpty) ? nonce : null,
  );
  if (!claims.ok) return verifierError(claims.error!);

  final result = await context.read<ProviderAuthRepository>().loginWithSocial(
    provider: 'apple',
    sub: claims.sub!,
    email: claims.email,
    emailVerified: claims.emailVerified,
  );
  // B6.7 — kept under the Pro account, which its deletion revokes
  // (docs/design/backend-integrity-batch6.md §13).
  if (result.ok) {
    await keepAppleSignInCode(
      apple: appleCode,
      identityToken: identityToken,
      verifier: verifier,
      sub: claims.sub!,
      kind: 'provider',
      accountId: result.provider!.id,
      tokens: context.read<AppleTokenService>,
    );
  }
  return providerSessionResponse(result);
}
