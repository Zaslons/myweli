import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `GET /me/provider/reviews` and `GET /providers/{id}/reviews` → `summary`
/// (docs/design/salon-reviews-summary.md, salon-team-and-reviews.md §3): the
/// « Avis » card is built from it on web and app, so the contract says it is
/// always sent, with the 1–5 split under string keys.
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final schemas =
      ((doc as YamlMap)['components'] as YamlMap)['schemas'] as YamlMap;

  // The salon's own « Avis » (salon-reviews-summary.md) and, since A5-api, the
  // public list a client's « Avis » screen reads (salon-team-and-reviews.md
  // §3). Both draw the card from the server's summary, never from the page.
  for (final path in ['/me/provider/reviews', '/providers/{id}/reviews']) {
    test('$path requires a ReviewSummary', () {
      final get =
          ((doc['paths'] as YamlMap)[path] as YamlMap)['get'] as YamlMap;
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
  }

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
