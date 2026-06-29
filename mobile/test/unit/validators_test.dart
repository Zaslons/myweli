import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/validators.dart';

void main() {
  group('Validators.phoneNumber (E.164)', () {
    test('accepts a current Côte d\'Ivoire 10-digit number', () {
      // The old validator wrongly rejected this (it required 8 digits).
      expect(Validators.phoneNumber('+2250712345678'), isNull);
    });

    test('accepts a foreign number (e.g. France)', () {
      expect(Validators.phoneNumber('+33612345678'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.phoneNumber(''), isNotNull);
    });

    test('rejects a number without the + country code', () {
      expect(Validators.phoneNumber('0712345678'), isNotNull);
    });

    test('rejects a too-short number', () {
      expect(Validators.phoneNumber('+12345'), isNotNull);
    });
  });
}
