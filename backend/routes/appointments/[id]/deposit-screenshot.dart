import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/deposit_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /appointments/{id}/deposit-screenshot` — a short-lived **signed** view
/// URL for the deposit screenshot, restricted to the booking's consumer or its
/// salon. The bytes live in private storage; this never serves them through the
/// API. Design: docs/design/consumer-deposit.md.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final r = await context.read<DepositService>().screenshotUrl(
    id,
    sub: principal.userId,
    role: principal.role,
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
