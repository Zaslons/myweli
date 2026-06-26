import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/kyc_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET`/`POST /me/kyc` — the signed-in provider's KYC. `GET` reads the status;
/// `POST` submits the document metadata (uploaded to private storage via
/// `POST /uploads/sign?purpose=kyc`) and sets the status to `pending`. Self-
/// scoped to the token's provider account. Design: docs/design/pro-kyc.md.
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  final kyc = context.read<KycService>();

  switch (context.request.method) {
    case HttpMethod.get:
      final r = await kyc.status(principal.userId);
      return resultResponse(ok: r.ok, error: r.error, body: r.data);
    case HttpMethod.post:
      final Map<String, dynamic> body;
      try {
        body = await context.request.json() as Map<String, dynamic>;
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      final r = await kyc.submit(principal.userId, body['documents']);
      return resultResponse(ok: r.ok, error: r.error, body: r.data);
    default:
      return methodNotAllowed();
  }
}
