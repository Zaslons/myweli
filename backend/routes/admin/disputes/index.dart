import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/dispute_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `/admin/disputes` — `GET` lists dispute cases (filter `status`); `POST`
/// opens one against a booking `{appointmentId, reason}`. Audited.
/// Design: docs/design/admin-console.md §12.
Future<Response> onRequest(RequestContext context) async {
  final service = context.read<DisputeService>();
  switch (context.request.method) {
    case HttpMethod.get:
      final p = context.request.uri.queryParameters;
      final page = (int.tryParse(p['page'] ?? '') ?? 1).clamp(1, 1 << 30);
      final pageSize = (int.tryParse(p['pageSize'] ?? '') ?? 20).clamp(1, 100);
      final r = await service.list(
        status: p['status'],
        page: page,
        pageSize: pageSize,
      );
      return resultResponse(ok: r.ok, error: r.error, body: r.data);
    case HttpMethod.post:
      final Map<String, dynamic> body;
      try {
        body = await context.request.json() as Map<String, dynamic>;
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      final adminId = principalOf(context)!.userId;
      final r = await service.open(
        adminId,
        body['appointmentId'],
        body['reason'],
      );
      if (r.ok) return Response.json(body: r.data);
      return resultResponse(ok: r.ok, error: r.error, body: r.data);
    default:
      return methodNotAllowed();
  }
}
