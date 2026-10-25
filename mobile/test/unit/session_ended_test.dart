import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/models/provider_session.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:myweli/services/api/refreshing_http_client.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';

/// A session the server stops renewing ENDS the account — today it only
/// vanished from storage while the app went on showing the person signed in
/// (docs/design/consumer-account-scope.md §1, §2.4).
Future<InMemorySessionStore> _signedInStore({Object? refresh = 'r1'}) async {
  final store = InMemorySessionStore();
  await store.save(
    jsonEncode({
      'token': 'old-access',
      'refreshToken': refresh,
      'user': {'id': 'u1', 'createdAt': DateTime(2026).toIso8601String()},
    }),
  );
  return store;
}

/// Every request answers 401; the refresh answers [refresh].
MockClient _server(Future<http.Response> Function() refresh) =>
    MockClient((req) async {
      if (req.url.path == '/auth/refresh') return refresh();
      return http.Response('', 401);
    });

Future<http.Response?> _read(RefreshingHttpClient client, http.Client c) =>
    client.send(
      (t) => c.get(Uri.parse('http://x/me'), headers: {'authorization': t}),
    );

void main() {
  group('RefreshingHttpClient announces a session it ends', () {
    Future<List<Object>> endedWhile(Future<void> Function() run) async {
      final ended = <Object>[];
      final sub = RefreshingHttpClient.sessionsEnded.listen(ended.add);
      await run();
      await pumpEventQueue();
      await sub.cancel();
      return ended;
    }

    for (final (why, refresh) in <(String, Future<http.Response> Function())>[
      ('refused (401)', () async => http.Response('', 401)),
      ('refused (403, reuse detected)', () async => http.Response('', 403)),
      (
        'answered with a body that is not JSON',
        () async => http.Response('<html>', 200),
      ),
      (
        'answered without the new pair',
        () async => http.Response(jsonEncode({'accessToken': 'a'}), 200),
      ),
    ]) {
      test('a refresh $why', () async {
        final store = await _signedInStore();
        final c = _server(refresh);
        final client = RefreshingHttpClient(
          client: c,
          baseUrl: 'http://x',
          store: store,
        );

        final ended = await endedWhile(() => _read(client, c));

        expect(await store.read(), isNull, reason: 'the scenario: cleared');
        expect(ended, [store.identity]);
      });
    }

    test('a session that cannot be renewed (no refresh token)', () async {
      final store = await _signedInStore(refresh: null);
      final c = _server(() async => fail('no refresh token, no exchange'));
      final client = RefreshingHttpClient(
        client: c,
        baseUrl: 'http://x',
        store: store,
      );

      expect(await endedWhile(() => _read(client, c)), [store.identity]);
    });

    test('a renewed session announces nothing', () async {
      final store = await _signedInStore();
      final c = MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          return http.Response(
            jsonEncode({'accessToken': 'new', 'refreshToken': 'r2'}),
            200,
          );
        }
        return http.Response(
          '',
          req.headers['authorization'] == 'new' ? 200 : 401,
        );
      });
      final client = RefreshingHttpClient(
        client: c,
        baseUrl: 'http://x',
        store: store,
      );

      expect(await endedWhile(() => _read(client, c)), isEmpty);
    });

    // A flaky network keeps the person signed in — and says nothing.
    test('a refresh with no answer announces nothing', () async {
      final store = await _signedInStore();
      final c = _server(() async => throw http.ClientException('offline'));
      final client = RefreshingHttpClient(
        client: c,
        baseUrl: 'http://x',
        store: store,
      );

      expect(await endedWhile(() => _read(client, c)), isEmpty);
      expect(await store.read(), isNotNull);
    });
  });

  group('ApiAuthService.sessionEnded', () {
    final user = {
      'id': 'user_1',
      'phoneNumber': '+2250707010101',
      'createdAt': DateTime(2026).toIso8601String(),
    };

    Future<(ApiAuthService, InMemorySessionStore, InMemorySessionStore)>
    signedIn() async {
      final store = InMemorySessionStore();
      final proStore = InMemorySessionStore();
      final auth = ApiAuthService(
        client: MockClient(
          (req) async => http.Response(
            jsonEncode({
              'tokens': {'accessToken': 'access', 'refreshToken': 'refresh'},
              'user': user,
            }),
            200,
          ),
        ),
        baseUrl: 'http://x',
        sessionStore: store,
        providerSessionStore: proStore,
      );
      final res = await auth.verifyOtp('+2250707010101', '123456');
      expect(res.success, isTrue, reason: 'the scenario: signed in');
      expect(await auth.getCurrentUser(), isNotNull, reason: 'the scenario');
      return (auth, store, proStore);
    }

    test('fires when ANY service\'s refresh is refused on this session, and '
        'the account it remembered goes with it', () async {
      final (auth, store, _) = await signedIn();
      final heard = <void>[];
      final sub = auth.sessionEnded.listen(heard.add);
      // Another service's client over the same session — the appointments'.
      final c = _server(() async => http.Response('', 401));
      final appointments = RefreshingHttpClient(
        client: c,
        baseUrl: 'http://x',
        store: store,
      );

      await _read(appointments, c);
      await pumpEventQueue();
      await sub.cancel();

      expect(heard, hasLength(1));
      expect(await auth.getCurrentUser(), isNull);
    });

    test('the Pro session ending is not the client\'s', () async {
      final (auth, _, proStore) = await signedIn();
      await proStore.save(
        jsonEncode({'token': 'pro-access', 'refreshToken': 'pro-refresh'}),
      );
      final heard = <void>[];
      final sub = auth.sessionEnded.listen(heard.add);
      final c = _server(() async => http.Response('', 401));
      final pro = RefreshingHttpClient(
        client: c,
        baseUrl: 'http://x',
        store: proStore,
        refreshPath: '/auth/refresh',
      );

      await _read(pro, c);
      await pumpEventQueue();
      await sub.cancel();

      expect(heard, isEmpty);
      expect(await auth.getCurrentUser(), isNotNull);
    });
  });

  // The Pro twin (pro-account-scope.md §2.3): the provider session's end is
  // its own announcement, and the client's is not it.
  group('ApiAuthService.providerSessionEnded', () {
    Future<(ApiAuthService, InMemorySessionStore, InMemorySessionStore)>
    proSignedIn() async {
      final store = InMemorySessionStore();
      final proStore = InMemorySessionStore();
      await proStore.save(
        jsonEncode(
          ProviderSession(
            token: 'pro-access',
            refreshToken: 'pro-refresh',
            provider: MockData.providerUsers.first,
          ).toJson(),
        ),
      );
      final auth = ApiAuthService(
        client: MockClient((_) async => http.Response('', 500)),
        baseUrl: 'http://x',
        sessionStore: store,
        providerSessionStore: proStore,
      );
      expect(await auth.getCurrentProvider(), isNotNull, reason: 'scenario');
      return (auth, store, proStore);
    }

    test('fires when the PROVIDER session is refused, and the provider it '
        'remembered goes with it', () async {
      final (auth, _, proStore) = await proSignedIn();
      final heard = <void>[];
      final sub = auth.providerSessionEnded.listen(heard.add);
      final c = _server(() async => http.Response('', 401));
      final pro = RefreshingHttpClient(
        client: c,
        baseUrl: 'http://x',
        store: proStore,
        refreshPath: '/auth/provider/refresh',
      );

      await _read(pro, c);
      await pumpEventQueue();
      await sub.cancel();

      expect(heard, hasLength(1));
      expect(await auth.getCurrentProvider(), isNull);
    });

    test('the client session ending is not the Pro\'s', () async {
      final (auth, store, _) = await proSignedIn();
      await store.save(
        jsonEncode({'token': 'access', 'refreshToken': 'refresh'}),
      );
      final heard = <void>[];
      final sub = auth.providerSessionEnded.listen(heard.add);
      final c = _server(() async => http.Response('', 401));
      final client = RefreshingHttpClient(
        client: c,
        baseUrl: 'http://x',
        store: store,
      );

      await _read(client, c);
      await pumpEventQueue();
      await sub.cancel();

      expect(heard, isEmpty);
      expect(await auth.getCurrentProvider(), isNotNull);
    });
  });

  test('MockAuthService.expireProviderSession ends it and says so', () async {
    final auth = MockAuthService();
    await auth.requestProviderEmailOtp('jean@salon-excellence.test');
    await auth.verifyProviderEmailOtp(
      'jean@salon-excellence.test',
      MockAuthService.demoOtp,
    );
    expect(await auth.getCurrentProvider(), isNotNull, reason: 'scenario');
    final heard = <void>[];
    final sub = auth.providerSessionEnded.listen(heard.add);

    await auth.expireProviderSession();
    await pumpEventQueue();
    await sub.cancel();

    expect(heard, hasLength(1));
    expect(await auth.getCurrentProvider(), isNull);
  });

  // The doubles fail the way the server does (B9.6): the mock can end its
  // session as a refused refresh would.
  test('MockAuthService.expireSession ends the session and says so', () async {
    final auth = MockAuthService();
    await auth.requestEmailOtp('a@myweli.test');
    await auth.verifyEmailOtp('a@myweli.test', MockAuthService.demoOtp);
    expect(await auth.getCurrentUser(), isNotNull, reason: 'the scenario');
    final heard = <void>[];
    final sub = auth.sessionEnded.listen(heard.add);

    await auth.expireSession();
    await pumpEventQueue();
    await sub.cancel();

    expect(heard, hasLength(1));
    expect(await auth.getCurrentUser(), isNull);
  });
}
