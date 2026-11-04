import 'dart:io';

import 'package:myweli_backend/src/idempotency/idempotent.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `Idempotency-Key` (docs/design/write-idempotency.md §3): the four creating
/// POSTs declare it, its three codes and the replay header — and NOTHING else
/// takes it (the web BFF forwards it on these four routes only, §4).
void main() {
  final doc =
      loadYaml(File('../docs/api/openapi.yaml').readAsStringSync()) as YamlMap;
  final paths = doc['paths'] as YamlMap;
  final components = doc['components'] as YamlMap;

  const four = {
    '/appointments',
    '/providers/{id}/appointments',
    '/providers/{id}/clients/{clientId}/notes',
    '/me/provider/members',
  };
  const ref = '#/components/parameters/IdempotencyKey';

  bool takesKey(YamlMap op) => ((op['parameters'] as YamlList?) ?? YamlList())
      .any((p) => p is YamlMap && p[r'$ref'] == ref);

  test('the header: optional, and the server’s pattern exactly', () {
    final p =
        (components['parameters'] as YamlMap)['IdempotencyKey'] as YamlMap;
    expect(p['name'], 'Idempotency-Key');
    expect(p['in'], 'header');
    expect(p['required'], isFalse);
    expect((p['schema'] as YamlMap)['pattern'], kIdempotencyKeyPattern);
    final said = p['description'] as String;
    for (final code in [
      'invalid_idempotency_key',
      'request_in_progress',
      'idempotency_key_reused',
    ]) {
      expect(said, contains(code));
    }
  });

  for (final path in four) {
    test('POST $path takes it, can answer 422, and says when it replayed', () {
      final post = (paths[path] as YamlMap)['post'] as YamlMap;
      expect(takesKey(post), isTrue);
      final responses = post['responses'] as YamlMap;
      expect(
        (responses['422'] as YamlMap)[r'$ref'],
        '#/components/responses/IdempotencyKeyReused',
      );
      expect(responses['409'], isNotNull, reason: 'request_in_progress');
      final created = responses['201'] as YamlMap;
      expect(
        ((created['headers'] as YamlMap)['Idempotent-Replayed']
            as YamlMap)[r'$ref'],
        '#/components/headers/IdempotentReplayed',
      );
    });
  }

  test('and no other operation takes it', () {
    final others = <String>[
      for (final MapEntry(:key, :value) in paths.entries)
        for (final MapEntry(key: verb, value: op) in (value as YamlMap).entries)
          if (op is YamlMap &&
              takesKey(op) &&
              !(verb == 'post' && four.contains(key)))
            '$verb $key',
    ];
    expect(others, isEmpty);
  });
}
