import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// docs/design/backend-integrity-batch6.md §13 (B6.7) — the three Apple
/// sign-in bodies take Apple's one-time code, and the redirect the web's BFF
/// adds; neither is required (a sign-in without them is the sign-in as
/// before).
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final paths = doc['paths'] as YamlMap;

  YamlMap schemaOf(String path) =>
      paths[path]['post']['requestBody']['content']['application/json']['schema']
          as YamlMap;

  for (final path in [
    '/auth/apple',
    '/auth/provider/apple',
    '/auth/provider/register',
  ]) {
    test('$path: authorizationCode and redirectUri, both optional strings', () {
      final schema = schemaOf(path);
      final props = schema['properties'] as YamlMap;
      for (final field in ['authorizationCode', 'redirectUri']) {
        expect((props[field] as YamlMap)['type'], 'string', reason: field);
        expect(
          (schema['required'] as YamlList?)?.contains(field) ?? false,
          isFalse,
          reason: '$field must stay optional',
        );
      }
      expect('${props['redirectUri']['description']}', contains('BFF'));
    });
  }
}
