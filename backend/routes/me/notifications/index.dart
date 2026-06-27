import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /me/notifications` — the caller's in-app notification feed (newest first,
/// ≤50). Self-scoped. Design: docs/design/notification-center.md.
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final items = await context.read<NotificationsRepository>().listForUser(
    principal.userId,
  );
  return Response.json(body: {'items': items});
}
