import 'dart:convert';

import 'package:http/http.dart' as http;

import 'access_token_source.dart';
import 'push_provider.dart';

/// FCM HTTP v1 adapter. v1 is single-recipient, so we loop the (few) tokens per
/// user and `messages:send` each. A `UNREGISTERED`/404 token is reported invalid
/// so the caller prunes it. Design: docs/design/push-notifications-fcm.md §3.
class FcmV1PushProvider implements PushProvider {
  FcmV1PushProvider({
    required this.projectId,
    required AccessTokenSource tokenSource,
    http.Client? client,
  }) : _tokenSource = tokenSource,
       _client = client ?? http.Client();

  /// The Android notification channel every MyWeli push lands in — created by
  /// the app at boot and declared in its manifest as the default. Changing it
  /// here means changing it there (`kPushChannelId`).
  static const androidChannelId = 'myweli_default';

  /// Caps on the visible strings, applied at the boundary that knows FCM's
  /// limit — the whole `messages:send` payload must stay under ~4096 bytes.
  ///
  /// **Defence in depth, not the primary fix.** `_isInvalidToken` no longer
  /// mistakes a payload rejection for a dead token, so an oversized body is
  /// merely a failed send now. This exists so that if that parser is ever
  /// loosened again, the input that would exploit it never reaches FCM. Both
  /// caps sit far above anything a notification usefully displays — iOS shows
  /// about four lines — so no legitimate message is affected.
  static const maxTitleChars = 200;
  static const maxBodyChars = 1000;

  /// Truncates on **code points**, so a cut never lands mid-surrogate and
  /// produces a malformed string — which FCM would reject, reintroducing the
  /// 400 this is here to avoid.
  static String _cap(String s, int max) {
    final runes = s.runes.toList();
    if (runes.length <= max) return s;
    return '${String.fromCharCodes(runes.take(max - 1))}…';
  }

  final String projectId;
  final AccessTokenSource _tokenSource;
  final http.Client _client;

  Uri get _endpoint => Uri.parse(
    'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
  );

  @override
  Future<PushSendResult> send({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    // Nothing to do is NOT an error — reporting one here would make the signal
    // noise and it would be ignored again.
    if (tokens.isEmpty) {
      return (sent: 0, invalidTokens: const <String>[], error: null);
    }
    final accessToken = await _tokenSource.token();
    if (accessToken == null) {
      // ignore: avoid_print — this must reach the container log. A silent
      // return here is exactly how push stayed broken for months.
      print(
        'ERROR: push_auth_failed — the FCM service account could not obtain an '
        'access token. Check FCM_CLIENT_EMAIL and FCM_PRIVATE_KEY belong to the '
        'SAME service account in project $projectId. Nothing was sent.',
      );
      return (
        sent: 0,
        invalidTokens: const <String>[],
        error: 'push_auth_failed',
      );
    }

    // Capped once, outside the loop — the payload is identical per token, which
    // is precisely why an oversized one used to take out every token at once.
    final safeTitle = _cap(title, maxTitleChars);
    final safeBody = _cap(body, maxBodyChars);

    var sent = 0;
    var failed = 0;
    final invalid = <String>[];
    for (final token in tokens) {
      final payload = jsonEncode({
        'message': {
          'token': token,
          'notification': {'title': safeTitle, 'body': safeBody},
          if (data.isNotEmpty) 'data': data,
          // Per-platform delivery options (design §9): bookings are
          // time-sensitive, so both platforms get the high-priority path, and
          // Android lands in the app's declared channel (otherwise a
          // background notification would fall into the unnamed default one).
          'android': {
            'priority': 'high',
            'notification': {'channel_id': androidChannelId},
          },
          'apns': {
            'headers': {'apns-priority': '10'},
          },
        },
      });
      try {
        final res = await _client.post(
          _endpoint,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: payload,
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          sent++;
        } else if (_isInvalidToken(res)) {
          invalid.add(token);
        } else {
          // Neither delivered nor a dead token — a 500, a quota rejection, a
          // malformed payload. This used to vanish entirely.
          failed++;
          // ignore: avoid_print
          print('WARNING: push_send_failed — FCM returned ${res.statusCode}');
        }
      } catch (_) {
        failed++; // transient — leave the token, don't prune.
      }
    }
    return (
      sent: sent,
      invalidTokens: invalid,
      error: failed > 0 ? 'push_send_failed' : null,
    );
  }

  /// Whether FCM is saying **this token is dead**, as opposed to anything else
  /// having gone wrong.
  ///
  /// **What this replaced was, in effect, `if (statusCode == 400) return true`.**
  /// It substring-matched `INVALID_ARGUMENT` against the response body, and FCM
  /// v1 answers with a `google.rpc.Status` envelope whose `error.status` is the
  /// canonical gRPC code name — which for *every* 400 is literally the string
  /// `INVALID_ARGUMENT`. The match therefore narrowed nothing. The
  /// `UNREGISTERED ||` half was dead code on top: `UNREGISTERED` arrives as a
  /// **404**, whose `status` is `NOT_FOUND`.
  ///
  /// That was not merely imprecise. `send` posts an **identical payload** for
  /// every token in the fan-out, so a payload-level 400 — an oversized
  /// notification body, an invalid data key — hit 100% of them, and the caller
  /// deletes what this returns. One salon with a long enough name would have
  /// wiped the push tokens of every client who booked there.
  ///
  /// So: parse the envelope, and prune on exactly two signals. The asymmetry is
  /// deliberate — failing to prune a dead token costs a wasted request, while
  /// wrongly pruning a live one silently destroys user data until that person
  /// next cold-starts the app. When in doubt, do not prune.
  bool _isInvalidToken(http.Response res) {
    final details = _errorDetails(res.body);
    // The only unambiguous dead-token signal FCM has.
    if (res.statusCode == 404) {
      return details.any((d) => _fcmErrorCode(d) == 'UNREGISTERED');
    }
    // A 400 is about the token ONLY when a field violation names it. Anything
    // else that 400s is our bug, not the device's.
    if (res.statusCode == 400) return details.any(_namesTheToken);
    return false;
  }

  /// `error.details`, or empty when the body is not the envelope we expect.
  ///
  /// Proxies and load balancers return HTML error pages, and a truncated
  /// response is not JSON at all — both must fall through to "not a dead
  /// token", never to a prune.
  List<Map<String, dynamic>> _errorDetails(String body) {
    try {
      final root = jsonDecode(body);
      if (root is! Map) return const [];
      final error = root['error'];
      if (error is! Map) return const [];
      final details = error['details'];
      if (details is! List) return const [];
      return details.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// `details` is a heterogeneous array — match on `@type`, never on position.
  String? _fcmErrorCode(Map<String, dynamic> detail) {
    final type = detail['@type'];
    if (type is! String || !type.endsWith('FcmError')) return null;
    final code = detail['errorCode'];
    return code is String ? code : null;
  }

  bool _namesTheToken(Map<String, dynamic> detail) {
    final type = detail['@type'];
    if (type is! String || !type.endsWith('google.rpc.BadRequest')) {
      return false;
    }
    final violations = detail['fieldViolations'];
    if (violations is! List) return false;
    return violations.whereType<Map<String, dynamic>>().any(
      (v) => v['field'] == 'message.token',
    );
  }
}
