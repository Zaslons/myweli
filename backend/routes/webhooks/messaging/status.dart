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
  // it without them. That inverts the usual order, so the two things it exposes
  // are bounded explicitly rather than assumed.
  //
  // First, size. An unauthenticated caller now decides how much work the parse
  // does: buffer, split, decode, sort and HMAC. Twilio's status callbacks are
  // under a kilobyte, so anything above this cap is not one.
  if (MessagingWebhookAuth.exceedsBodyCap(
    context.request.headers[HttpHeaders.contentLengthHeader],
  )) {
    return jsonError(HttpStatus.requestEntityTooLarge, 'payload_too_large');
  }

  // Second, failure mode. `formData()` throws `StateError` on a non-form
  // content type — an **`Error`, not an `Exception`** — so `on Exception` here
  // caught nothing and a `POST` with `content-type: application/json` from
  // anyone on the internet became a 500 and a reported error event. Catching
  // the supertype is right precisely because this runs before authentication:
  // the caller is unknown, so no throw from parsing their input is a fault of
  // ours to report.
  final Map<String, String> fields;
  try {
    final form = await context.request.formData();
    fields = form.fields;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final uri = context.request.uri;
  final auth = messagingWebhookAuth.authenticate(
    twilioSignature: context.request.headers['x-twilio-signature'],
    headerSecret: context.request.headers['x-messaging-secret'],
    // Path AND query: Twilio signs the URL as configured, so a callback
    // registered with any query parameter must still verify.
    requestPathAndQuery: uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path,
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
