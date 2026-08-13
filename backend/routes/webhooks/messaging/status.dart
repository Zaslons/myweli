import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart' show messagingWebhookAuth;
import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/messaging/messaging_service.dart';
import 'package:myweli_backend/src/messaging/webhook_auth.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /webhooks/messaging/status` — BSP delivery-status callback. Twilio sends
/// form params `MessageSid` + `MessageStatus`; we map and advance the outbox row.
/// Always 200 for known/unknown ids (idempotent).
///
/// **Authenticated by `X-Twilio-Signature`**, with `X-Messaging-Secret` as a
/// transitional fallback and a 404 when neither is configured. It used to accept
/// `?secret=` from the query string, which wrote a credential into every log
/// that records a URL — see `messaging/webhook_auth.dart` for why a plain header
/// could not replace it and what does.
///
/// Design: docs/design/messaging-notifications.md §5.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  // Deny-by-default: with nothing configured the endpoint does not exist, so
  // the surface is not merely unguarded-but-present. Same posture as the cron
  // routes.
  if (!messagingWebhookAuth.isConfigured) {
    return jsonError(HttpStatus.notFound, 'not_found');
  }

  // **The body is parsed before the caller is authenticated, and it has to be**
  // — Twilio's signature covers the POST parameters, so there is no way to check
  // it without them. That is a deliberate ordering, not an oversight: the body
  // is form-encoded and bounded, nothing is persisted before the check below,
  // and a parse failure is answered without ever consulting the outbox.
  final Map<String, String> fields;
  try {
    final form = await context.request.formData();
    fields = form.fields;
  } on Exception {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final auth = messagingWebhookAuth.authenticate(
    twilioSignature: context.request.headers['x-twilio-signature'],
    headerSecret: context.request.headers['x-messaging-secret'],
    requestPath: context.request.uri.path,
    formFields: fields,
  );
  if (!auth.ok) return jsonError(HttpStatus.forbidden, 'forbidden');
  if (auth.method == MessagingWebhookMethod.sharedSecret) {
    // The same evidence gate the cron routes carry: the fallback stays until
    // something is actually seen using it, and goes when nothing is.
    // ignore: avoid_print — this is the signal that says when it can go.
    print(
      'INFO: messaging_webhook_legacy — /webhooks/messaging/status '
      'authenticated on the shared secret, not the Twilio signature',
    );
  }

  final sid = fields['MessageSid'];
  final raw = fields['MessageStatus'];
  if (sid == null || raw == null) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final status = mapTwilioStatus(raw);
  if (status != null) {
    await context.read<MessagingService>().updateStatus(sid, status);
  }
  return Response(statusCode: HttpStatus.ok);
}
