import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/upload_signing_service.dart';

/// `POST /uploads/sign` — issue a presigned upload to an authenticated caller.
///
/// **Not provider-only** (this comment said so for three consumer purposes'
/// worth of drift): the role is gated PER PURPOSE below. Either way the object
/// key is derived server-side from the token, so a client can never target
/// another tenant or an arbitrary path, and bytes go client → storage directly
/// (never through this API).
///
/// Designs: docs/design/pro-image-upload-pipeline.md, consumer-deposit.md,
/// reviews-photos-reporting.md, consumer-avatar-upload.md.
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

  // Role gate per purpose: deposit screenshots, review photos and profile
  // photos are consumer uploads; gallery and KYC are provider uploads. The
  // gate is symmetric — a provider token asking for a consumer purpose is a
  // 403 too, so neither role can borrow the other's namespace.
  final consumerPurposes = {'deposit', 'review', 'avatar'};
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
    // R6: gallery uploads may target a selected salon (T55).
    salonId: context.request.uri.queryParameters['salonId'],
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
