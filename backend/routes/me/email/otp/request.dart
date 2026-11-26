import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/email_change_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /me/email/otp/request` — the first step of changing the signed-in
/// consumer's address: a code to the new one, and to the current one when it
/// is the account's only way in (decision 265). The same answer whether or
/// not the new address has an account (T32); « taken » is said only at the
/// verify, to whoever proves the inbox (decision 262).
///
/// The account is the token's, never an id from the body. Per IP, under the
/// same limit as `/auth/` (`isIpLimitedPath`); per account, the service's.
/// Design: docs/design/account-email-change.md §3.1 (B16.3).
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
  if (!isValidEmail(email)) {
    return jsonError(HttpStatus.badRequest, 'invalid_email');
  }

  final r = await context.read<EmailChangeService>().request(
    principal.userId,
    email,
  );
  if (!r.ok) {
    return switch (r.error) {
      'not_found' => jsonError(HttpStatus.notFound, 'not_found'),
      'account_suspended' => jsonError(
        HttpStatus.forbidden,
        'account_suspended',
      ),
      'email_unchanged' => jsonError(HttpStatus.conflict, 'email_unchanged'),
      final error => jsonError(HttpStatus.tooManyRequests, error!),
    };
  }
  return Response.json(
    statusCode: HttpStatus.accepted,
    body: {
      'expiresInSeconds': r.expiresInSeconds,
      'currentCodeSent': r.currentCodeSent,
      if (r.devCode != null) 'devCode': r.devCode,
      if (r.currentDevCode != null) 'currentDevCode': r.currentDevCode,
    },
  );
}
