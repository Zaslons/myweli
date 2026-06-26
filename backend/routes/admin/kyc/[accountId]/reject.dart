import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_kyc_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/kyc/{accountId}/reject` — body `{reason}` (required); sets the
/// provider's verification to `rejected` (audited). Design: docs/design/admin-console.md.
Future<Response> onRequest(RequestContext context, String accountId) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<AdminKycService>().reject(
    adminId,
    accountId,
    body['reason'],
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
