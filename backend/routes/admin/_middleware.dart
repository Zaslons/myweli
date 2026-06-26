import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// Trust boundary for `/admin/*` (docs/BACKEND.md §7 T17): every endpoint except
/// auth (login/refresh) requires an **admin** access token. Deny by default —
/// admins are global (they bypass tenant ownership), so this gate + the audit
/// log are the only things standing between the team and everyone's data.
Handler middleware(Handler handler) {
  return (context) {
    final path = context.request.uri.path;
    if (path.startsWith('/admin/auth')) return handler(context);

    final principal = principalOf(context);
    if (principal == null) {
      return jsonError(HttpStatus.unauthorized, 'unauthorized');
    }
    if (principal.role != 'admin') {
      return jsonError(HttpStatus.forbidden, 'forbidden');
    }
    return handler(context);
  };
}
