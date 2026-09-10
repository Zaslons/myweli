import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Every operation under `/auth/` and `/admin/auth/` documents a 429.
///
/// The per-IP limit of the origin front door (10 per minute per address,
/// `docs/design/infra-cloudflare-front-door.md` §3) applies to the whole
/// prefix, so a 429 is now possible on every one of these paths — where before
/// only the four `otp/request` routes and two admin ones could refuse. A path
/// added tomorrow under either prefix inherits the limit by construction
/// (`isIpLimitedPath` is a prefix test), so it must inherit the documentation
/// too; this is what makes that a test failure rather than a contract drift.
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final paths = (doc as YamlMap)['paths'] as YamlMap;

  final limited = [
    for (final k in paths.keys)
      if ((k as String).startsWith('/auth/') || k.startsWith('/admin/auth/')) k,
  ];

  test('the scope is the twenty paths the spec counts', () {
    // 17 under /auth/, 3 under /admin/auth/ — spec §3. A change here is not a
    // failure, it is a prompt to re-read the scope of the limiter.
    expect(limited, hasLength(20), reason: limited.join(', '));
  });

  for (final path in limited) {
    final item = paths[path] as YamlMap;
    for (final method in item.keys) {
      final op = item[method];
      if (op is! YamlMap || !op.containsKey('responses')) continue;
      test('$method $path documents 429', () {
        final responses = op['responses'] as YamlMap;
        expect(
          responses.keys.map((k) => k.toString()),
          contains('429'),
          reason:
              'the origin front door can answer 429 rate_limited on any '
              '/auth/* or /admin/auth/* path; add '
              "'429': { \$ref: '#/components/responses/RateLimited' }",
        );
      });
    }
  }

  test('origin_required is documented once, in the shared Error schema', () {
    final error =
        ((doc['components'] as YamlMap)['schemas'] as YamlMap)['Error']
            as YamlMap;
    final description = error['description'] as String?;
    expect(description, isNotNull);
    expect(description, contains('origin_required'));
    expect(description, contains('/health'));
  });
}
