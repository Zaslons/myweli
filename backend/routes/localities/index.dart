import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/localities/localities_service.dart';

/// GET /localities — the public locality reference tree (multi-pays MP1,
/// docs/design/multi-pays-end-version.md §2): countries → operators + cities
/// → areas. Read-only, parameterless, zero PII; served from a process cache
/// and marked CDN-cacheable (threat T56).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'method_not_allowed'},
    );
  }
  final tree = await context.read<LocalitiesService>().tree();
  return Response.json(
    body: tree,
    headers: {'Cache-Control': 'public, max-age=3600'},
  );
}
