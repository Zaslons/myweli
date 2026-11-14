import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_provider_account_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:myweli_backend/src/responses.dart';

/// `DELETE /admin/provider-accounts/{id}/erase`
/// `{confirmEmail, reason, caseRef}` — erase a Pro account on a support
/// request (B0.25's server half). Audited, irreversible.
///
/// Runs the same deletion as `DELETE /me/provider`, through the same service
/// singleton, so the demo lock (T69) and the future-bookings gate hold here
/// too, with no override. Exists because the request comes by e-mail from
/// someone who cannot reach « Profil ».
///
/// DELETE on a sub-path, as `DELETE /admin/users/{id}/erase`: an
/// irreversible verb never shares the URL of a support view.
///
/// 204. 400 `invalid_body` (not a JSON object, or a field of the wrong JSON
/// type) · `invalid_input` (a field missing or empty, `reason` outside the
/// set, `caseRef` off pattern). 401 / 403 (the `/admin` gate). 403
/// `demo_account_locked`. 404 `not_found` (unknown id, or erased already).
/// 409 `confirmation_mismatch` · `future_bookings`. Each code its own arm:
/// the precedent's catch-all would answer the demo lock as a 404.
///
/// Design: docs/design/admin-pro-account-erase.md §3.1; threat T83.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.delete) return methodNotAllowed();

  final Object? body;
  try {
    body = await context.request.json();
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  if (body is! Map<String, dynamic>) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  // Every field read before any is acted on: a wrong JSON type throws, and
  // the outermost middleware answers it 400 `invalid_body`.
  final confirmEmail = optionalString(body, 'confirmEmail');
  final reason = optionalString(body, 'reason');
  final caseRef = optionalString(body, 'caseRef');

  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<AdminProviderAccountService>().erase(
    adminId,
    id,
    confirmEmail: confirmEmail,
    reason: reason,
    caseRef: caseRef,
  );
  if (r.ok) return Response(statusCode: HttpStatus.noContent);
  return switch (r.error) {
    'invalid_input' => jsonError(HttpStatus.badRequest, 'invalid_input'),
    'not_found' => jsonError(HttpStatus.notFound, 'not_found'),
    'demo_account_locked' => jsonError(
      HttpStatus.forbidden,
      'demo_account_locked',
    ),
    'confirmation_mismatch' => jsonError(
      HttpStatus.conflict,
      'confirmation_mismatch',
    ),
    'future_bookings' => jsonError(HttpStatus.conflict, 'future_bookings'),
    // A code nobody mapped is our bug, never the caller's: thrown, so the
    // outermost middleware answers 500 and reports it.
    final other => throw StateError('unmapped erase outcome: $other'),
  };
}
