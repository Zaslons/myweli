import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /me/notifications/read-all` — mark all the caller's notifications read.
/// Self-scoped. Design: docs/design/notification-center.md.
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  await context.read<NotificationsRepository>().markAllRead(principal.userId);
  return Response.json(body: {'status': 'ok'});
}
