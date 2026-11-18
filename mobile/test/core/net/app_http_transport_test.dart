import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/net/app_http_transport.dart';
import 'package:myweli/core/observability/error_reporting.dart';

/// The transport of docs/design/android-http3-transport.md §4.1–§4.2, §4.7,
/// run on the Mac: the platform is passed in and both clients are fakes, so
/// every branch Android takes is reached here. What only a phone can show —
/// that Play Services builds an engine, that HTTP/3 is negotiated — is the
/// device read of §7.
void main() {
  const api = 'https://api.myweli.com';

  /// A client that answers 200 and counts what it served.
  /// Like cronet_http's client, it refuses every request once closed.
  ({http.Client client, List<Uri> served}) recording(String name) {
    final served = <Uri>[];
    return (
      client: _ClosableClient(
        MockClient((req) async {
          served.add(req.url);
          return http.Response(name, 200);
        }),
      ),
      served: served,
    );
  }

  AppHttpTransport transport({
    required bool isAndroid,
    String apiBaseUrl = api,
    http.Client Function(CronetSettings)? buildCronet,
    http.Client Function()? buildPlatformClient,
    String userAgent = 'MyWeli/0.0.2+785 (com.myweli.pro; Android)',
  }) => AppHttpTransport(
    isAndroid: isAndroid,
    apiBaseUrl: apiBaseUrl,
    buildCronet:
        buildCronet ?? (_) => fail('Cronet must not be built off Android'),
    buildPlatformClient:
        buildPlatformClient ?? () => fail('the platform client is not used'),
    readUserAgent: () async => userAgent,
  );

  Future<String> get(http.Client client, [String path = '/me']) async =>
      (await client.get(Uri.parse('$api$path'))).body;

  group('on Android, with a Cronet that builds', () {
    test('every request goes through ONE Cronet client, built once — '
        'concurrent first requests included', () async {
      final cronet = recording('cronet');
      var builds = 0;
      final t = transport(
        isAndroid: true,
        buildCronet: (_) {
          builds++;
          return cronet.client;
        },
      );

      final bodies = await Future.wait([
        for (var i = 0; i < 5; i++) get(t.sharedClient, '/a$i'),
      ]);
      for (var i = 0; i < 3; i++) {
        bodies.add(await get(t.sharedClient, '/b$i'));
      }

      expect(builds, 1);
      expect(bodies, everyElement('cronet'));
      expect(cronet.served, hasLength(8));
      expect(t.outcome!.transport, NetTransport.cronet);
      expect(t.outcome!.isFallback, isFalse);
    });

    test('nothing is built before the first request — the engine waits for '
        'the binding (dart-lang/http#1241)', () {
      var builds = 0;
      final t = transport(
        isAndroid: true,
        buildCronet: (_) {
          builds++;
          return recording('cronet').client;
        },
      );
      expect(t.sharedClient, isNotNull);
      expect(builds, 0);
      expect(t.outcome, isNull);
    });

    test(
      'the engine is told the app user agent read from the package',
      () async {
        CronetSettings? seen;
        final t = transport(
          isAndroid: true,
          userAgent: 'MyWeli/0.0.2+785 (com.myweli.pro; Android)',
          buildCronet: (s) {
            seen = s;
            return recording('cronet').client;
          },
        );
        await get(t.sharedClient);
        expect(seen!.userAgent, 'MyWeli/0.0.2+785 (com.myweli.pro; Android)');
        expect(seen!.quicHosts, ['api.myweli.com', 'cdn.myweli.com']);
      },
    );
  });

  group('the QUIC hints (§4.2)', () {
    test('exactly the API host and the CDN', () {
      expect(quicHintHosts('https://api.myweli.com'), [
        'api.myweli.com',
        'cdn.myweli.com',
      ]);
    });

    test('a staging build hints its own API host', () {
      expect(quicHintHosts('https://api-staging.myweli.com/v1'), [
        'api-staging.myweli.com',
        'cdn.myweli.com',
      ]);
    });

    test('plain HTTP (the Mac backend) is never hinted — QUIC is TLS', () {
      expect(quicHintHosts('http://10.0.2.2:8080'), ['cdn.myweli.com']);
    });

    test('no host twice', () {
      expect(quicHintHosts('https://cdn.myweli.com'), ['cdn.myweli.com']);
    });
  });

  group('on Android, when Cronet cannot be built', () {
    test('the platform client carries every request, and Cronet is not '
        'tried again', () async {
      final io = recording('dartio');
      var tries = 0;
      final t = transport(
        isAndroid: true,
        buildCronet: (_) {
          tries++;
          throw StateError('no provider');
        },
        buildPlatformClient: () => io.client,
      );

      expect(await get(t.sharedClient), 'dartio');
      expect(await get(t.sharedClient), 'dartio');
      expect(tries, 1);
      expect(io.served, hasLength(2));
      expect(t.outcome!.transport, NetTransport.dartio);
      expect(t.outcome!.fallbackReason, 'StateError');
    });

    test('the fallback is reported ONCE, to a listener registered before or '
        'after the first request — Sentry starts after the version gate has '
        'asked', () async {
      final early = <NetTransportOutcome>[];
      final late = <NetTransportOutcome>[];
      final t = transport(
        isAndroid: true,
        buildCronet: (_) => throw StateError('no provider'),
        buildPlatformClient: () => recording('dartio').client,
      )..whenSettled(early.add);

      await get(t.sharedClient);
      await get(t.sharedClient);
      t.whenSettled(late.add);
      await get(t.sharedClient);

      expect(early, hasLength(1));
      expect(late, hasLength(1));
      expect(early.single.isFallback, isTrue);
      expect(late.single.fallbackReason, 'StateError');
    });

    test('a Java exception is named by its class — the text Cronet gives '
        'without Play Services', () async {
      final t = transport(
        isAndroid: true,
        buildCronet: (_) => throw _FakeJThrowable(
          'java.lang.RuntimeException: Unable to find any Cronet provider. '
          'Have you included all necessary jars?',
        ),
        buildPlatformClient: () => recording('dartio').client,
      );
      await get(t.sharedClient);
      expect(t.outcome!.fallbackReason, 'java.lang.RuntimeException');
    });

    test('a listener that throws does not fail the request', () async {
      final t = transport(
        isAndroid: true,
        buildCronet: (_) => throw StateError('no provider'),
        buildPlatformClient: () => recording('dartio').client,
      )..whenSettled((_) => throw StateError('listener'));
      expect(await get(t.sharedClient), 'dartio');
    });
  });

  group('off Android', () {
    test('the platform client, Cronet never built, and no fallback '
        'reported', () async {
      final io = recording('dartio');
      final seen = <NetTransportOutcome>[];
      final t = transport(
        isAndroid: false,
        buildPlatformClient: () => io.client,
      )..whenSettled(seen.add);

      expect(await get(t.sharedClient), 'dartio');
      expect(io.served, hasLength(1));
      expect(seen.single.transport, NetTransport.dartio);
      expect(seen.single.isFallback, isFalse);
    });
  });

  test('closing the shared client does nothing: the next request still '
      'goes through', () async {
    final cronet = recording('cronet');
    final t = transport(isAndroid: true, buildCronet: (_) => cronet.client)
      ..sharedClient.close();
    expect(await get(t.sharedClient), 'cronet');
    // After the engine exists too: a close passed on would end the app's
    // network, as it ends cronet_http's.
    t.sharedClient.close();
    expect(await get(t.sharedClient), 'cronet');
  });

  group('the user agent names the app, never the phone', () {
    test('package, version and build', () {
      expect(
        appUserAgent(
          packageName: 'com.myweli.pro',
          version: '0.0.2',
          build: '785',
        ),
        'MyWeli/0.0.2+785 (com.myweli.pro; Android)',
      );
    });

    test('no build number', () {
      expect(
        appUserAgent(packageName: 'com.myweli.app', version: '1.0.0'),
        'MyWeli/1.0.0 (com.myweli.app; Android)',
      );
    });

    test('no package info at all', () {
      expect(appUserAgent(), 'MyWeli (Android)');
    });
  });

  group('cronetFailureName — a class, never a message', () {
    test('the Java class inside a JThrowable-like text', () {
      expect(
        cronetFailureName(
          _FakeJThrowable(
            'java.lang.UnsatisfiedLinkError: dlopen failed: secret path',
          ),
        ),
        'java.lang.UnsatisfiedLinkError',
      );
    });

    test('Dart errors by kind', () {
      expect(cronetFailureName(ArgumentError('x')), 'ArgumentError');
      expect(cronetFailureName(UnsupportedError('x')), 'UnsupportedError');
      expect(cronetFailureName(StateError('x')), 'StateError');
    });

    test('anything else: unknown, and nothing of its text', () {
      expect(cronetFailureName(Exception('user@example.com')), 'unknown');
    });
  });

  group('the Sentry tags (§4.7)', () {
    test('Cronet: the transport only', () {
      expect(netTransportTags(const NetTransportOutcome(NetTransport.cronet)), {
        'net.transport': 'cronet',
      });
    });

    test('a fallback: the transport and what failed', () {
      expect(
        netTransportTags(
          const NetTransportOutcome(
            NetTransport.dartio,
            fallbackReason: 'java.lang.RuntimeException',
          ),
        ),
        {
          'net.transport': 'dartio',
          'net.fallback': 'java.lang.RuntimeException',
        },
      );
    });
  });
}

/// A client that, like `CronetClient`, refuses every request once closed.
class _ClosableClient extends http.BaseClient {
  _ClosableClient(this._inner);

  final http.Client _inner;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) {
      throw http.ClientException('Client is already closed.', request.url);
    }
    return _inner.send(request);
  }

  @override
  void close() => _closed = true;
}

/// Stands in for jni's JThrowable, whose text is the Java exception's.
class _FakeJThrowable implements Exception {
  _FakeJThrowable(this.message);
  final String message;
  @override
  String toString() => message;
}
