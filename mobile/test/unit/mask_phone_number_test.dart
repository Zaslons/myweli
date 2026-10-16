import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/helpers.dart';

/// `Helpers.maskPhoneNumber` — the number an OTP screen says it sent the code
/// to (docs/design/phone-leftovers.md §5).
///
/// It used to mask ONE shape: `+225` followed by the pre-2021 8 digits, a
/// length written in the helper itself (`cleaned.length == 12`), outside the
/// §18 seam. Every Ivorian number since 31 January 2021 has 10 digits, so a
/// number of today went through it whole and the screen printed it in clear —
/// as it did any other country's. The rule now knows no length: the calling
/// code, the first two and the last two national digits stay, every digit
/// between becomes a `•`.
void main() {
  group('maskPhoneNumber', () {
    test('a 10-digit Ivorian number: +225, 07 … 56, six dots between', () {
      expect(Helpers.maskPhoneNumber('+2250707123456'), '+225 07••••••56');
    });

    test('separators typed or stored do not change the result', () {
      expect(Helpers.maskPhoneNumber('+225 07 07 12 34 56'), '+225 07••••••56');
    });

    test('a number of another country keeps ITS calling code — +33, not '
        '+336', () {
      expect(Helpers.maskPhoneNumber('+33612345678'), '+33 61•••••78');
    });

    test(
      'a pre-2021 8-digit number stored before the change is masked too',
      () {
        expect(Helpers.maskPhoneNumber('+22507123456'), '+225 07••••56');
      },
    );

    test('no calling code: the digits are masked all the same', () {
      expect(Helpers.maskPhoneNumber('0707123456'), '07••••••56');
    });

    test('a short value has nothing to hide and comes back as it was', () {
      expect(Helpers.maskPhoneNumber(''), '');
      expect(Helpers.maskPhoneNumber('0712'), '0712');
      expect(
        Helpers.maskPhoneNumber('+2250712'),
        '+2250712',
        reason: 'four national digits: the two shown each side are all of it',
      );
    });
  });
}
