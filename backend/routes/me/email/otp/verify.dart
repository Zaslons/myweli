import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/email_change_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /me/email/otp/verify` — proves the new address by its code (and the
/// current one by `currentCode` when decision 265 asks for it) and makes it
/// the signed-in consumer's, proven. `409 email_taken` only once the code is
/// right, and the code is then left for its owner's sign-in (§3.1).
///
/// Design: docs/design/account-email-change.md §3.1, §5.2–§5.3 (B16.3).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'user') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (!context.read<AuthMethods>().contains('email')) {
    return jsonError(HttpStatus.notFound, 'auth_method_disabled');
  }

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final email = optionalString(body, 'email')?.trim() ?? '';
  final code = optionalString(body, 'code')?.trim() ?? '';
  final currentCode = optionalString(body, 'currentCode')?.trim();
  if (!isValidEmail(email) ||
      !isValidOtpCode(code) ||
      (currentCode != null && !isValidOtpCode(currentCode))) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final r = await context.read<EmailChangeService>().verify(
    principal.userId,
    email,
    code,
    currentCode: currentCode,
  );
  if (r.ok) return Response.json(body: r.user!.toJson());
  final error = r.error!;
  return switch (error) {
    'email_taken' || 'email_unchanged' => jsonError(HttpStatus.conflict, error),
    'account_suspended' => jsonError(HttpStatus.forbidden, error),
    'not_found' => jsonError(HttpStatus.notFound, error),
    'rate_limited' => jsonError(HttpStatus.tooManyRequests, error),
    // The code's refusals, the new address's or the current one's: each a
    // 400, as at sign-in (`authSessionResponse`).
    _ => jsonError(HttpStatus.badRequest, error),
  };
}
