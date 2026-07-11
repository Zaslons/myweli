import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/upload_signing_service.dart';

/// `POST /uploads/sign` — issue a presigned upload for an authenticated salon.
/// Provider-only; the object key is derived server-side from the token's salon,
/// so a client can't target another salon or an arbitrary path. Image bytes go
/// client → storage directly (never through this API).
/// Design: docs/design/pro-image-upload-pipeline.md.
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  // Role gate per purpose: deposit screenshots and review photos are consumer
  // uploads; gallery and KYC are provider uploads.
  final consumerPurposes = {'deposit', 'review'};
  final requiredRole = consumerPurposes.contains(body['purpose'])
      ? 'user'
      : 'provider';
  if (principal.role != requiredRole) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final r = await context.read<UploadSigningService>().sign(
    principal.userId,
    contentType: body['contentType'],
    purpose: body['purpose'],
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
