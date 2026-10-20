import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `GET /me/provider/reviews` → `summary` (docs/design/salon-reviews-summary.md):
/// the « Avis » card is built from it on web and app, so the contract says it
/// is always sent, with the 1–5 split under string keys.
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final schemas =
      ((doc as YamlMap)['components'] as YamlMap)['schemas'] as YamlMap;

  test('the salon reviews page requires a ReviewSummary', () {
    final get =
        ((doc['paths'] as YamlMap)['/me/provider/reviews'] as YamlMap)['get']
            as YamlMap;
    final schema =
        ((((get['responses'] as YamlMap)['200'] as YamlMap)['content']
                    as YamlMap)['application/json']
                as YamlMap)['schema']
            as YamlMap;
    expect(schema['required'] as YamlList, contains('summary'));
    expect(
      ((schema['properties'] as YamlMap)['summary'] as YamlMap)[r'$ref'],
      '#/components/schemas/ReviewSummary',
    );
  });

  test('ReviewSummary: average, count, and the five stars', () {
    final s = schemas['ReviewSummary'] as YamlMap;
    expect((s['required'] as YamlList).toSet(), {
      'average',
      'count',
      'distribution',
    });
    final dist = (s['properties'] as YamlMap)['distribution'] as YamlMap;
    expect((dist['required'] as YamlList).toSet(), {'1', '2', '3', '4', '5'});
  });
}
