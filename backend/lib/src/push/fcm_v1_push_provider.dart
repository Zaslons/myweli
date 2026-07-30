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
    if (tokens.isEmpty) return (sent: 0, invalidTokens: const <String>[]);
    final accessToken = await _tokenSource.token();
    if (accessToken == null) {
      return (sent: 0, invalidTokens: const <String>[]);
    }

    var sent = 0;
    final invalid = <String>[];
    for (final token in tokens) {
      final payload = jsonEncode({
        'message': {
          'token': token,
          'notification': {'title': title, 'body': body},
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
        }
      } catch (_) {
        // transient — leave the token, don't prune.
      }
    }
    return (sent: sent, invalidTokens: invalid);
  }

  /// FCM marks a stale token with 404 (UNREGISTERED) or 400 (invalid argument).
  bool _isInvalidToken(http.Response res) {
    if (res.statusCode == 404) return true;
    if (res.statusCode == 400) {
      return res.body.contains('UNREGISTERED') ||
          res.body.contains('INVALID_ARGUMENT');
    }
    return false;
  }
}
