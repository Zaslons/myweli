import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/push/access_token_source.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/push/fcm_v1_push_provider.dart';
import 'package:myweli_backend/src/push/push_provider.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:test/test.dart';

import '../routes/me/devices/index.dart' as devices_route;
import 'http/observed.dart';

class _MockRequestContext extends Mock implements RequestContext {}

class _FakeTokenSource implements AccessTokenSource {
  _FakeTokenSource(this._t);
  final String? _t;
  @override
  Future<String?> token() async => _t;
}

class _FakeProvider implements PushProvider {
  final List<String> seen = [];
  List<String> invalid = const [];
  @override
  Future<PushSendResult> send({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    seen.addAll(tokens);
    // Answers for the tokens of THIS call only — the service makes one call
    // per kind (app, browsers).
    final dead = [
      for (final t in tokens)
        if (invalid.contains(t)) t,
    ];
    return (
      sent: tokens.length - dead.length,
      invalidTokens: dead,
      error: null,
    );
  }
}

void main() {
  group('InMemoryDeviceTokenRepository', () {
    test('upsert reassigns owner; scoped delete; tokensForUser', () async {
      final repo = InMemoryDeviceTokenRepository();
      await repo.upsert(
        token: 't1',
        userId: 'u1',
        role: 'user',
        platform: 'android',
      );
      await repo.upsert(
        token: 't2',
        userId: 'u1',
        role: 'user',
        platform: 'ios',
      );
      expect((await repo.tokensForUser('u1')).toSet(), {'t1', 't2'});

      // re-register t1 to u2 → moves ownership
      await repo.upsert(
        token: 't1',
        userId: 'u2',
        role: 'user',
        platform: 'web',
      );
      expect(await repo.tokensForUser('u1'), ['t2']);
      expect(await repo.tokensForUser('u2'), ['t1']);

      // scoped delete: u1 can't remove u2's token
      await repo.removeForUser('u1', 't1');
      expect(await repo.tokensForUser('u2'), ['t1']);
      await repo.removeForUser('u2', 't1');
      expect(await repo.tokensForUser('u2'), isEmpty);
    });
  });

  group('devicesForUser — the platform rides along (web-pro-browser-push)', () {
    test('each token with the platform it registered with', () async {
      final repo = InMemoryDeviceTokenRepository();
      await repo.upsert(
        token: 'phone',
        userId: 'u1',
        role: 'provider',
        platform: 'android',
      );
      await repo.upsert(
        token: 'desk',
        userId: 'u1',
        role: 'provider',
        platform: 'web',
      );
      await repo.upsert(
        token: 'other',
        userId: 'u2',
        role: 'provider',
        platform: 'ios',
      );
      expect((await repo.devicesForUser('u1')).toSet(), {
        (token: 'phone', platform: 'android'),
        (token: 'desk', platform: 'web'),
      });
      expect(await repo.devicesForUser('nobody'), isEmpty);
    });
  });

  /// docs/design/web-pro-browser-push.md §4, Q1: FCM accepts a push to a
  /// CLOSED browser, so the salon notifier must know what reached the APP —
  /// a browser's count can never stand for it.
  group('PushService.sendToUserByKind — the app and browsers apart', () {
    late InMemoryDeviceTokenRepository repo;
    setUp(() async {
      repo = InMemoryDeviceTokenRepository();
      for (final (token, platform) in [
        ('a1', 'android'),
        ('i1', 'ios'),
        ('w1', 'web'),
        ('w2', 'web'),
      ]) {
        await repo.upsert(
          token: token,
          userId: 'u1',
          role: 'provider',
          platform: platform,
        );
      }
    });

    test('counts what reached the app and what reached browsers', () async {
      final provider = _FakeProvider();
      final d = await PushService(
        provider,
        repo,
      ).sendToUserByKind('u1', title: 'T', body: 'B');
      expect(d.app, 2);
      expect(d.web, 2);
      expect(provider.seen.toSet(), {'a1', 'i1', 'w1', 'w2'});
    });

    test('a dead browser token is pruned and not counted', () async {
      final provider = _FakeProvider()..invalid = ['w2'];
      final svc = PushService(provider, repo);
      final d = await svc.sendToUserByKind('u1', title: 'T', body: 'B');
      expect(d.web, 1);
      expect(d.app, 2, reason: 'the app group knows nothing of w2');
      expect((await repo.tokensForUser('u1')).toSet(), {'a1', 'i1', 'w1'});
    });

    test('only browsers → app 0', () async {
      final only = InMemoryDeviceTokenRepository();
      await only.upsert(
        token: 'w',
        userId: 'u9',
        role: 'provider',
        platform: 'web',
      );
      final d = await PushService(
        _FakeProvider(),
        only,
      ).sendToUserByKind('u9', title: 'T', body: 'B');
      expect(d, (app: 0, web: 1));
    });

    test('sendToUser still answers the total', () async {
      expect(
        await PushService(
          _FakeProvider(),
          repo,
        ).sendToUser('u1', title: 'T', body: 'B'),
        4,
      );
    });
  });

  group('PushService', () {
    test('sendToUser fans out + prunes invalid tokens', () async {
      final repo = InMemoryDeviceTokenRepository();
      await repo.upsert(
        token: 'good',
        userId: 'u1',
        role: 'user',
        platform: 'android',
      );
      await repo.upsert(
        token: 'dead',
        userId: 'u1',
        role: 'user',
        platform: 'ios',
      );
      final provider = _FakeProvider()..invalid = ['dead'];
      final svc = PushService(provider, repo);

      final sent = await svc.sendToUser('u1', title: 'T', body: 'B');
      expect(sent, 1);
      expect(provider.seen.toSet(), {'good', 'dead'});
      expect(await repo.tokensForUser('u1'), ['good']); // dead pruned
    });

    test('no tokens → no-op', () async {
      final svc = PushService(_FakeProvider(), InMemoryDeviceTokenRepository());
      expect(await svc.sendToUser('nobody', title: 'T', body: 'B'), 0);
    });
  });

  group('FcmV1PushProvider', () {
    test(
      'posts messages:send with Bearer + parses success; 404 → invalid',
      () async {
        final seen = <http.Request>[];
        final p = FcmV1PushProvider(
          projectId: 'proj',
          tokenSource: _FakeTokenSource('tok'),
          client: MockClient((req) async {
            seen.add(req);
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            final token = (body['message'] as Map)['token'];
            // A REAL 404 envelope, not `{}`. The old assertion passed on an
            // empty body because the code short-circuited on the status alone;
            // pruning now requires the UNREGISTERED detail, so the test has to
            // send what FCM actually sends.
            return token == 'dead'
                ? http.Response(_unregistered, 404)
                : http.Response('{}', 200);
          }),
        );

        final res = await p.send(
          tokens: ['good', 'dead'],
          title: 'T',
          body: 'B',
        );
        expect(res.sent, 1);
        expect(res.invalidTokens, ['dead']);
        expect(
          seen.first.url.toString(),
          'https://fcm.googleapis.com/v1/projects/proj/messages:send',
        );
        expect(seen.first.headers['Authorization'], 'Bearer tok');
      },
    );

    test('no access token → nothing sent', () async {
      final p = FcmV1PushProvider(
        projectId: 'proj',
        tokenSource: _FakeTokenSource(null),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect((await p.send(tokens: ['x'], title: 'T', body: 'B')).sent, 0);
    });

    test(
      'carries the per-platform options (design §9): the Android channel '
      'the app declares + the time-sensitive priority on both platforms',
      () async {
        Map<String, dynamic>? message;
        final p = FcmV1PushProvider(
          projectId: 'proj',
          tokenSource: _FakeTokenSource('tok'),
          client: MockClient((req) async {
            message =
                (jsonDecode(req.body) as Map<String, dynamic>)['message']
                    as Map<String, dynamic>;
            return http.Response('{}', 200);
          }),
        );

        await p.send(
          tokens: ['good'],
          title: 'T',
          body: 'B',
          data: {'route': '/appointment/a1'},
        );

        final android = message!['android'] as Map<String, dynamic>;
        expect(
          (android['notification'] as Map)['channel_id'],
          FcmV1PushProvider.androidChannelId, // == the app's kPushChannelId
        );
        expect(android['priority'], 'high');
        final apns = message!['apns'] as Map<String, dynamic>;
        expect((apns['headers'] as Map)['apns-priority'], '10');
        // Never a silent push (B0.9, decision 7): every message carries a
        // `notification`, and nothing asks iOS to wake the app in the
        // background. The iOS app no longer declares `remote-notification`
        // (`ios_store_readiness_test.dart`); a silent push would need it back.
        expect(message!['notification'], isA<Map<String, dynamic>>());
        expect(apns.containsKey('payload'), isFalse);
        expect(jsonEncode(message), isNot(contains('content-available')));
        expect((apns['headers'] as Map)['apns-push-type'], isNot('background'));
        // Browsers (web-pro-browser-push.md §4): the same urgency, and a day
        // at most — past that, a booking alert no longer helps (the e-mail
        // and the feed have said it).
        final webpush = message!['webpush'] as Map<String, dynamic>;
        expect((webpush['headers'] as Map)['Urgency'], 'high');
        expect((webpush['headers'] as Map)['TTL'], '86400');
        // The data payload (deep-link route) rides along untouched.
        expect((message!['data'] as Map)['route'], '/appointment/a1');
      },
    );
  });

  /// Which FCM failures mean "this device is gone" and which mean "we sent
  /// something wrong" (docs/design/infra-staging.md §7, finding 4).
  ///
  /// **None of this was covered.** No test in this file had ever sent a 400, and
  /// the 404 test asserted against a body of `{}` — so the detector's body
  /// inspection was never exercised at all, and a rule that pruned on *every*
  /// 400 survived three PRs.
  group('FcmV1PushProvider — a 400 is not a dead token', () {
    FcmV1PushProvider providerReturning(String body, int status) =>
        FcmV1PushProvider(
          projectId: 'proj',
          tokenSource: _FakeTokenSource('tok'),
          client: MockClient((_) async => http.Response(body, status)),
        );

    test('a field violation naming message.token → pruned', () async {
      final res = await providerReturning(
        _badToken,
        400,
      ).send(tokens: ['garbage'], title: 'T', body: 'B');
      expect(res.invalidTokens, ['garbage']);
    });

    test(
      'REGRESSION: a payload-level 400 prunes NOTHING — the tokens are fine',
      () async {
        // The bug, exactly. `send` posts an identical payload for every token,
        // so an oversized body 400s on all of them; the old detector saw
        // "INVALID_ARGUMENT" in each response and reported every token dead.
        // `PushService` then DELETEs them. One salon with a long enough name
        // wiped the push tokens of every client who booked there.
        final res = await providerReturning(
          _payloadTooBig,
          400,
        ).send(tokens: ['alice', 'bob', 'carol'], title: 'T', body: 'B' * 5000);
        expect(
          res.invalidTokens,
          isEmpty,
          reason: 'the payload was rejected, not the devices',
        );
        expect(res.error, 'push_send_failed');
        expect(res.sent, 0);
      },
    );

    test('403 SENDER_ID_MISMATCH → not pruned', () async {
      // A service account from the wrong project. A configuration error, and
      // pruning here would turn a fixable mistake into lost user data.
      final res = await providerReturning(
        _senderMismatch,
        403,
      ).send(tokens: ['alice'], title: 'T', body: 'B');
      expect(res.invalidTokens, isEmpty);
      expect(res.error, 'push_send_failed');
    });

    test(
      'a non-JSON body (proxy/LB error page) → not pruned, no throw',
      () async {
        final res = await providerReturning(
          '<html>502 Bad Gateway</html>',
          400,
        ).send(tokens: ['alice'], title: 'T', body: 'B');
        expect(res.invalidTokens, isEmpty);
        expect(res.error, 'push_send_failed');
      },
    );

    test('a 404 without the UNREGISTERED detail → not pruned', () async {
      // A 404 can also come from a wrong URL or an edge proxy. Only FCM's own
      // UNREGISTERED is a statement about the device. Not pruning a genuinely
      // dead token costs one wasted request; pruning a live one destroys data.
      final res = await providerReturning(
        '{}',
        404,
      ).send(tokens: ['alice'], title: 'T', body: 'B');
      expect(res.invalidTokens, isEmpty);
    });

    test(
      'the visible strings are capped before a send can be oversized',
      () async {
        // Defence in depth: the detector above is the fix, but the input that
        // exploited it should not reach FCM either.
        Map<String, dynamic>? notification;
        var payloadBytes = 0;
        final p = FcmV1PushProvider(
          projectId: 'proj',
          tokenSource: _FakeTokenSource('tok'),
          client: MockClient((req) async {
            payloadBytes = req.bodyBytes.length;
            notification =
                ((jsonDecode(req.body) as Map<String, dynamic>)['message']
                        as Map<String, dynamic>)['notification']
                    as Map<String, dynamic>;
            return http.Response('{}', 200);
          }),
        );

        await p.send(tokens: ['a'], title: 'T' * 500, body: 'B' * 5000);

        expect(
          (notification!['title'] as String).runes.length,
          FcmV1PushProvider.maxTitleChars,
        );
        expect(
          (notification!['body'] as String).runes.length,
          FcmV1PushProvider.maxBodyChars,
        );
        expect(
          payloadBytes,
          lessThan(4096),
          reason: 'the whole messages:send payload must stay under FCM’s limit',
        );
      },
    );

    test('a short message is passed through untouched', () async {
      // The cap must not be visible in normal operation.
      Map<String, dynamic>? notification;
      final p = FcmV1PushProvider(
        projectId: 'proj',
        tokenSource: _FakeTokenSource('tok'),
        client: MockClient((req) async {
          notification =
              ((jsonDecode(req.body) as Map<String, dynamic>)['message']
                      as Map<String, dynamic>)['notification']
                  as Map<String, dynamic>;
          return http.Response('{}', 200);
        }),
      );
      await p.send(
        tokens: ['a'],
        title: 'Réservation confirmée',
        body: 'Beauté Divine — demain à 14:00',
      );
      expect(notification!['title'], 'Réservation confirmée');
      expect(notification!['body'], 'Beauté Divine — demain à 14:00');
    });
  });

  group('routes /me/devices', () {
    final tokens = TokenService(secret: 'test-secret');
    late InMemoryDeviceTokenRepository repo;
    late PushService push;

    setUp(() {
      repo = InMemoryDeviceTokenRepository();
      push = PushService(LogPushProvider(), repo);
    });

    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<PushService>()).thenReturn(push);
      return context;
    }

    Request post(Object body, {String? token}) => Request.post(
      Uri.parse('http://localhost/me/devices'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
      body: jsonEncode(body),
    );

    test('register stores the token for the caller; anon → 401', () async {
      final token = tokens.issueAccessToken(subject: 'u1', role: 'user').token;
      final res = await devices_route.onRequest(
        ctx(post({'token': 'devtok', 'platform': 'android'}, token: token)),
      );
      expect(res.statusCode, 200);
      expect(await repo.tokensForUser('u1'), ['devtok']);

      final anon = await devices_route.onRequest(
        ctx(post({'token': 'x', 'platform': 'android'})),
      );
      expect(anon.statusCode, HttpStatus.unauthorized);
    });

    test('bad platform → 400', () async {
      final token = tokens.issueAccessToken(subject: 'u1', role: 'user').token;
      final res = await devices_route.onRequest(
        ctx(post({'token': 'devtok', 'platform': 'nope'}, token: token)),
      );
      expect(res.statusCode, HttpStatus.badRequest);
    });

    test('a non-text token or platform → 400 invalid_body, not 500, and '
        'nothing stored (docs/design/phone-leftovers.md §3)', () async {
      final token = tokens.issueAccessToken(subject: 'u1', role: 'user').token;
      for (final body in <Map<String, Object?>>[
        {'token': 12345, 'platform': 'android'},
        {'token': 'devtok', 'platform': 1},
      ]) {
        final res = await observed(
          devices_route.onRequest,
          ctx(post(body, token: token)),
        );
        expect(res.statusCode, HttpStatus.badRequest, reason: '$body');
        expect((await res.json() as Map)['error'], 'invalid_body');
      }
      expect(await repo.tokensForUser('u1'), isEmpty);
    });
  });
  group('an auth failure must be LOUD (it was silent for months)', () {
    // FCM_PRIVATE_KEY was a key for a RETIRED Firebase project, so OAuth failed
    // on every send and push had never worked. The provider returned
    // (sent: 0, invalidTokens: []) — byte-identical to "there was nobody to
    // send to". No log, no signal, nothing to notice.
    test('no access token → a distinguishable error, not silence', () async {
      final p = FcmV1PushProvider(
        projectId: 'proj',
        tokenSource: _NoTokenSource(),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final r = await p.send(tokens: ['t1'], title: 'x', body: 'y');

      expect(r.sent, 0);
      expect(
        r.error,
        'push_auth_failed',
        reason:
            'this is the whole point — it must not be indistinguishable '
            'from having no recipients',
      );
    });

    test('nothing to send is NOT an error', () async {
      // The other half: if every empty fan-out reported an error, the signal
      // would be noise and get ignored again.
      final p = FcmV1PushProvider(
        projectId: 'proj',
        tokenSource: _NoTokenSource(),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final r = await p.send(tokens: const [], title: 'x', body: 'y');
      expect(r.sent, 0);
      expect(r.error, isNull);
    });

    test('an unexpected non-2xx is reported, not swallowed', () async {
      // A 500 from FCM is neither "sent" nor "invalid token", and used to
      // vanish entirely.
      final p = FcmV1PushProvider(
        projectId: 'proj',
        tokenSource: _FixedTokenSource(),
        client: MockClient((_) async => http.Response('boom', 500)),
      );
      final r = await p.send(tokens: ['t1'], title: 'x', body: 'y');
      expect(r.sent, 0);
      expect(r.invalidTokens, isEmpty);
      expect(r.error, 'push_send_failed');
    });

    test('a successful send reports no error', () async {
      final p = FcmV1PushProvider(
        projectId: 'proj',
        tokenSource: _FixedTokenSource(),
        client: MockClient((_) async => http.Response('{"name":"ok"}', 200)),
      );
      final r = await p.send(tokens: ['t1'], title: 'x', body: 'y');
      expect(r.sent, 1);
      expect(r.error, isNull);
    });
  });
}

class _NoTokenSource implements AccessTokenSource {
  @override
  Future<String?> token() async => null;
}

class _FixedTokenSource implements AccessTokenSource {
  @override
  Future<String?> token() async => 'access-token';
}

/// Real FCM HTTP v1 error envelopes.
///
/// Every one of these is a `google.rpc.Status`, and **every 400 carries
/// `"status": "INVALID_ARGUMENT"`** — that is the canonical gRPC code name for
/// the HTTP status, not a statement about the token. The old detector
/// substring-matched exactly that string, which is why it pruned on any 400.
/// `UNREGISTERED` appears only in `details[].errorCode`, under a 404 whose
/// `status` is `NOT_FOUND`.

/// 404 — the one unambiguous dead-token signal.
const _unregistered = '''
{"error":{"code":404,"message":"Requested entity was not found.",
"status":"NOT_FOUND","details":[
{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError",
"errorCode":"UNREGISTERED"}]}}
''';

/// 400 — the token itself is malformed. The field violation names it.
const _badToken = '''
{"error":{"code":400,"message":"The registration token is not valid.",
"status":"INVALID_ARGUMENT","details":[
{"@type":"type.googleapis.com/google.rpc.BadRequest","fieldViolations":[
{"field":"message.token","description":"Invalid registration token"}]},
{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError",
"errorCode":"INVALID_ARGUMENT"}]}}
''';

/// 400 — OUR payload is wrong; the tokens are fine. Indistinguishable from
/// [_badToken] to a `contains()`, and this is the one that used to wipe tables.
const _payloadTooBig = '''
{"error":{"code":400,"message":"Request contains an invalid argument.",
"status":"INVALID_ARGUMENT","details":[
{"@type":"type.googleapis.com/google.rpc.BadRequest","fieldViolations":[
{"field":"message.notification.body","description":"Payload exceeds 4096 bytes"}]},
{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError",
"errorCode":"INVALID_ARGUMENT"}]}}
''';

/// 403 — the service account belongs to another project. Config error, not a
/// dead device.
const _senderMismatch = '''
{"error":{"code":403,"message":"SenderId mismatch","status":"PERMISSION_DENIED",
"details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError",
"errorCode":"SENDER_ID_MISMATCH"}]}}
''';
