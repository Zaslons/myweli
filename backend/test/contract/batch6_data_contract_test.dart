import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// docs/design/backend-integrity-batch6.md §2.5 (B6.5) — the deposit policy's
/// two new refusals are in the contract, each said under its control.
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final put =
      (doc['paths'] as YamlMap)['/providers/{id}/deposit-policy']['put']
          as YamlMap;

  test('PUT deposit-policy documents invalid_percentage and '
      'operator_unavailable', () {
    final bad = '${(put['responses'] as YamlMap)['400']['description']}';
    expect(bad, contains('invalid_percentage'));
    expect(bad, contains('operator_unavailable'));
  });

  test('…and says the range, and that an unknown operator is not kept', () {
    final text = '${put['description']}';
    expect(text, contains('0.05–0.80'));
    expect(text, contains('not kept'));
  });
}
