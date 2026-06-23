import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// Liveness probe. `GET` → 200 with a small JSON payload; other verbs → 405.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'method_not_allowed'},
    );
  }
  return Response.json(
    body: {
      'status': 'ok',
      'service': 'myweli-api',
      'time': DateTime.now().toUtc().toIso8601String(),
    },
  );
}
