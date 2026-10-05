import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The companion path's contract (docs/design/pro-companion-path.md §3):
/// the two new demo refusals and the publish-time trial start are part of
/// the API, so the document has to say so — the handler tests prove the
/// server answers them, this proves a client reading the contract can know.
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final paths = (doc as YamlMap)['paths'] as YamlMap;

  YamlMap op(String path, String method) =>
      (paths[path] as YamlMap)[method] as YamlMap;

  String response(String path, String method, String status) {
    final responses = op(path, method)['responses'] as YamlMap;
    final r = responses[status];
    expect(r, isA<YamlMap>(), reason: '$method $path documents $status');
    // A bare `$ref` to the shared Forbidden carries no code at all — the
    // thing this test exists to refuse.
    return ((r as YamlMap)['description'] as String?) ?? '';
  }

  test(
    'PUT /providers/{id}/subscription documents 403 demo_account_locked',
    () {
      expect(
        response('/providers/{id}/subscription', 'put', '403'),
        contains('demo_account_locked'),
      );
    },
  );

  test('POST /me/salons documents 403 demo_account_locked', () {
    expect(
      response('/me/salons', 'post', '403'),
      contains('demo_account_locked'),
    );
  });

  test('publish says the trial starts there, and when `offer` still '
      'appears', () {
    final description =
        op('/providers/{id}/publish', 'post')['description'] as String;
    expect(description, contains('The trial starts here when no offer exists'));
    expect(
      response('/providers/{id}/publish', 'post', '409'),
      contains('expired'),
    );
  });

  test('publish documents its two 403 refusals: the demo lock and an '
      'admin suspension', () {
    final forbidden = response('/providers/{id}/publish', 'post', '403');
    expect(forbidden, contains('demo_account_locked'));
    expect(forbidden, contains('provider_suspended'));
  });

  test('POST /admin/demo/snapshot is in the contract: audited, refuses a '
      'non-demo-owned target', () {
    final description =
        op('/admin/demo/snapshot', 'post')['description'] as String;
    expect(description, contains('demo.snapshot'));
    expect(
      response('/admin/demo/snapshot', 'post', '409'),
      contains('not_demo_owned'),
    );
  });

  test('the subscription GET 404 is the setup state, ended by the first '
      'publish or the first choice', () {
    expect(
      response('/providers/{id}/subscription', 'get', '404'),
      contains('first publish'),
    );
  });
}
