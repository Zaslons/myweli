import 'package:myweli_backend/src/validators.dart';
import 'package:test/test.dart';

void main() {
  group('isValidPhoneNumber', () {
    test('accepts +225 numbers, rejects malformed', () {
      expect(isValidPhoneNumber('+2250707010101'), isTrue);
      expect(isValidPhoneNumber('  +2250707010101  '), isTrue);
      expect(isValidPhoneNumber('0707010101'), isFalse);
      expect(isValidPhoneNumber('+0123456789'), isFalse); // leading zero
      expect(isValidPhoneNumber('+22 abc'), isFalse);
    });

    // docs/design/phone-national-length.md §2.1: a CI number has exactly 10
    // digits after +225 (ARTCI, 2021), the leading 0 included.
    test('+225: exactly 10 digits after the calling code', () {
      expect(isValidPhoneNumber('+2250707123456'), isTrue);
      expect(isValidPhoneNumber('+2252722123456'), isTrue); // fixed line
      // E.164 in shape — the generic rule alone accepted every one of these.
      expect(isValidPhoneNumber('+2250700000'), isFalse); // 7
      expect(isValidPhoneNumber('+225070712345'), isFalse); // 9
      expect(isValidPhoneNumber('+22507071234567'), isFalse); // 11
      expect(isValidPhoneNumber('+225070000000011'), isFalse); // 12
      expect(isValidPhoneNumber('+2250700'), isFalse); // 4
      expect(isValidPhoneNumber('+22507000000'), isFalse); // 8 (pre-2021)
    });

    test('another calling code keeps the generic E.164 rule', () {
      expect(isValidPhoneNumber('+33612345678'), isTrue);
      expect(isValidPhoneNumber('+2410700000001'), isTrue); // Gabon
      expect(isValidPhoneNumber('+3361234'), isFalse); // 7 digits < 8
      expect(isValidPhoneNumber('+3361234567890123'), isFalse); // 16 > 15
    });

    test('canonical form only: separators are the client\'s job', () {
      expect(isValidPhoneNumber('+225 07 07 12 34 56'), isFalse);
      expect(isValidPhoneNumber('+225-07-07-12-34-56'), isFalse);
      expect(isValidPhoneNumber('+225 (07) 07123456'), isFalse);
    });

    test('empty, or a calling code alone, is not a number', () {
      expect(isValidPhoneNumber(''), isFalse);
      expect(isValidPhoneNumber('   '), isFalse);
      expect(isValidPhoneNumber('+225'), isFalse);
      expect(isValidPhoneNumber('+'), isFalse);
    });
  });

  test('isValidOtpCode accepts 4–8 digits only', () {
    expect(isValidOtpCode('123456'), isTrue);
    expect(isValidOtpCode('1234'), isTrue);
    expect(isValidOtpCode('12'), isFalse);
    expect(isValidOtpCode('123456789'), isFalse);
    expect(isValidOtpCode('12ab'), isFalse);
  });
}
