import 'package:myweli_backend/src/validators.dart';
import 'package:test/test.dart';

void main() {
  test('isValidE164 accepts +225 numbers, rejects malformed', () {
    expect(isValidE164('+2250707010101'), isTrue);
    expect(isValidE164('  +2250707010101  '), isTrue);
    expect(isValidE164('0707010101'), isFalse);
    expect(isValidE164('+0123456789'), isFalse); // leading zero
    expect(isValidE164('+22 abc'), isFalse);
  });

  test('isValidOtpCode accepts 4–8 digits only', () {
    expect(isValidOtpCode('123456'), isTrue);
    expect(isValidOtpCode('1234'), isTrue);
    expect(isValidOtpCode('12'), isFalse);
    expect(isValidOtpCode('123456789'), isFalse);
    expect(isValidOtpCode('12ab'), isFalse);
  });
}
