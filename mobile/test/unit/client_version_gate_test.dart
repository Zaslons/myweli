import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/version/client_version_gate.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The version gate's contract is **fail open**, and these tests are mostly
/// about the ways it must NOT block.
///
/// A gate that blocks on ambiguity is worse than no gate: the failure it
/// produces — an app that will not start — is indistinguishable to the user
/// from the app being broken, and it arrives on exactly the networks our users
/// have. The house rule copied here is `refreshing_http_client.dart:102`:
/// distinguish "the server said no" from "I could not reach the server".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PackageInfo info({String build = '3'}) => PackageInfo(
    appName: 'MyWeli',
    packageName: 'com.myweli.app',
    version: '1.0.0',
    buildNumber: build,
  );

  Future<ClientVersionResult> run(MockClient client, {PackageInfo? pkg}) =>
      ClientVersionGate(
        client: client,
        packageInfo: pkg ?? info(),
        // The test VM is neither Android nor iOS, so without this the gate
        // returns `ok` before reaching anything under test — which is exactly
        // how the first draft of these tests "passed" a broken assumption.
        platform: 'android',
      ).check();

  MockClient responds(String body, {int status = 200}) =>
      MockClient((_) async => http.Response(body, status));

  group('blocks only on an explicit, well-formed refusal', () {
    test('update_required → blocked, with the URL', () async {
      final r = await run(
        responds('{"status":"update_required","updateUrl":"https://play/x"}'),
      );
      expect(r.verdict, ClientVersionVerdict.updateRequired);
      expect(r.updateUrl, 'https://play/x');
      expect(r.build, 3);
    });

    test('update_available → nudge, not a block', () async {
      final r = await run(
        responds('{"status":"update_available","updateUrl":"https://play/x"}'),
      );
      expect(r.verdict, ClientVersionVerdict.updateAvailable);
    });

    test('ok → runs', () async {
      expect(
        (await run(responds('{"status":"ok"}'))).verdict,
        ClientVersionVerdict.ok,
      );
    });
  });

  group('fails OPEN on every ambiguity', () {
    test('an UNRECOGNISED status runs', () async {
      // The other half of the order-sensitivity argument. A v1.0 that treated
      // an unknown verdict as "block" would be undeployable-around: a later
      // server could never add a verdict without bricking the oldest clients
      // it is trying to manage.
      final r = await run(responds('{"status":"quarantine_please"}'));
      expect(r.verdict, ClientVersionVerdict.ok);
    });

    test('a timeout runs — and does not hang past the deadline', () async {
      final slow = MockClient((_) async {
        await Future<void>.delayed(ClientVersionGate.deadline * 3);
        return http.Response('{"status":"update_required"}', 200);
      });
      final sw = Stopwatch()..start();
      expect((await run(slow)).verdict, ClientVersionVerdict.ok);
      sw.stop();
      // The splash waits on this. A gate with no deadline hangs forever behind
      // a captive portal, which is the failure most likely to be blamed on us.
      expect(sw.elapsed, lessThan(ClientVersionGate.deadline * 2));
    });

    test('a socket error runs', () async {
      final dead = MockClient((_) async => throw const SocketException('no'));
      expect((await run(dead)).verdict, ClientVersionVerdict.ok);
    });

    test('5xx, 4xx and malformed JSON all run', () async {
      for (final c in [
        responds('{"status":"update_required"}', status: 500),
        responds('{"status":"update_required"}', status: 403),
        responds('not json at all'),
        responds('[]'),
        responds('{}'),
      ]) {
        expect((await run(c)).verdict, ClientVersionVerdict.ok);
      }
    });

    test(
      'an unparseable build number runs, without asking the server',
      () async {
        var called = false;
        final spy = MockClient((_) async {
          called = true;
          return http.Response('{"status":"update_required"}', 200);
        });
        final r = await run(spy, pkg: info(build: 'not-a-number'));
        expect(r.verdict, ClientVersionVerdict.ok);
        expect(called, isFalse, reason: 'nothing to compare — do not even ask');
      },
    );

    test('update_required WITHOUT a url still blocks, url null', () async {
      // The server refuses to send this (it will not block a platform it has
      // nowhere to send). If it ever does, the screen renders without a button
      // rather than with a dead one.
      final r = await run(responds('{"status":"update_required"}'));
      expect(r.verdict, ClientVersionVerdict.updateRequired);
      expect(r.updateUrl, isNull);
    });
  });

  test('sends app, platform, build and version', () async {
    Uri? seen;
    final spy = MockClient((req) async {
      seen = req.url;
      return http.Response('{"status":"ok"}', 200);
    });
    await run(spy);
    expect(seen!.path, endsWith('/client-version'));
    expect(seen!.queryParameters['app'], 'com.myweli.app');
    expect(seen!.queryParameters['build'], '3');
    expect(seen!.queryParameters['version'], '1.0.0');
    expect(seen!.queryParameters['platform'], 'android');
  });
}
