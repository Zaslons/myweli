import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/otp/verify` — verify a code and issue a token pair + user.
/// Dormant at launch (see otp/request.dart).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  if (!context.read<AuthMethods>().contains('phone')) {
    return jsonError(HttpStatus.notFound, 'auth_method_disabled');
  }

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final phone = optionalString(body, 'phoneNumber')?.trim() ?? '';
  final code = optionalString(body, 'code')?.trim() ?? '';
  // Each field its own code, so a client can tell the number from the code
  // (docs/design/phone-leftovers.md §2) — they used to share `invalid_input`.
  if (!isValidPhoneNumber(phone)) {
    return jsonError(HttpStatus.badRequest, 'invalid_phone');
  }
  if (!isValidOtpCode(code)) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final result = await context.read<AuthRepository>().verifyOtp(phone, code);
  return authSessionResponse(result);
}
