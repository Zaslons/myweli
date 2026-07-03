import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/provider/email/otp/request` — dispatch a one-time code to a
/// salon's email (login AND registration use it — the register endpoint
/// consumes the same code). Identical response whether or not the address maps
/// to an account (no enumeration). Design: docs/design/pro-auth-social.md.
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
  if (!isValidEmail(email)) {
    return jsonError(HttpStatus.badRequest, 'invalid_email');
  }

  final result = await context.read<ProviderAuthRepository>().requestEmailOtp(
    email,
  );
  if (!result.ok) {
    return jsonError(HttpStatus.tooManyRequests, result.error!);
  }

  if (result.code != null) {
    await context.read<EmailProvider>().send(
      to: email,
      subject: otpEmailSubject,
      text: renderOtpEmailText(result.code!),
      html: renderOtpEmailHtml(result.code!),
    );
  }

  return Response.json(
    statusCode: HttpStatus.accepted,
    body: {
      'expiresInSeconds': result.expiresInSeconds,
      if (result.devCode != null) 'devCode': result.devCode,
    },
  );
}
