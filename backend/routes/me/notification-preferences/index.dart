import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /me/notification-preferences` — the caller's prefs (all-true defaults).
/// `PUT` — partial update `{ reminders?, marketing?, push? }`; each provided
/// field must be a bool. Self-scoped (keyed by `principal.userId`; no path id).
/// Design: docs/design/notification-preferences.md (FR-NOTIF-004).
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  final repo = context.read<NotificationPrefsRepository>();

  switch (context.request.method) {
    case HttpMethod.get:
      final prefs = await repo.get(principal.userId);
      return Response.json(body: prefs.toJson());

    case HttpMethod.put:
      final Object? raw;
      try {
        raw = await context.request.json();
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      if (raw is! Map<String, dynamic>) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      final map = raw;
      bool ok(String k) => !map.containsKey(k) || map[k] is bool;
      if (!ok('reminders') || !ok('marketing') || !ok('push')) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      final prefs = await repo.update(
        principal.userId,
        reminders: map['reminders'] as bool?,
        marketing: map['marketing'] as bool?,
        push: map['push'] as bool?,
      );
      return Response.json(body: prefs.toJson());

    default:
      return methodNotAllowed();
  }
}
