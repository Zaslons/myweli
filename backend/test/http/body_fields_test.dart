import 'dart:convert';

import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:test/test.dart';

/// The typed body readers (docs/design/phone-leftovers.md §3). Bodies are
/// built with `jsonDecode`, because that is the only way one reaches a route:
/// a JSON list arrives as `List<dynamic>`, never a `List<String>`.
void main() {
  Map<String, dynamic> body(String json) =>
      jsonDecode(json) as Map<String, dynamic>;

  /// Throws a [BodyFieldTypeError] naming [key] — not a `TypeError`, which
  /// the middleware reports as a server fault.
  Matcher refuses(String key) =>
      throwsA(isA<BodyFieldTypeError>().having((e) => e.key, 'key', key));

  group('optionalString', () {
    test('absent → null', () {
      expect(optionalString(body('{}'), 'name'), isNull);
    });

    test('JSON null → null, the same as absent', () {
      expect(optionalString(body('{"name": null}'), 'name'), isNull);
    });

    test('a string → that string, untouched (no trim here)', () {
      expect(optionalString(body('{"name": " Awa "}'), 'name'), ' Awa ');
      expect(optionalString(body('{"name": ""}'), 'name'), '');
    });

    test('any other JSON type → BodyFieldTypeError naming the field', () {
      for (final wrong in ['5', '5.5', 'true', '["a"]', '{"a": 1}']) {
        expect(
          () => optionalString(body('{"phoneNumber": $wrong}'), 'phoneNumber'),
          refuses('phoneNumber'),
          reason: 'phoneNumber: $wrong',
        );
      }
    });
  });

  group('optionalList', () {
    test('absent → null', () {
      expect(optionalList(body('{}'), 'tags'), isNull);
    });

    test('JSON null → null', () {
      expect(optionalList(body('{"tags": null}'), 'tags'), isNull);
    });

    test('a JSON list → that list, elements as sent (any type)', () {
      expect(optionalList(body('{"tags": ["vip", 3]}'), 'tags'), ['vip', 3]);
      expect(optionalList(body('{"tags": []}'), 'tags'), isEmpty);
    });

    test('any other JSON type → BodyFieldTypeError naming the field', () {
      for (final wrong in ['"vip"', '5', 'true', '{"a": 1}']) {
        expect(
          () => optionalList(body('{"serviceIds": $wrong}'), 'serviceIds'),
          refuses('serviceIds'),
          reason: 'serviceIds: $wrong',
        );
      }
    });
  });
}
