import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/smoke_seam.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/email/otp/request` — dispatch a one-time code to an email.
/// The response is identical whether or not the address maps to an account
/// (no enumeration — threat model T32). Design:
/// docs/design/auth-social-email.md §5, §7–8.
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

  final result = await context.read<AuthRepository>().requestEmailOtp(email);
  if (!result.ok) {
    return jsonError(HttpStatus.tooManyRequests, result.error!);
  }

  // Deliver the code (best-effort; never logs it). In dev the LogProvider
  // no-ops and `devCode` is echoed below.
  if (result.code != null) {
    final sent = await context.read<EmailProvider>().send(
      // COLD: an anonymous caller picked this address. Budgeted tightly —
      // docs/design/backend-email-send-budget.md §2.
      classification: EmailClass.cold,
      to: email,
      subject: otpEmailSubject,
      text: renderOtpEmailText(result.code!),
      html: renderOtpEmailHtml(result.code!),
    );
    // `requestEmailOtp` already spent one of this caller's four resends, and
    // the budget then declined to send for reasons that have nothing to do
    // with them. Left alone, an hour-long global ceiling becomes a per-user
    // lockout that OUTLASTS it: four silent retries, then a hard
    // `otp_resend_limit` that survives the window reset.
    //
    // A PROVIDER failure is deliberately not refunded — that was a real
    // delivery attempt. docs/design/backend-email-send-budget.md §9.
    // The response is IDENTICAL either way — 202 with the same body — so this is
    // not an address-exists oracle: budget exhaustion is global, not per-address,
    // and leaks nothing about the recipient. A handler test drives the real route
    // against an exhausted budget and a fresh one and fails if they differ.
    if (sent.error == 'send_budget_exhausted') {
      await context.read<AuthRepository>().refundEmailOtpResend(email);
    }
  }

  // Off-prod `devCode` is unchanged. In production it is null, and the ONLY
  // way to get the code back is the Q1b seam: a constant-time secret match AND
  // an identity in the RFC 2606 `.test` TLD, which no configuration can widen
  // to a real address. docs/design/backend-q1b-smoke-seam.md.
  final disclosed =
      result.devCode ??
      (context.read<SmokeSeam>().allows(
            providedSecret: context.request.headers['x-smoke-secret'],
            identifier: email,
          )
          ? result.code
          : null);

  return Response.json(
    statusCode: HttpStatus.accepted,
    body: {
      'expiresInSeconds': result.expiresInSeconds,
      if (disclosed != null) 'devCode': disclosed,
    },
  );
}
