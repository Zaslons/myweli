import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The demo account's deletion lock is part of the API
/// (docs/design/demo-account-deletion-lock.md §3): a client that reads the
/// contract has to be able to tell this 403 from the ordinary `forbidden`,
/// or it cannot show the sentence the store review notes promise. The
/// handler tests prove the server answers it; this proves the document says
/// so.
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final paths = (doc as YamlMap)['paths'] as YamlMap;
  final delete = (paths['/me/provider'] as YamlMap)['delete'] as YamlMap;
  final responses = delete['responses'] as YamlMap;

  /// The response's OWN description. A bare `$ref` to the shared Forbidden
  /// has none, and carries no code at all — the thing this test refuses.
  String describes(String status) {
    final r = responses[status];
    expect(r, isA<YamlMap>(), reason: 'DELETE /me/provider documents $status');
    return ((r as YamlMap)['description'] as String?) ?? '';
  }

  test('DELETE /me/provider documents 403 demo_account_locked, beside the '
      'ordinary forbidden', () {
    final forbidden = describes('403');
    expect(forbidden, contains('demo_account_locked'));
    expect(forbidden, contains('`forbidden`'));
  });

  test('the operation says the demo account is refused before the agenda '
      'gate, and names the threat', () {
    final description = delete['description'] as String;
    expect(description, contains('demo_account_locked'));
    expect(description, contains('T69'));
    expect(description, contains('before the future-bookings gate'));
  });

  test('the other answers are still documented: 204, 401, 409 '
      'future_bookings', () {
    expect(responses['204'], isNotNull);
    expect(responses['401'], isNotNull);
    expect(describes('409'), contains('future_bookings'));
  });
}
