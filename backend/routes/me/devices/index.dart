import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:myweli_backend/src/responses.dart';

const _platforms = {'android', 'ios', 'web'};

/// `POST /me/devices` — register an FCM device token for the authed principal.
/// `DELETE /me/devices` — unregister one (logout). Self-scoped. Design:
/// docs/design/push-notifications-fcm.md.
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  final method = context.request.method;
  if (method != HttpMethod.post && method != HttpMethod.delete) {
    return methodNotAllowed();
  }

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final token = (body['token'] as String?)?.trim() ?? '';
  if (token.isEmpty || token.length > 4096) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final push = context.read<PushService>();
  if (method == HttpMethod.delete) {
    await push.unregister(principal.userId, token);
    return Response.json(body: {'status': 'unregistered'});
  }

  final platform = (body['platform'] as String?)?.trim() ?? '';
  if (!_platforms.contains(platform)) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }
  await push.register(
    userId: principal.userId,
    role: principal.role,
    token: token,
    platform: platform,
  );
  return Response.json(body: {'status': 'registered'});
}
