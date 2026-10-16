import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `SalonClientCard.phoneEditable` (docs/design/phone-leftovers.md §8/§11):
/// the clients show « Modifier » on a card's number only when the server
/// says so. The handler tests prove the server sends it
/// (`clients_phone_change_test.dart`); this proves the contract a client is
/// built from says the same — a boolean, always sent, on the card only, and
/// that an absent field means false.
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final schemas =
      ((doc as YamlMap)['components'] as YamlMap)['schemas'] as YamlMap;

  /// The card's own part — the `allOf` member that is not the `$ref`.
  YamlMap cardPart() {
    final allOf = (schemas['SalonClientCard'] as YamlMap)['allOf'] as YamlList;
    return allOf.whereType<YamlMap>().singleWhere(
      (m) => !m.containsKey(r'$ref'),
    );
  }

  test('SalonClientCard requires a boolean phoneEditable', () {
    final part = cardPart();
    expect(part['required'] as YamlList, contains('phoneEditable'));
    final prop = (part['properties'] as YamlMap)['phoneEditable'] as YamlMap?;
    expect(prop, isNotNull);
    expect(prop!['type'], 'boolean');
  });

  test('its description names the rule and what an absent field means', () {
    final prop =
        (cardPart()['properties'] as YamlMap)['phoneEditable'] as YamlMap;
    final description = prop['description'] as String;
    expect(description, contains('client_linked'));
    expect(description, contains('client_anonymized'));
    expect(description, contains('ABSENT'));
  });

  test('the list rows (SalonClient) do not declare it — the card does', () {
    final props = (schemas['SalonClient'] as YamlMap)['properties'] as YamlMap;
    expect(props.containsKey('phoneEditable'), isFalse);
  });
}
