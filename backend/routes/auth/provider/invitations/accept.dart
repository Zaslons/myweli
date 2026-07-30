import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/team_service.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/provider/invitations/accept` — join a salon WITHOUT creating
/// one (module `access` R2b, §5.2 critical path). Carries the SAME identity
/// proof as login: `{invitationId, idToken}` (Google) or
/// `{invitationId, email, code}` (the email code survives the login attempt
/// unconsumed by design — it is consumed here). Creates a BARE member
/// account when none exists (the R1 provisioning guard keeps salons from
/// auto-creating), activates the membership, returns a ProviderSession
/// (201 new account / 200 existing). Threat T37: the invitation alone
/// grants nothing — the email identity must be proven.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final invitationId = (body['invitationId'] as String?)?.trim() ?? '';
  if (invitationId.isEmpty) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final repo = context.read<ProviderAuthRepository>();
  final team = context.read<TeamService>();

  // ---- Resolve + verify the identity (the register.dart branches) ---------
  String verifiedEmail;
  String authProvider;
  String? googleSub;
  String? emailCode;

  final idToken = (body['idToken'] as String?)?.trim() ?? '';
  if (idToken.isNotEmpty) {
    if (!context.read<AuthMethods>().contains('google')) {
      return jsonError(HttpStatus.notFound, 'auth_method_disabled');
    }
    final claims = await context.read<GoogleIdTokenVerifier>().verify(idToken);
    if (!claims.ok) return verifierError(claims.error!);
    if (claims.email == null || !claims.emailVerified) {
      return jsonError(HttpStatus.badRequest, 'email_not_verified');
    }
    verifiedEmail = claims.email!;
    authProvider = 'google';
    googleSub = claims.sub;
  } else {
    if (!context.read<AuthMethods>().contains('email')) {
      return jsonError(HttpStatus.notFound, 'auth_method_disabled');
    }
    final email = (body['email'] as String?)?.trim() ?? '';
    final code = (body['code'] as String?)?.trim() ?? '';
    if (!isValidEmail(email) || !isValidOtpCode(code)) {
      return jsonError(HttpStatus.badRequest, 'invalid_input');
    }
    verifiedEmail = email;
    authProvider = 'email';
    emailCode = code;
  }

  // ---- Existing account? Accept under it; else create the bare account. ---
  final existing = googleSub != null
      ? await repo.loginWithSocial(provider: 'google', sub: googleSub)
      : await repo.verifyEmailOtp(verifiedEmail, emailCode!);

  if (existing.ok) {
    final account = existing.provider!;
    final r = await team.accept(
      invitationId,
      accountId: account.id,
      accountEmail: account.email ?? verifiedEmail,
    );
    if (!r.ok) return _teamError(r.error);
    return providerSessionResponse(existing);
  }
  if (existing.error != 'provider_not_found') {
    // otp_invalid / otp_locked / verifier problems — surface as login does.
    return providerSessionResponse(existing);
  }

  final created = await repo.createMemberAccount(
    email: verifiedEmail,
    authProvider: authProvider,
    googleSub: googleSub,
    emailCode: emailCode,
  );
  if (!created.ok) return providerSessionResponse(created);

  final r = await team.accept(
    invitationId,
    accountId: created.provider!.id,
    accountEmail: verifiedEmail,
  );
  if (!r.ok) return _teamError(r.error);
  return providerSessionResponse(created, successStatus: HttpStatus.created);
}

Response _teamError(String? code) => switch (code) {
  'forbidden' => jsonError(HttpStatus.forbidden, 'forbidden'),
  'not_found' => jsonError(HttpStatus.notFound, 'not_found'),
  'invitation_expired' => jsonError(HttpStatus.conflict, 'invitation_expired'),
  _ => jsonError(HttpStatus.badRequest, code ?? 'invalid_input'),
};
