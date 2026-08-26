import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/demo/demo_reset_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/demo/snapshot` — capture the demo salon's current state as
/// the canonical snapshot the weekly reset restores (T69). Admin-gated by
/// `/admin/_middleware.dart` like every admin surface. Takes NO body: the
/// target is derived server-side from the compile-time demo identity, so an
/// operator cannot aim it at a real salon.
/// Design: docs/design/backend-demo-review-account.md §6.2.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  final r = await context.read<DemoResetService>().capture(
    DateTime.now().toUtc(),
  );
  if (!r.ok) return jsonError(HttpStatus.conflict, r.error!);
  return Response.json(body: {'providerId': r.providerId});
}
