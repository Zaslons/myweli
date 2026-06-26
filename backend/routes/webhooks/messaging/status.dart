import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart'
    show messagingWebhookSecret;
import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/messaging/messaging_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /webhooks/messaging/status` — BSP delivery-status callback. Twilio sends
/// form params `MessageSid` + `MessageStatus`; we map and advance the outbox row.
/// Guarded by a shared `?secret=` (deny-by-default when configured). Always 200
/// for known/unknown ids (idempotent). Design: docs/design/messaging-notifications.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final secret = messagingWebhookSecret;
  if (secret != null &&
      context.request.uri.queryParameters['secret'] != secret) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final form = await context.request.formData();
  final sid = form.fields['MessageSid'];
  final raw = form.fields['MessageStatus'];
  if (sid == null || raw == null) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final status = mapTwilioStatus(raw);
  if (status != null) {
    await context.read<MessagingService>().updateStatus(sid, status);
  }
  return Response(statusCode: HttpStatus.ok);
}
