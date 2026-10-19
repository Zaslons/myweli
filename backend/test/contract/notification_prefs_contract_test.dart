import 'dart:io';

import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `NotificationPreferences.emailAlerts` (docs/design/salon-email-alerts.md
/// §5): the web Pro switch is built from the contract, so the contract must
/// say what the server sends — and accept what the switch writes.
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final schemas =
      ((doc as YamlMap)['components'] as YamlMap)['schemas'] as YamlMap;
  final prefs = schemas['NotificationPreferences'] as YamlMap;

  test('the schema is exactly what the server serializes — no drift', () {
    final served = const NotificationPrefs().toJson().keys.toSet();
    final declared = (prefs['properties'] as YamlMap).keys.toSet();
    expect(declared, served);
    expect((prefs['required'] as YamlList).toSet(), served);
  });

  test('emailAlerts is a boolean', () {
    final prop = (prefs['properties'] as YamlMap)['emailAlerts'] as YamlMap;
    expect(prop['type'], 'boolean');
  });

  test('PUT accepts emailAlerts', () {
    final put =
        ((doc['paths'] as YamlMap)['/me/notification-preferences']
                as YamlMap)['put']
            as YamlMap;
    final schema =
        (((put['requestBody'] as YamlMap)['content']
                    as YamlMap)['application/json']
                as YamlMap)['schema']
            as YamlMap;
    final prop = (schema['properties'] as YamlMap)['emailAlerts'] as YamlMap?;
    expect(prop, isNotNull);
    expect(prop!['type'], 'boolean');
  });
}
