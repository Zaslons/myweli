import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// Standard error envelope (docs/BACKEND.md §2): `{ error, message? }`.
Response jsonError(int statusCode, String error, [String? message]) =>
    Response.json(
      statusCode: statusCode,
      body: {'error': error, if (message != null) 'message': message},
    );

/// 405 for an unsupported verb.
Response methodNotAllowed() =>
    jsonError(HttpStatus.methodNotAllowed, 'method_not_allowed');

/// Maps a service result's machine code to the conventional status: ok → 200
/// with [body]; `not_found` → 404; `forbidden` → 403; `invalid_state` → 409;
/// anything else → 400. Keeps the lifecycle route handlers thin.
Response resultResponse({
  required bool ok,
  required String? error,
  required Object? body,
}) {
  if (ok) return Response.json(body: body);
  switch (error) {
    case 'not_found':
      return jsonError(HttpStatus.notFound, 'not_found');
    case 'forbidden':
      return jsonError(HttpStatus.forbidden, 'forbidden');
    case 'invalid_state':
      return jsonError(HttpStatus.conflict, 'invalid_state');
    default:
      return jsonError(HttpStatus.badRequest, error ?? 'error');
  }
}
