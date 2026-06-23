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
