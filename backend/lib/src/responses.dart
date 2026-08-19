import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import 'auth/auth_repository.dart';
import 'auth/provider_auth_repository.dart';

/// Standard error envelope (docs/BACKEND.md §2): `{ error, message? }`.
Response jsonError(
  int statusCode,
  String error, [
  String? message,
  Map<String, String>? headers,
]) => Response.json(
  statusCode: statusCode,
  headers: headers ?? const {},
  body: {'error': error, if (message != null) 'message': message},
);

/// **Storage could not be reached** — the one upload failure that is ours, not
/// the caller's.
///
/// `UploadVerificationService` fails CLOSED on an unreachable bucket, which is
/// right, but the refusal then travelled as a **400** alongside
/// `invalid_input` and `upload_too_large` — so "your file is wrong, fix it and
/// resend" and "our storage blinked, send exactly that again" were the same
/// answer. A client cannot tell those apart, and the honest one is the only
/// one worth retrying.
///
/// `Retry-After` because a 503 conventionally invites a retry, and each
/// retried claim costs a fresh HEAD against a bucket that is already failing.
Response storageUnavailable() => jsonError(
  HttpStatus.serviceUnavailable,
  'storage_unavailable',
  null,
  const {'retry-after': '5'},
);

/// 405 for an unsupported verb.
Response methodNotAllowed() =>
    jsonError(HttpStatus.methodNotAllowed, 'method_not_allowed');

/// Maps a service result's machine code to the conventional status: ok → 200
/// with [body]; `not_found` → 404; `forbidden` → 403; `invalid_state` → 409;
/// `storage_unavailable` → **503**; `rate_limited` → **429**; anything else →
/// 400. Keeps the lifecycle route handlers thin.
///
/// **This is not the only mapping in the codebase.** `POST /appointments`,
/// `POST /appointments/{id}/deposit` and `POST /appointments/{id}/review` each
/// carry their own switch, so a code added here alone reaches two surfaces out
/// of five — the trap `routes/appointments/index.dart` already documents in a
/// comment about a 409 that shipped as a 400.
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
    case 'storage_unavailable':
      return storageUnavailable();
    // Per-identity rate limits (docs/design/backend-identity-rate-limits.md).
    // Written BEFORE anything emits it — the whole point of the ordering,
    // because `storage_unavailable` had to be retrofitted across four places
    // after the fact and shipped as a 400 from two of them in the meantime.
    case 'rate_limited':
      return jsonError(HttpStatus.tooManyRequests, 'rate_limited');
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
/// Team/invitation results (module `access` R2b): the error-code → status
/// mapping for TeamService outcomes.
Response teamResponse(
  ({bool ok, String? error, Object? data}) result, {
  int successStatus = HttpStatus.ok,
}) {
  if (result.ok) {
    return Response.json(statusCode: successStatus, body: result.data ?? {});
  }
  return switch (result.error) {
    'forbidden' => jsonError(HttpStatus.forbidden, 'forbidden'),
    'owner_protected' => jsonError(HttpStatus.forbidden, 'owner_protected'),
    'not_found' => jsonError(HttpStatus.notFound, 'not_found'),
    'member_exists' => jsonError(HttpStatus.conflict, 'member_exists'),
    'offer_required' => jsonError(HttpStatus.conflict, 'offer_required'),
    'seat_limit' => jsonError(HttpStatus.conflict, 'seat_limit'),
    'invitation_expired' => jsonError(
      HttpStatus.conflict,
      'invitation_expired',
    ),
    'invalid_state' => jsonError(HttpStatus.conflict, 'invalid_state'),
    'invite_rate_limited' => jsonError(
      HttpStatus.tooManyRequests,
      'invite_rate_limited',
    ),
    _ => jsonError(HttpStatus.badRequest, result.error ?? 'invalid_input'),
  };
}

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
