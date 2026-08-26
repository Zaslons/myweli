import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/team_service.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/provider/email/otp/verify` — verify an emailed code and issue
/// a ProviderSession. LOGIN-ONLY: a correct code with no salon returns 404
/// `provider_not_found` (code NOT consumed — the register screen reuses it).
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

  final repo = context.read<ProviderAuthRepository>();

  // The demo identity (T69): when the FIXED code matches (constant-time; seam
  // absent → this is false and the demo address behaves like any unknown
  // one), mint a real OTP record and consume it immediately — so everything
  // downstream (session family, email_verified, LOGIN-ONLY 404, the
  // invitation bridge) is the production path, not a parallel one. The
  // reviewer-visible code never touches the repository; the repository's code
  // never leaves this handler. The resend slot is refunded: no delivery was
  // attempted. Design: docs/design/backend-demo-review-account.md §5.
  if (context.read<DemoSeam>().allows(email: email, otp: code)) {
    final minted = await repo.requestEmailOtp(email);
    if (!minted.ok) {
      return jsonError(HttpStatus.tooManyRequests, minted.error!);
    }
    await repo.refundEmailOtpResend(email);
    final result = await repo.verifyEmailOtp(email, minted.code!);
    return _withInvitationBridge(context, result, email);
  }

  final result = await repo.verifyEmailOtp(email, code);
  return _withInvitationBridge(context, result, email);
}

/// The invitation bridge (module `access` R2b): a verified identity with no
/// account but PENDING invitations gets 202 {invitations} instead of the
/// 404 — the client shows « {Salon} vous invite comme {Rôle} ».
Future<Response> _withInvitationBridge(
  RequestContext context,
  ProviderVerifyResult result,
  String? verifiedEmail,
) async {
  if (result.error == 'provider_not_found' &&
      verifiedEmail != null &&
      verifiedEmail.isNotEmpty) {
    final invitations = await context.read<TeamService>().pendingInvitationsFor(
      verifiedEmail,
    );
    if (invitations.isNotEmpty) {
      return Response.json(
        statusCode: HttpStatus.accepted,
        body: {'invitations': invitations},
      );
    }
  }
  return providerSessionResponse(result);
}
