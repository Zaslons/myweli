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
    return (sent: tokens.length - invalid.length, invalidTokens: invalid);
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
            return http.Response('{}', token == 'dead' ? 404 : 200);
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
        // The data payload (deep-link route) rides along untouched.
        expect((message!['data'] as Map)['route'], '/appointment/a1');
      },
    );
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
  });
}
