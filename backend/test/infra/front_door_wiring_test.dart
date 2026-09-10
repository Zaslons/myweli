import 'dart:io';

import 'package:test/test.dart';

/// The front door is three components that never compile together — a Dart
/// middleware, a JavaScript Worker, a shell script against Cloudflare's API —
/// and they agree on strings nobody's compiler checks: the header the Worker
/// sets and the origin reads, the hostname the Worker forwards to, the route
/// the script deploys, the order in which the script inspects before it
/// overwrites. A drift in any of them is a production outage with every
/// per-component test green — the shape this repo keeps finding, so it gets
/// a source-level pin across the component boundary.
///
/// Design: docs/design/infra-cloudflare-front-door.md §8 ("Source-level
/// wiring pins"). The per-component pins live beside their components
/// (origin_front_door_wiring_test.dart, front_door_scripts_test.dart); this
/// file holds only the ones that span two of them.
void main() {
  final root = Directory.current.path.endsWith('/backend')
      ? Directory.current.parent.path
      : Directory.current.path;
  String read(String rel) => File('$root/$rel').readAsStringSync();

  /// JavaScript with `//` and `/* */` comments removed, because the Worker's
  /// header comment quotes the very strings these pins look for (a comment
  /// satisfied two guards in this repo before — see
  /// myweli-verification-guardrails §2).
  String stripJs(String src) => src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  /// Shell with full-line comments removed.
  String stripSh(String src) =>
      src.split('\n').where((l) => !l.trimLeft().startsWith('#')).join('\n');

  final dart = read('backend/lib/src/security/origin_front_door.dart');
  final js = stripJs(
    read('infra/cloudflare/worker/api-front-door/src/index.js'),
  );
  final toml = read('infra/cloudflare/worker/api-front-door/wrangler.toml');
  final script = read('infra/cloudflare/96-api-front-door.sh');
  final scriptCode = stripSh(script);

  group('the origin-auth header is one string on both sides of the door', () {
    test(
      'the Dart side reads it, lower-cased (shelf headers are case-insensitive)',
      () {
        expect(
          dart,
          contains("const String kOriginAuthHeader = 'x-myweli-origin-auth';"),
          reason:
              'origin_front_door.dart must declare the header name as a '
              'named constant, lower-cased — the string these pins compare',
        );
      },
    );

    test('the Worker sets the same header (compared case-insensitively)', () {
      final m = RegExp(r"const ORIGIN_AUTH_HEADER = '([^']+)';").firstMatch(js);
      expect(m, isNotNull, reason: 'index.js declares ORIGIN_AUTH_HEADER once');
      expect(
        m!.group(1)!.toLowerCase(),
        'x-myweli-origin-auth',
        reason:
            'the Worker sets a header the origin does not read — every '
            'request through the front door would be answered 403 '
            'origin_required',
      );
      expect(
        js,
        contains('headers.set(ORIGIN_AUTH_HEADER, env.ORIGIN_AUTH_SECRET)'),
        reason: 'the constant must actually be the header that is set',
      );
    });
  });

  group('the Worker is a proxy, not a client', () {
    test("forwards with redirect: 'manual' (in code, not in a comment)", () {
      expect(
        js,
        contains("redirect: 'manual'"),
        reason:
            "with 'follow', the runtime forwards Authorization to a 3xx "
            'target even across hosts (Cloudflare docs) — the cron OIDC token '
            'would leak to wherever the origin redirected',
      );
    });

    test('never sets a Host header — the runtime derives it from the URL', () {
      expect(js.toLowerCase(), isNot(contains("set('host'")));
      expect(js.toLowerCase(), isNot(contains('set("host"')));
      expect(js, contains('url.hostname = env.ORIGIN_HOST'));
    });

    test(
      'answers http:// with a 301 to https:// on the public host, never proxies in clear',
      () {
        expect(
          js,
          contains("url.protocol === 'http:'"),
          reason:
              'without this, an http:// client is proxied to the origin over '
              'http, Cloud Run answers 301 naming its own run.app hostname, and '
              "redirect: 'manual' hands that to the client — who follows it to "
              'the direct door and is refused (found in review)',
        );
        expect(js, contains('Response.redirect('));
        expect(js, contains('301'));
      },
    );

    test(
      'refuses to forward without the secret rather than forwarding bare',
      () {
        expect(js, contains('!env.ORIGIN_AUTH_SECRET'));
        expect(js, contains('status: 500'));
      },
    );
  });

  group('wrangler.toml matches the spec and holds no secret', () {
    test('routes api.myweli.com/* on the myweli.com zone', () {
      expect(toml, contains('pattern = "api.myweli.com/*"'));
      expect(toml, contains('zone_name = "myweli.com"'));
      expect(toml, contains('name = "myweli-api-front-door"'));
    });

    test('forwards to the status.url hostname the spec fixes', () {
      expect(
        toml,
        contains('ORIGIN_HOST = "myweli-api-5a24ymhbbq-od.a.run.app"'),
        reason:
            'Cloud Run answers 404 to a Host it does not recognise; only '
            'the service\'s own hostnames work, and status.url is the one the '
            'deploy pipeline treats as canonical',
      );
    });

    test('the secret is a binding, never a value in the file', () {
      expect(toml, isNot(contains('ORIGIN_AUTH_SECRET =')));
      expect(toml, isNot(contains('ORIGIN_AUTH_SECRET=')));
    });
  });

  group('96-api-front-door.sh looks before it overwrites, and never leaks', () {
    test('the ownership GET of the ratelimit phase precedes the only PUT', () {
      final get = scriptCode.indexOf(
        'rulesets/phases/http_ratelimit/entrypoint',
      );
      final put = scriptCode.indexOf('cf PUT ');
      expect(get, isNonNegative, reason: 'the script reads the phase first');
      expect(put, isNonNegative, reason: 'the script writes the phase');
      expect(
        get,
        lessThan(put),
        reason:
            'PUT replaces the WHOLE rules list (Cloudflare docs) — a PUT '
            'before the ownership check would silently delete any rule the '
            'owner made by hand',
      );
      expect(
        scriptCode,
        contains('ENTRY_STATUS'),
        reason: 'the refusal branch keys on the GET status',
      );
    });

    test('reads both secrets by their fixed Secret Manager names', () {
      expect(script, contains('--secret=CLOUDFLARE_FRONT_DOOR_TOKEN'));
      expect(script, contains('--secret=ORIGIN_AUTH_SECRET'));
    });

    test('never echoes the token', () {
      final leaks = scriptCode
          .split('\n')
          .where((l) => l.contains('CLOUDFLARE_API_TOKEN'))
          .where((l) => l.trimLeft().startsWith('echo'))
          .toList();
      expect(
        leaks,
        isEmpty,
        reason:
            'a token on an echo line is a token in '
            'a terminal scrollback and a CI log: $leaks',
      );
    });

    test('pipes the origin secret into wrangler on stdin, never on argv', () {
      expect(
        script,
        contains('secret put ORIGIN_AUTH_SECRET'),
        reason: 'the Worker binding is set with wrangler secret put',
      );
      final onArgv = scriptCode
          .split('\n')
          .where(
            (l) =>
                l.contains('secret put ORIGIN_AUTH_SECRET') &&
                l.contains(r'$ORIGIN'),
          );
      expect(onArgv, isEmpty, reason: 'a value on argv is visible to ps');
    });
  });

  group('the runbook that pages on the per-IP refusal knows the bucket', () {
    test('92-identity-limit-alert.sh names the ip:auth: shape', () {
      final runbook = read('infra/gcp/92-identity-limit-alert.sh');
      expect(
        runbook,
        contains('ip:auth:'),
        reason:
            '91-armor-deny-alert.sh\'s RETIRED banner says 92 already '
            'pages on this line; if the runbook does not explain the bucket, '
            'the operator reading the page at 2am cannot tell a client burst '
            'from a booking ceiling',
      );
      expect(
        dart,
        contains('ip:auth:'),
        reason: 'and the middleware really builds that prefix',
      );
    });
  });
}
