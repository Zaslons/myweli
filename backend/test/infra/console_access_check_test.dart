import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `infra/cloudflare/98-verify-console-access.sh` and the `access` job of
/// `production-checks.yml`: is every address of the admin console still behind
/// the Cloudflare Access sign-in? Design:
/// docs/design/infra-console-access-check.md
///
/// Access lives only in the Cloudflare dashboard. Until 2026-11-13 it covered
/// admin.myweli.com alone, and myweli-admin.pages.dev served the whole console
/// bundle to anyone. The daily job asks production; this file is where every
/// red branch is reached, since reaching one against production means taking
/// Access away. It runs the REAL script, against a local server through the two
/// rehearsal variables, and with no variable at all against a stand-in curl, so
/// the production list and team host are held without touching production.
///
/// **What this cannot see.** What Cloudflare answers GitHub's network, and who
/// the « Admins » policy lets in: only the daily run shows the first, and
/// nothing anonymous can show the second (spec §8).
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  const scriptPath = 'infra/cloudflare/98-verify-console-access.sh';
  final scriptFile = File('$root/$scriptPath');

  final workflow =
      loadYaml(
            File(
              '$root/.github/workflows/production-checks.yml',
            ).readAsStringSync(),
          )
          as YamlMap;
  final jobs = workflow['jobs'] as YamlMap;

  const team = 'team.access.test';
  const fixApp = '« Myweli Admin »';
  const restrict = 'docs/DEPLOYMENT.md « Restrict »';
  // Access puts kid and meta in the query; the script must never print them.
  const query = '?kid=k1&meta=meta-must-not-be-logged&redirect_url=%2F';
  const login = 'https://$team/cdn-cgi/access/login/127.0.0.1';

  late HttpServer server;
  late String base;
  late String closedBase;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final res = req.response;
      void redirect(int code, String? location) {
        res.statusCode = code;
        if (location != null) {
          res.headers.set(HttpHeaders.locationHeader, location);
        }
      }

      final path = req.uri.path;
      if (path.startsWith('/behind/')) {
        redirect(int.parse(path.split('/').last), '$login$query');
      } else {
        switch (path) {
          case '/behind':
            redirect(302, '$login$query');
          case '/behind-upper-case':
            redirect(
              302,
              'https://TEAM.Access.Test/cdn-cgi/access/login/127.0.0.1',
            );
          case '/public':
            res.write('console');
          case '/missing':
            res.statusCode = 404;
          case '/refused':
            res.statusCode = 403;
          case '/challenged':
            // What Cloudflare sends a client it challenges: the runner, not a
            // visitor of the console.
            res.statusCode = 403;
            res.headers.set('cf-mitigated', 'challenge');
          case '/pages-redirect':
            // Pages' own redirect: relative, to the same host.
            redirect(308, '/public');
          case '/elsewhere':
            redirect(302, 'https://myweli-admin.pages.dev/');
          case '/foreign-host':
            redirect(
              302,
              'https://evil.example/cdn-cgi/access/login/127.0.0.1$query',
            );
          case '/lookalike':
            redirect(
              302,
              'https://$team.evil.example/cdn-cgi/access/login/127.0.0.1',
            );
          case '/userinfo':
            redirect(
              302,
              'https://$team@evil.example/cdn-cgi/access/login/127.0.0.1',
            );
          case '/port':
            redirect(302, 'https://$team:8443/cdn-cgi/access/login/127.0.0.1');
          case '/plain-http':
            redirect(302, 'http://$team/cdn-cgi/access/login/127.0.0.1');
          case '/other-host-login':
            redirect(
              302,
              'https://$team/cdn-cgi/access/login/admin.myweli.com$query',
            );
          case '/login-prefix':
            redirect(302, '$login.evil.example$query');
          case '/login-longer':
            redirect(302, '$login/more$query');
          case '/renamed':
            redirect(
              302,
              'https://new-team.cloudflareaccess.com/cdn-cgi/access/login/127.0.0.1$query',
            );
          case '/no-location':
            redirect(302, null);
          default:
            res.statusCode = 404;
        }
      }
      await res.close();
    });

    // A port nothing listens on: refused at once, and curl does not retry a
    // refused connection.
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    closedBase = 'http://127.0.0.1:${socket.port}';
    await socket.close();
  });

  tearDownAll(() => server.close(force: true));

  /// Runs the real script with the two rehearsal variables and only PATH from
  /// outside, so a proxy or a curlrc on the tester's machine cannot change
  /// what it reads. Asynchronous: a synchronous spawn would block the very
  /// server it calls.
  Future<({int exitCode, String out})> verify(
    List<String> urls, {
    String teamHost = team,
  }) async {
    final r = await Process.run(
      'bash',
      [scriptFile.path],
      includeParentEnvironment: false,
      environment: {
        'PATH': Platform.environment['PATH']!,
        'CONSOLE_ACCESS_URLS': urls.join('\n'),
        'CONSOLE_ACCESS_TEAM_HOST': teamHost,
      },
    );
    return (exitCode: r.exitCode, out: '${r.stdout}${r.stderr}');
  }

  group('green: a redirect to the Access sign-in for that very host', () {
    test('302, its query ignored', () async {
      final r = await verify(['$base/behind']);
      expect(r.exitCode, 0, reason: r.out);
      expect(r.out, contains('✓ $base/behind → 302'));
      expect(r.out, contains('All 1 console addresses'));
      expect(r.out, contains('REHEARSAL'));
      expect(r.out, isNot(contains('meta-must-not-be-logged')));
    });

    test('301, 303, 307 and 308 too', () async {
      final r = await verify([
        for (final code in [301, 303, 307, 308]) '$base/behind/$code',
      ]);
      expect(r.exitCode, 0, reason: r.out);
      expect(r.out, contains('All 4 console addresses'));
    });

    test('the team host in another case', () async {
      final r = await verify(['$base/behind-upper-case']);
      expect(r.exitCode, 0, reason: r.out);
    });
  });

  group('red, naming what came back', () {
    test('200: the console is PUBLIC there, and the fix', () async {
      final r = await verify(['$base/public']);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('::error::the console is PUBLIC at $base/public'));
      expect(r.out, contains('answered 200'));
      expect(r.out, contains('add 127.0.0.1 back to the Access application'));
      expect(r.out, contains(fixApp));
      expect(r.out, contains(restrict));
    });

    final cases = <String, (String, String)>{
      "Pages' own relative redirect": (
        '/pages-redirect',
        // The server's address is known only once it listens.
        'answered 308 to BASE/public, not to the Access sign-in for 127.0.0.1',
      ),
      'a redirect to another site': (
        '/elsewhere',
        'answered 302 to https://myweli-admin.pages.dev/, not to the Access',
      ),
      'the right login path on a host that is not the team': (
        '/foreign-host',
        'answered 302 to https://evil.example/cdn-cgi/access/login/127.0.0.1,',
      ),
      'a look-alike team host': (
        '/lookalike',
        'to https://$team.evil.example/',
      ),
      'the team host as userinfo in front of another host': (
        '/userinfo',
        'to https://$team@evil.example/',
      ),
      'the team host on another port': ('/port', 'to https://$team:8443/'),
      'plain http to the team host': ('/plain-http', 'to http://$team/'),
      'the sign-in of ANOTHER hostname': (
        '/other-host-login',
        'to https://$team/cdn-cgi/access/login/admin.myweli.com,',
      ),
      'a login path that only starts with the right hostname': (
        '/login-prefix',
        'login/127.0.0.1.evil.example,',
      ),
      'a login path with more after the hostname': (
        '/login-longer',
        'login/127.0.0.1/more,',
      ),
      'a redirect with no Location': (
        '/no-location',
        'answered 302 with no Location',
      ),
    };

    cases.forEach((name, c) {
      final (path, line) = c;
      test(name, () async {
        final r = await verify(['$base$path']);
        expect(r.exitCode, 1, reason: r.out);
        expect(r.out, contains('✗ $base$path'));
        expect(r.out, contains(line.replaceAll('BASE', base)));
        expect(r.out, contains(restrict), reason: 'the fix is not named');
        expect(r.out, isNot(contains('PUBLIC')));
        expect(r.out, isNot(contains('meta-must-not-be-logged')));
      });
    });

    test(
      '200 on a real hostname: its fix names that hostname, no probe note',
      () async {
        final r = await verify(['$base/public']);
        expect(r.out, contains('Fix: add 127.0.0.1 back'));
        expect(r.out, isNot(contains('*.')));
        expect(r.out, isNot(contains('made up')));
      },
    );

    test('a renamed team domain: red, and it says that is all it is', () async {
      final r = await verify(['$base/renamed']);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('Only the team domain differs'));
      expect(r.out, contains('TEAM_HOST_DEFAULT'));
      // Nothing is public, so « add it back » would send the reader the wrong way.
      expect(r.out, isNot(contains('back to the Access application')));
      expect(r.out, isNot(contains('meta-must-not-be-logged')));
    });

    test('no answer at all: nothing measured is not green', () async {
      final r = await verify(['$closedBase/main.dart.js']);
      expect(r.exitCode, 1, reason: r.out);
      expect(
        r.out,
        contains('could not reach $closedBase/main.dart.js — nothing measured'),
      );
      expect(r.out, isNot(contains('All 1')));
    });

    test('something that is not an http(s) URL', () async {
      final r = await verify(['admin.myweli.com/']);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('not an http(s) URL'));
    });
  });

  group('red, but what came back shows nothing public: it says so', () {
    // Neither the console nor the sign-in: a 404 off the probe, a 403, a 5xx.
    // « Add it back » would send the owner to the dashboard to add a hostname
    // that may still be there (spec §5), so no fix line, a look by hand.
    for (final (name, path, code) in [
      ('404 on an address that is not the probe', '/missing', 404),
      ('403', '/refused', 403),
    ]) {
      test(name, () async {
        final r = await verify(['$base$path']);
        expect(r.exitCode, 1, reason: r.out);
        expect(r.out, contains('✗ $base$path → $code'));
        expect(
          r.out,
          contains(
            'answered $code: neither the Access sign-in nor the console',
          ),
        );
        expect(r.out, contains('does not show the console is public'));
        expect(r.out, contains('Look by hand first: open $base$path'));
        expect(r.out, contains('Only if 127.0.0.1 is missing from it'));
        expect(r.out, isNot(contains('Fix: add')));
        expect(r.out, isNot(contains('PUBLIC')));
        expect(r.out, isNot(contains('cf-mitigated')));
      });
    }

    test('a Cloudflare challenge of the runner is named as one', () async {
      final r = await verify(['$base/challenged']);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('answered 403: neither the Access sign-in'));
      expect(
        r.out,
        contains('Cloudflare marked that answer « cf-mitigated: challenge »'),
      );
      expect(r.out, contains('does not show the console is public'));
      expect(r.out, isNot(contains('Fix: add')));
      expect(r.out, isNot(contains('PUBLIC')));
    });
  });

  group('every URL is read before the exit', () {
    test(
      'a bad one first does not hide the good ones or a second bad one',
      () async {
        final r = await verify([
          '$base/public',
          '$base/behind',
          '$closedBase/x',
          '$base/behind/307',
        ]);
        expect(r.exitCode, 1, reason: r.out);
        expect(r.out, contains('PUBLIC at $base/public'));
        expect(r.out, contains('✓ $base/behind → 302'));
        expect(r.out, contains('could not reach $closedBase/x'));
        expect(r.out, contains('✓ $base/behind/307 → 307'));
        expect(r.out, contains('2 of 4 console addresses'));
      },
    );
  });

  group('it refuses to report success having read nothing', () {
    test('a list of spaces only', () async {
      final r = await verify(['   ', '']);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('refusing to report success'));
    });

    test('an empty team host', () async {
      final r = await verify(['$base/behind'], teamHost: '');
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('refusing to report success'));
    });
  });

  group('with no variable: the production list, against a stand-in curl', () {
    const expected = [
      'https://admin.myweli.com/',
      'https://admin.myweli.com/main.dart.js',
      'https://myweli-admin.pages.dev/',
      'https://myweli-admin.pages.dev/main.dart.js',
      'https://zz-access-probe.myweli-admin.pages.dev/',
      'https://zz-access-probe.myweli-admin.pages.dev/main.dart.js',
    ];

    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('console_access_');
      // Logs each call, then answers as Access did on 2026-11-13: a 302 to the
      // sign-in of the requested host on the real team domain, written in the
      // format the script's own -w asks for, `\n` turned into a newline as
      // curl does. $FAKE_HOST answers $FAKE_CODE instead, with no Location and
      // $FAKE_MITIGATED as its cf-mitigated header.
      File('${dir.path}/curl').writeAsStringSync(r'''#!/usr/bin/env bash
{ printf '%s\037' "$@"; printf '\036'; } >> "$CURL_LOG"
fmt='' url=''
while [ $# -gt 0 ]; do
  case "$1" in
    -w|--write-out) fmt=$2; shift 2 ;;
    http://*|https://*) url=$1; shift ;;
    *) shift ;;
  esac
done
rest=${url#*://}
host=${rest%%/*}
code=302
loc="https://blue-base-1ad1.cloudflareaccess.com/cdn-cgi/access/login/${host}?kid=k"
mitigated=''
if [ "$host" = "${FAKE_HOST:-}" ]; then
  code=$FAKE_CODE loc='' mitigated=${FAKE_MITIGATED:-}
fi
out=${fmt//'%{http_code}'/$code}
out=${out//'%{redirect_url}'/$loc}
out=${out//'%header{cf-mitigated}'/$mitigated}
out=${out//'\n'/$'\n'}
printf '%s' "$out"
''');
      Process.runSync('chmod', ['+x', '${dir.path}/curl']);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Future<({int exitCode, String out, List<List<String>> calls})> defaults({
      String? host,
      int code = 200,
      Map<String, String> extra = const {},
    }) async {
      final log = File('${dir.path}/curl.log')..writeAsStringSync('');
      final r = await Process.run(
        'bash',
        [scriptFile.path],
        includeParentEnvironment: false,
        environment: {
          'PATH': '${dir.path}:${Platform.environment['PATH']}',
          'CURL_LOG': log.path,
          if (host != null) ...{'FAKE_HOST': host, 'FAKE_CODE': '$code'},
          ...extra,
        },
      );
      final calls = log
          .readAsStringSync()
          .split('\x1e')
          .where((call) => call.isNotEmpty)
          .map((call) => (call.split('\x1f')..removeLast()))
          .toList();
      return (
        exitCode: r.exitCode,
        out: '${r.stdout}${r.stderr}',
        calls: calls,
      );
    }

    List<String> urlsOf(List<List<String>> calls) => [
      for (final args in calls)
        args.singleWhere((a) => RegExp('^https?://').hasMatch(a)),
    ];

    test('it asks for exactly the six URLs of spec §3, and is green', () async {
      final r = await defaults();
      expect(r.exitCode, 0, reason: r.out);
      expect(urlsOf(r.calls), expected);
      expect(r.out, contains('All 6 console addresses'));
      expect(r.out, contains('team blue-base-1ad1.cloudflareaccess.com'));
      expect(r.out, isNot(contains('REHEARSAL')));
    });

    test(
      'three hostnames, the wildcard among them, each at / and the bundle',
      () async {
        final urls = urlsOf((await defaults()).calls).map(Uri.parse).toList();
        final hosts = urls.map((u) => u.host).toSet();
        expect(hosts, {
          'admin.myweli.com',
          'myweli-admin.pages.dev',
          'zz-access-probe.myweli-admin.pages.dev',
        });
        for (final host in hosts) {
          expect(urls.where((u) => u.host == host).map((u) => u.path).toSet(), {
            '/',
            '/main.dart.js',
          }, reason: host);
        }
      },
    );

    test('one request each, anonymous, redirects not followed', () async {
      final r = await defaults();
      for (final args in r.calls) {
        for (final flag in [
          '-L',
          '--location',
          '--location-trusted',
          '-H',
          '--header',
          '-b',
          '--cookie',
          '-u',
          '--user',
          '-X',
          '--request',
          '-d',
          '--data',
        ]) {
          expect(args, isNot(contains(flag)), reason: '$args');
        }
        expect(args, contains('--max-time'));
      }
    });

    test('a public address in the production list turns it red', () async {
      final r = await defaults(host: 'myweli-admin.pages.dev');
      expect(r.exitCode, 1, reason: r.out);
      expect(
        r.out,
        contains('the console is PUBLIC at https://myweli-admin.pages.dev/'),
      );
      expect(
        r.out,
        contains(
          'the console is PUBLIC at https://myweli-admin.pages.dev/main.dart.js',
        ),
      );
      expect(r.out, contains('2 of 6 console addresses'));
      expect(r.out, contains('Fix: add myweli-admin.pages.dev back'));
      expect(r.out, isNot(contains('*.myweli-admin.pages.dev')));
    });

    // The probe is a made-up name that stands for the wildcard. Adding THAT
    // name to Access turns the check green and leaves every real preview
    // (<hash>.myweli-admin.pages.dev) public, so the fix must name the
    // wildcard and warn off the probe's own name (spec §5).
    const probe = 'zz-access-probe.myweli-admin.pages.dev';
    for (final (code, why) in [
      (404, 'what Pages gives an alias it does not know: the wildcard is gone'),
      (200, 'something served there without Access'),
    ]) {
      test('the probe answering $code ($why): the fix names the wildcard, '
          'never the probe', () async {
        final r = await defaults(host: probe, code: code);
        expect(r.exitCode, 1, reason: r.out);
        expect(r.out, contains('2 of 6 console addresses'));
        expect(
          r.out,
          contains(
            'Fix: add *.myweli-admin.pages.dev back to the Access application',
          ),
        );
        expect(r.out, contains('every preview address'));
        expect(
          r.out,
          contains(
            "Do not put the probe's own name, $probe, in the application",
          ),
        );
        expect(r.out, isNot(contains('add zz-access-probe')));
        expect(r.out, isNot(contains('add $probe')));
      });
    }

    test('the probe answering 404 says the wildcard is gone', () async {
      final r = await defaults(host: probe, code: 404);
      expect(r.out, contains('the wildcard *.myweli-admin.pages.dev is gone'));
      expect(r.out, isNot(contains('neither the Access sign-in')));
    });

    test('the probe answering 403: a look by hand, at the wildcard', () async {
      final r = await defaults(host: probe, code: 403);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('does not show the console is public'));
      expect(r.out, contains('Only if *.myweli-admin.pages.dev is missing'));
      expect(r.out, isNot(contains('Fix: add')));
      expect(r.out, isNot(contains('add zz-access-probe')));
    });

    test('a variable set but empty is refused, never swapped for the production '
        'list', () async {
      // An empty value read as « use the defaults » would let a mistyped
      // override measure production while saying it rehearsed, and the reverse.
      for (final name in ['CONSOLE_ACCESS_URLS', 'CONSOLE_ACCESS_TEAM_HOST']) {
        final r = await defaults(extra: {name: ''});
        expect(r.exitCode, 1, reason: '$name: ${r.out}');
        expect(r.out, contains('refusing to report success'), reason: name);
        expect(r.calls, isEmpty, reason: name);
      }
    });
  });

  group('the daily job', () {
    YamlMap job() => jobs['access'] as YamlMap;
    List<YamlMap> steps() => (job()['steps'] as YamlList).cast<YamlMap>();

    test('exists, checks out, then runs exactly the script', () {
      expect(
        jobs.keys,
        contains('access'),
        reason: 'a check nothing runs is a file',
      );
      final s = steps();
      final checkout = s.indexWhere(
        (x) => (x['uses'] as String? ?? '').startsWith('actions/checkout@'),
      );
      final run = s.indexWhere((x) => x.containsKey('run'));
      expect(checkout, isNonNegative);
      expect(run, greaterThan(checkout));
      expect((s[run]['run'] as String).trim(), 'bash $scriptPath');
    });

    test('sets no variable: the job measures production, not a rehearsal', () {
      expect(workflow.containsKey('env'), isFalse);
      expect(job().containsKey('env'), isFalse);
      for (final step in steps()) {
        expect(step.containsKey('env'), isFalse, reason: '${step['name']}');
      }
      // The ASSIGNMENT form: the workflow says in a comment that they are not
      // set, and a guard that forbids naming a thing forbids explaining it.
      for (final f in Directory('$root/.github/workflows').listSync()) {
        if (f is! File) continue;
        expect(
          RegExp(
            r'CONSOLE_ACCESS_(URLS|TEAM_HOST)\s*[:=]',
          ).hasMatch(f.readAsStringSync()),
          isFalse,
          reason: '${f.path} sets a rehearsal variable',
        );
      }
    });

    test('holds contents: read and nothing else', () {
      expect(
        (job()['permissions'] as YamlMap).map((k, v) => MapEntry('$k', '$v')),
        {'contents': 'read'},
      );
    });

    test('a red run reaches the alarm, and the issue says what to do', () {
      expect(
        (jobs['report']['needs'] as YamlList).toList(),
        contains('access'),
      );
      expect((jobs['clear']['needs'] as YamlList).toList(), contains('access'));
      final report = (jobs['report']['steps'] as YamlList)
          .cast<YamlMap>()
          .singleWhere((s) => s.containsKey('run'));
      final env = report['env'] as YamlMap;
      final name = env.keys.cast<String>().singleWhere(
        (k) => env[k] == r'${{ needs.access.result }}',
      );
      final script = report['run'] as String;
      final statusLine = script
          .split('\n')
          .singleWhere((l) => l.contains(r'CWV: ${CWV}'));
      expect(statusLine, contains('\${$name}'));
      // The body is printf arguments, one per line; joined as the issue reads.
      final body = script.replaceAll(RegExp(r"'\s*\\\n\s*'"), ' ');
      for (final words in [
        fixApp,
        restrict,
        'zz-access-probe',
        'Add *.myweli-admin.pages.dev back, never the made-up name itself',
        'does not show the console is public',
        'cf-mitigated',
      ]) {
        expect(body, contains(words));
      }
    });
  });

  group('the script', () {
    test('is executable', () {
      expect(scriptFile.statSync().mode & 0x40, isNonZero);
    });

    test('carries no credential, comments included', () {
      // A request that carried one would pass through Access and see nothing.
      final text = scriptFile.readAsStringSync().toLowerCase();
      for (final word in [
        'authorization',
        'cookie',
        'cf-access-client',
        'cf_authorization',
        'bearer',
      ]) {
        expect(text, isNot(contains(word)), reason: word);
      }
    });
  });
}
