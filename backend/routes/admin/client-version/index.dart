import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_client_version_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /admin/client-version` — every floor.
/// `PUT /admin/client-version` — set one, audited as `client_floor.set`.
///
/// Admin-gated by `routes/admin/_middleware.dart`. Design:
/// docs/design/client-version-gate.md §6.
Future<Response> onRequest(RequestContext context) async {
  final svc = context.read<AdminClientVersionService>();

  switch (context.request.method) {
    case HttpMethod.get:
      final r = await svc.list();
      return resultResponse(ok: r.ok, error: r.error, body: r.data);

    case HttpMethod.put:
      final Map<String, dynamic> body;
      try {
        body = await context.request.json() as Map<String, dynamic>;
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      final adminId = principalOf(context)!.userId;
      final r = await svc.set(
        adminId,
        appId: body['appId'],
        platform: body['platform'],
        minimumBuild: body['minimumBuild'],
        recommendedBuild: body['recommendedBuild'],
        updateUrl: body['updateUrl'],
      );
      if (r.ok) return Response.json(body: r.data);
      return switch (r.error) {
        'not_found' => jsonError(HttpStatus.notFound, 'not_found'),
        _ => jsonError(HttpStatus.badRequest, r.error ?? 'invalid_input'),
      };

    default:
      return methodNotAllowed();
  }
}
