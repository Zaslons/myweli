import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/email/otp/verify` — verify an emailed code and issue a token
/// pair + user (proving inbox ownership verifies the email).
/// Design: docs/design/auth-social-email.md §5, §7.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  if (!context.read<AuthMethods>().contains('email')) {
    return jsonError(HttpStatus.notFound, 'auth_method_disabled');
  }

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final email = (body['email'] as String?)?.trim() ?? '';
  final code = (body['code'] as String?)?.trim() ?? '';
  if (!isValidEmail(email) || !isValidOtpCode(code)) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final result = await context.read<AuthRepository>().verifyEmailOtp(
    email,
    code,
  );
  return authSessionResponse(result);
}
