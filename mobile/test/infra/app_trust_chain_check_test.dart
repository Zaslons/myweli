import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/net/net_settings.dart';

/// `infra/cloudflare/98-verify-app-trust-chain.sh` and the `appchain` job of
/// `production-checks.yml`: does the chain Cloudflare serves for the app's
/// hosts still end in a root the Android app bundles?
/// Design: docs/design/android-http3-transport.md §5.2.
///
/// The daily job asks production; this file is where every red branch is
/// reached, since reaching one against production means Cloudflare already
/// moved us to a CA the app does not trust. It runs the REAL script against a
/// local TLS server through the two rehearsal variables — a test PKI made with
/// openssl here, so nothing is committed — and with no variable against a
/// stand-in openssl, so the production hosts and the bundled roots are held
/// without touching production.
///
/// Here and not in backend/test/: any file under backend/ redeploys staging on
/// merge (deploy-backend.yml), and this has nothing to do with the server.
///
/// **What this cannot see.** What Cloudflare serves GitHub's runner — only the
/// daily run shows it — and a backup certificate before Cloudflare deploys it.
void main() {
  final root = Directory.current.path.endsWith('mobile')
      ? '${Directory.current.path}/..'
      : Directory.current.path;
  const scriptPath = 'infra/cloudflare/98-verify-app-trust-chain.sh';
  final scriptFile = File('$root/$scriptPath');
  const rawDir = 'mobile/android/app/src/main/res/raw';

  late Directory pki;
  late Directory anchorsA;
  late Directory anchorsB;
  late Directory noAnchors;
  late HttpServer server;
  late String good;
  late String closed;

  void openssl(List<String> args) {
    final r = Process.runSync('openssl', args, workingDirectory: pki.path);
    if (r.exitCode != 0) {
      throw StateError('openssl ${args.join(' ')}: ${r.stderr}');
    }
  }

  /// A key and a certificate: self-signed when [issuer] is null.
  void cert(String name, String subject, {String? issuer, String? ext}) {
    if (issuer == null) {
      openssl([
        'req', '-x509', '-newkey', 'ec', '-pkeyopt', //
        'ec_paramgen_curve:P-256', '-nodes', '-keyout', '$name.key',
        '-out', '$name.pem', '-days', '30', '-subj', subject,
        '-addext', 'basicConstraints=critical,CA:TRUE',
        '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
      ]);
      return;
    }
    File('${pki.path}/$name.ext').writeAsStringSync(ext!);
    openssl([
      'req', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', //
      '-nodes', '-keyout', '$name.key', '-out', '$name.csr', '-subj', subject,
    ]);
    openssl([
      'x509', '-req', '-in', '$name.csr', '-CA', '$issuer.pem', //
      '-CAkey', '$issuer.key', '-CAcreateserial', '-out', '$name.pem',
      '-days', '30', '-extfile', '$name.ext',
    ]);
  }

  setUpAll(() async {
    pki = Directory.systemTemp.createTempSync('app_chain_pki_');
    cert('rootA', '/CN=Test Root A');
    cert('rootB', '/CN=Test Root B');
    cert(
      'int',
      '/CN=Test Intermediate',
      issuer: 'rootA',
      ext:
          'basicConstraints=critical,CA:TRUE,pathlen:0\n'
          'keyUsage=critical,keyCertSign,cRLSign\n',
    );
    cert(
      'leaf',
      '/CN=127.0.0.1',
      issuer: 'int',
      ext:
          'basicConstraints=CA:FALSE\n'
          'extendedKeyUsage=serverAuth\n'
          'subjectAltName=IP:127.0.0.1\n',
    );
    File('${pki.path}/chain.pem').writeAsStringSync(
      File('${pki.path}/leaf.pem').readAsStringSync() +
          File('${pki.path}/int.pem').readAsStringSync(),
    );

    Directory dirWith(String name, List<String> pems) {
      final d = Directory('${pki.path}/$name')..createSync();
      for (final p in pems) {
        File('${pki.path}/$p.pem').copySync('${d.path}/$p.pem');
      }
      return d;
    }

    anchorsA = dirWith('anchors-a', ['rootB', 'rootA']);
    anchorsB = dirWith('anchors-b', ['rootB']);
    noAnchors = dirWith('anchors-none', []);

    final context = SecurityContext()
      ..useCertificateChain('${pki.path}/chain.pem')
      ..usePrivateKey('${pki.path}/leaf.key');
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    server.listen((req) => req.response.close());
    good = '127.0.0.1:${server.port}';

    // A port nothing listens on: refused at once.
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    closed = '127.0.0.1:${socket.port}';
    await socket.close();
  });

  tearDownAll(() async {
    await server.close(force: true);
    pki.deleteSync(recursive: true);
  });

  /// The real script, with the rehearsal variables and only PATH from
  /// outside. Asynchronous: a synchronous spawn would block the very server
  /// it reads.
  Future<({int exitCode, String out})> verify(
    String hosts,
    Directory anchors,
  ) async {
    final r = await Process.run(
      'bash',
      [scriptFile.path],
      includeParentEnvironment: false,
      environment: {
        'PATH': Platform.environment['PATH']!,
        'APP_CHAIN_HOSTS': hosts,
        'APP_CHAIN_ANCHORS_DIR': anchors.path,
      },
    );
    return (exitCode: r.exitCode, out: '${r.stdout}${r.stderr}');
  }

  group('against a local TLS server', () {
    test(
      'green: the chain ends in a bundled root, and it says which',
      () async {
        final r = await verify(good, anchorsA);
        expect(r.exitCode, 0, reason: r.out);
        expect(r.out, contains('$good: OK'));
        expect(r.out, contains('ends in CN=Test Root A'));
        expect(r.out, contains('against 2 bundled roots'));
      },
    );

    test('red: the chain ends in a root that is not bundled — and the fix '
        'names the files to change', () async {
      final r = await verify(good, anchorsB);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('$good: the chain it serves'));
      expect(r.out, contains('ends in NO root the Android app trusts'));
      expect(r.out, contains('res/raw/'));
      expect(r.out, contains('network_security_config.xml'));
    });

    test('red: no answer at all — nothing measured is not green', () async {
      final r = await verify(closed, anchorsA);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('$closed: could not read the chain'));
    });

    test('every host is read before the exit: one red never hides a green '
        'or a second red', () async {
      final r = await verify('$closed\n$good $closed', anchorsA);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('$good: OK'));
      expect(
        RegExp(RegExp.escape('$closed: could not read')).allMatches(r.out),
        hasLength(2),
      );
    });
  });

  test(
    'it verifies against the bundled roots ONLY: no system store, no '
    'default path — or a root trusted by the runner would turn it green',
    () async {
      // The real openssl, behind a wrapper that logs each call.
      final real =
          (Process.runSync('bash', ['-c', 'command -v openssl']).stdout
                  as String)
              .trim();
      final shim = Directory.systemTemp.createTempSync('app_chain_wrap_');
      addTearDown(() => shim.deleteSync(recursive: true));
      final log = File('${shim.path}/openssl.log')..writeAsStringSync('');
      File('${shim.path}/openssl').writeAsStringSync('''#!/usr/bin/env bash
{ printf '%s\\037' "\$@"; printf '\\036'; } >> "${log.path}"
exec "$real" "\$@"
''');
      Process.runSync('chmod', ['+x', '${shim.path}/openssl']);
      final r = await Process.run(
        'bash',
        [scriptFile.path],
        includeParentEnvironment: false,
        environment: {
          'PATH': '${shim.path}:${Platform.environment['PATH']}',
          'APP_CHAIN_HOSTS': good,
          'APP_CHAIN_ANCHORS_DIR': anchorsA.path,
        },
      );
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final verifies = log
          .readAsStringSync()
          .split('\x1e')
          .where((c) => c.startsWith('verify\x1f'))
          .map((c) => c.split('\x1f'))
          .toList();
      expect(verifies, hasLength(1));
      expect(
        verifies.single,
        containsAll(['-no-CApath', '-no-CAstore', '-CAfile']),
      );
    },
  );

  group('it refuses to report success having read nothing', () {
    test('no bundled root', () async {
      final r = await verify(good, noAnchors);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('no bundled root'));
    });

    test('a host list of spaces only', () async {
      final r = await verify('  \n ', anchorsA);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('no host to check'));
    });
  });

  group('with no variable: production, against a stand-in openssl', () {
    late Directory shim;

    setUp(() {
      shim = Directory.systemTemp.createTempSync('app_chain_shim_');
      // Logs each call and answers nothing, so the script stops at « could not
      // read »: what is held is WHAT it asks, not what Cloudflare answers.
      File('${shim.path}/openssl').writeAsStringSync(r'''#!/usr/bin/env bash
{ printf '%s\037' "$@"; printf '\036'; } >> "$OPENSSL_LOG"
exit 1
''');
      Process.runSync('chmod', ['+x', '${shim.path}/openssl']);
    });

    tearDown(() => shim.deleteSync(recursive: true));

    test('it reads exactly the API and the CDN, with SNI, against the roots '
        'the Android app bundles', () async {
      final log = File('${shim.path}/openssl.log')..writeAsStringSync('');
      final r = await Process.run(
        'bash',
        [scriptFile.path],
        includeParentEnvironment: false,
        environment: {
          'PATH': '${shim.path}:${Platform.environment['PATH']}',
          'OPENSSL_LOG': log.path,
        },
      );
      final calls = log
          .readAsStringSync()
          .split('\x1e')
          .where((c) => c.isNotEmpty)
          .map((c) => c.split('\x1f')..removeLast())
          .toList();
      expect(calls, [
        [
          's_client',
          '-connect',
          'api.myweli.com:443',
          '-servername',
          'api.myweli.com',
          '-showcerts',
        ],
        [
          's_client',
          '-connect',
          '$kCdnHost:443',
          '-servername',
          kCdnHost,
          '-showcerts',
        ],
      ]);
      final bundled = Directory(
        '$root/$rawDir',
      ).listSync().where((f) => f.path.endsWith('.pem')).length;
      expect(bundled, greaterThanOrEqualTo(10));
      expect(
        '${r.stdout}${r.stderr}',
        contains('against $bundled bundled roots from $rawDir'),
      );
      expect(r.exitCode, 1, reason: 'nothing was read');
    });
  });

  group('the daily job', () {
    final workflow = File(
      '$root/.github/workflows/production-checks.yml',
    ).readAsStringSync().replaceAll(RegExp(r'^\s*#.*$', multiLine: true), '');

    String jobBlock(String name) {
      final m = RegExp(
        '^  $name:\$([\\s\\S]*?)(?=^  \\S|(?![\\s\\S]))',
        multiLine: true,
      ).firstMatch(workflow);
      expect(m, isNotNull, reason: 'no $name job');
      return m!.group(1)!;
    }

    test('exists, checks out, then runs exactly the script', () {
      final job = jobBlock('appchain');
      final checkout = job.indexOf('uses: actions/checkout@');
      final run = job.indexOf('run: bash $scriptPath\n');
      expect(checkout, isNonNegative);
      expect(run, greaterThan(checkout));
      expect(
        RegExp(r'^\s+run:', multiLine: true).allMatches(job),
        hasLength(1),
      );
    });

    test('holds contents: read and nothing else, and sets no variable', () {
      final job = jobBlock('appchain');
      expect(
        job,
        matches(
          RegExp(
            r'^ {4}permissions:\n {6}contents: read\n {4}\S',
            multiLine: true,
          ),
        ),
      );
      expect(job, isNot(contains('env:')));
      for (final f in Directory('$root/.github/workflows').listSync()) {
        if (f is! File) continue;
        expect(
          RegExp(
            r'APP_CHAIN_(HOSTS|ANCHORS_DIR)\s*[:=]',
          ).hasMatch(f.readAsStringSync()),
          isFalse,
          reason: '${f.path} sets a rehearsal variable',
        );
      }
    });

    test('a red run reaches the alarm, and the issue says what to do', () {
      final needs = RegExp(r'needs: \[([^\]]*)\]')
          .allMatches(workflow)
          .map((m) => m.group(1)!.split(',').map((s) => s.trim()).toSet())
          .toList();
      expect(needs.where((n) => n.contains('appchain')), hasLength(2));
      final report = jobBlock('report');
      final row = RegExp(
        r'^\s+([A-Z][A-Z0-9_]*): \$\{\{ needs\.appchain\.result \}\}\s*$',
        multiLine: true,
      ).firstMatch(report);
      expect(row, isNotNull);
      final status = report
          .split('\n')
          .singleWhere((l) => l.contains(r'CWV: ${CWV}'));
      expect(status, contains('\${${row!.group(1)}}'));
      final body = report.replaceAll(RegExp(r"'\s*\\\n\s*'"), ' ');
      for (final words in [
        'mobile/android/app/src/main/res/raw/',
        'network_security_config.xml',
        'android-http3-transport.md §5.2',
        'nothing was measured',
      ]) {
        expect(body, contains(words));
      }
    });
  });

  group('the script', () {
    test('is executable', () {
      expect(scriptFile.statSync().mode & 0x40, isNonZero);
    });

    test('checks the hosts the app hints, by default', () {
      expect(
        scriptFile.readAsStringSync(),
        contains("HOSTS_DEFAULT='api.myweli.com $kCdnHost'"),
      );
    });

    test('carries no credential, comments included', () {
      final text = scriptFile.readAsStringSync().toLowerCase();
      for (final word in ['authorization', 'cookie', 'bearer', 'api_token']) {
        expect(text, isNot(contains(word)), reason: word);
      }
    });
  });
}
