import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// How a delivery-status callback proved it came from the BSP.
enum MessagingWebhookMethod {
  /// `X-Twilio-Signature` — HMAC-SHA1 over the callback URL plus the sorted POST
  /// parameters, keyed by the Twilio auth token. Twilio sends this on every
  /// webhook without being asked.
  twilioSignature,

  /// `X-Messaging-Secret` — the transitional shared secret, for a provider whose
  /// signature scheme is not implemented here.
  sharedSecret,
}

/// Authenticates `POST /webhooks/messaging/status`.
///
/// ## What this replaced, and why a header was not the answer
///
/// The webhook used to accept a shared secret as **`?secret=` in the query
/// string** — the same weakness `CronAuth` was written to remove from the cron
/// routes, where BACKEND.md T21 records it: a credential in a URL lands in Cloud
/// Run request logs, load-balancer logs and browser history. That pass missed
/// this route because its source-pin enumerated the two cron files by path
/// instead of scanning the route tree.
///
/// The obvious fix — move it to a header, as `X-Cron-Secret` did — **does not
/// work for the provider that actually calls this route.** Twilio's
/// `StatusCallback` is a URL Twilio POSTs to; Twilio's webhook documentation is
/// explicit that custom request headers cannot be configured. A header the
/// sender cannot send is not a mechanism.
///
/// So this implements what [messaging-notifications.md](../../../docs/design/messaging-notifications.md)
/// §5 already claimed the webhook did: **verify `X-Twilio-Signature`.** That
/// claim had been in the spec since the slice shipped and was never true — the
/// `?secret=` was substituted without the spec being corrected. This closes the
/// gap rather than redesigning anything.
///
/// ## The two paths, in the same order as `CronAuth`
///
///   1. **The signature**, when `TWILIO_AUTH_TOKEN` is configured. Cryptographic,
///      per-request, and needs no shared secret to exist at all.
///   2. **`X-Messaging-Secret`**, when `MESSAGING_WEBHOOK_SECRET` is configured
///      — for a BSP whose scheme is not implemented here (Termii's delivery
///      reports are a deferred follow-up) and for driving the route by hand.
///
/// Neither configured → [isConfigured] is false and the route 404s, so the
/// surface is not merely unguarded-but-present.
class MessagingWebhookAuth {
  MessagingWebhookAuth({
    required String? twilioAuthToken,
    required String? sharedSecret,
    required String? publicBaseUrl,
  }) : _twilioAuthToken = _blankToNull(twilioAuthToken),
       _sharedSecret = _blankToNull(sharedSecret),
       _publicBaseUrl = _trimTrailingSlash(_blankToNull(publicBaseUrl));

  final String? _twilioAuthToken;
  final String? _sharedSecret;

  /// The origin Twilio was told to call, e.g. `https://api.myweli.com`.
  ///
  /// **The signed URL is rebuilt from this, never from the request's `Host`
  /// header** — and that is a security property, not a convenience. Twilio signs
  /// the URL it was configured with; behind a load balancer the host the
  /// application sees need not match, so a `Host` taken from the request is both
  /// unreliable AND attacker-influenced. Letting a caller choose part of the
  /// string a signature is checked against is the whole game.
  final String? _publicBaseUrl;

  /// Whether the endpoint exists at all. Deny-by-default, matching `CronAuth`.
  ///
  /// The Twilio path additionally needs [_publicBaseUrl]: without it there is no
  /// URL to reconstruct, so a signature cannot be checked and claiming otherwise
  /// would be the failure this class exists to remove.
  bool get isConfigured =>
      (_twilioAuthToken != null && _publicBaseUrl != null) ||
      _sharedSecret != null;

  /// [requestPath] is the path only (e.g. `/webhooks/messaging/status`);
  /// [formFields] are the POST parameters as received.
  ({bool ok, MessagingWebhookMethod? method}) authenticate({
    required String? twilioSignature,
    required String? headerSecret,
    required String requestPath,
    required Map<String, String> formFields,
  }) {
    final token = _twilioAuthToken;
    final base = _publicBaseUrl;
    if (twilioSignature != null && token != null && base != null) {
      final expected = computeTwilioSignature(
        url: '$base$requestPath',
        params: formFields,
        authToken: token,
      );
      if (constantTimeEquals(twilioSignature, expected)) {
        return (ok: true, method: MessagingWebhookMethod.twilioSignature);
      }
      // Fall through rather than rejecting: during the transition a
      // misconfigured PUBLIC_BASE_URL must not be able to take delivery
      // tracking down on its own. Same reasoning as `CronAuth`.
    }

    final secret = _sharedSecret;
    if (secret != null &&
        headerSecret != null &&
        constantTimeEquals(headerSecret, secret)) {
      return (ok: true, method: MessagingWebhookMethod.sharedSecret);
    }
    return (ok: false, method: null);
  }

  /// Twilio's request signature, exactly as their `RequestValidator` computes it.
  ///
  /// Take the full URL Twilio called — scheme, host, port, path and query as
  /// configured — sort the POST parameters by name, append each `name` then
  /// `value` to that string, and HMAC-SHA1 the result with the auth token,
  /// base64-encoded.
  ///
  /// Pinned in the tests against **Twilio's own published fixture** (auth token
  /// `12345`, `https://mycompany.com/myapp.php?foo=1&bar=2`, five params →
  /// `RSOYDt4T1cUTdK1PDd93/VVr8B8=`), so the test proves the algorithm rather
  /// than restating this function.
  ///
  /// Note the sort is by **code unit**, which is what Twilio's implementations
  /// do; Twilio parameter names are ASCII, so this is not a locale question.
  static String computeTwilioSignature({
    required String url,
    required Map<String, String> params,
    required String authToken,
  }) {
    final buffer = StringBuffer(url);
    final names = params.keys.toList()..sort();
    for (final name in names) {
      buffer
        ..write(name)
        ..write(params[name]);
    }
    final mac = Hmac(sha1, utf8.encode(authToken));
    return base64.encode(mac.convert(utf8.encode(buffer.toString())).bytes);
  }

  /// Compares in time proportional to the inputs, not to how far they match.
  ///
  /// Lifted deliberately from `CronAuth`'s private copy rather than reinvented:
  /// the lengths are folded into the difference instead of returning early,
  /// because an early return leaks the secret's length — the one thing a timing
  /// attacker gets for free otherwise.
  static bool constantTimeEquals(String a, String b) {
    final ab = Uint8List.fromList(a.codeUnits);
    final bb = Uint8List.fromList(b.codeUnits);
    var diff = ab.length ^ bb.length;
    final n = ab.length < bb.length ? ab.length : bb.length;
    for (var i = 0; i < n; i++) {
      diff |= ab[i] ^ bb[i];
    }
    return diff == 0;
  }

  static String? _blankToNull(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static String? _trimTrailingSlash(String? v) =>
      (v != null && v.endsWith('/')) ? v.substring(0, v.length - 1) : v;
}
