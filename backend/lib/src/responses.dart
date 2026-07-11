import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import 'auth/auth_repository.dart';
import 'auth/provider_auth_repository.dart';

/// Standard error envelope (docs/BACKEND.md §2): `{ error, message? }`.
Response jsonError(int statusCode, String error, [String? message]) =>
    Response.json(
      statusCode: statusCode,
      body: {'error': error, if (message != null) 'message': message},
    );

/// 405 for an unsupported verb.
Response methodNotAllowed() =>
    jsonError(HttpStatus.methodNotAllowed, 'method_not_allowed');

/// Maps a service result's machine code to the conventional status: ok → 200
/// with [body]; `not_found` → 404; `forbidden` → 403; `invalid_state` → 409;
/// anything else → 400. Keeps the lifecycle route handlers thin.
Response resultResponse({
  required bool ok,
  required String? error,
  required Object? body,
}) {
  if (ok) return Response.json(body: body);
  switch (error) {
    case 'not_found':
      return jsonError(HttpStatus.notFound, 'not_found');
    case 'forbidden':
      return jsonError(HttpStatus.forbidden, 'forbidden');
    case 'verification_required':
      return jsonError(HttpStatus.forbidden, 'verification_required');
    case 'invalid_state':
      return jsonError(HttpStatus.conflict, 'invalid_state');
    default:
      return jsonError(HttpStatus.badRequest, error ?? 'error');
  }
}

/// Shapes a login outcome as the **AuthSession** contract
/// (`{ tokens: {...}, user }` — every login endpoint returns this exact
/// nesting; drift here broke the web BFF once). Failures:
/// `account_suspended` → 403, anything else (otp_*) → 400.
Response authSessionResponse(OtpVerifyResult result) {
  if (!result.ok) {
    final status = result.error == 'account_suspended'
        ? HttpStatus.forbidden
        : HttpStatus.badRequest;
    return jsonError(status, result.error!);
  }
  final tokens = result.tokens!;
  return Response.json(
    body: {
      'tokens': {
        'accessToken': tokens.accessToken,
        'refreshToken': tokens.refreshToken,
        'expiresAt': tokens.expiresAt.toIso8601String(),
      },
      'user': result.user!.toJson(),
    },
  );
}

/// Maps an ID-token verifier failure to the conventional response:
/// malformed → 400 `invalid_token`; unconfigured → 503; else 401
/// `token_rejected`.
Response verifierError(String error) => switch (error) {
  'invalid_token' => jsonError(HttpStatus.badRequest, 'invalid_token'),
  'verifier_not_configured' => jsonError(
    HttpStatus.serviceUnavailable,
    'auth_not_configured',
  ),
  _ => jsonError(HttpStatus.unauthorized, 'token_rejected'),
};

/// Shapes a provider login outcome as the (FLAT — historical) ProviderSession
/// contract every provider login endpoint returns. Failures:
/// `provider_not_found` → 404, anything else (otp_*) → 400.
Response providerSessionResponse(
  ProviderVerifyResult result, {
  int successStatus = HttpStatus.ok,
}) {
  if (!result.ok) {
    final status = result.error == 'provider_not_found'
        ? HttpStatus.notFound
        : result.error == 'provider_exists'
        ? HttpStatus.conflict
        : HttpStatus.badRequest;
    return jsonError(status, result.error!);
  }
  final tokens = result.tokens!;
  return Response.json(
    statusCode: successStatus,
    body: {
      'provider': result.provider!.toJson(),
      'accessToken': tokens.accessToken,
      'refreshToken': tokens.refreshToken,
      'expiresAt': tokens.expiresAt.toIso8601String(),
    },
  );
}
