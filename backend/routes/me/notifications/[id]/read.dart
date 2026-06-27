import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /me/notifications/{id}/read` — mark one of the caller's notifications
/// read (404 if it isn't theirs / doesn't exist). Self-scoped.
/// Design: docs/design/notification-center.md.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final ok = await context.read<NotificationsRepository>().markRead(
    principal.userId,
    id,
  );
  if (!ok) return jsonError(HttpStatus.notFound, 'not_found');
  return Response.json(body: {'status': 'ok'});
}
