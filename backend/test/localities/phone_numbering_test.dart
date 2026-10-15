import 'package:myweli_backend/src/localities/localities_repository.dart';
import 'package:myweli_backend/src/localities/phone_numbering.dart';
import 'package:test/test.dart';

/// The numbering table — the server's only home of « how many digits follow
/// a calling code » (multi-pays.md §9). Design:
/// docs/design/phone-national-length.md §2.2 / §8.
void main() {
  group('nationalLengthRule', () {
    test('+225 → 10 digits, keyed by the calling code without +', () {
      final rule = nationalLengthRule('+2250707123456');
      expect(rule, isNotNull);
      expect(rule!.callingCode, '225');
      expect(rule.length, 10);
      // The rule is the code's, whatever follows it (the caller counts).
      expect(nationalLengthRule('+2250700000')?.length, 10);
      expect(nationalLengthRule('+225')?.callingCode, '225');
    });

    test('a calling code with no row → null (the generic E.164 rule)', () {
      expect(nationalLengthRule('+33612345678'), isNull);
      // +22 is not +225: a prefix of the code is not the code.
      expect(nationalLengthRule('+22507'), isNotNull);
      expect(nationalLengthRule('+2241234567'), isNull);
    });

    test('not `+` then digits → null (no rule applies to a non-E.164)', () {
      expect(nationalLengthRule('2250707123456'), isNull);
      expect(nationalLengthRule(''), isNull);
    });
  });

  test('every seeded country has its row — a market cannot open without '
      'its numbering length', () {
    // Read from the seed itself (the Postgres seed runs from this same
    // list), so a new country fails here until its row is added.
    expect(seedCountries, isNotEmpty);
    for (final country in seedCountries) {
      expect(country.phonePrefix, startsWith('+'), reason: country.code);
      final code = country.phonePrefix.substring(1);
      expect(
        nationalNumberLengths,
        contains(code),
        reason:
            '${country.code} (${country.phonePrefix}) has no row in '
            'nationalNumberLengths',
      );
      // And the lookup resolves the prefix to that row.
      expect(
        nationalLengthRule(country.phonePrefix)?.callingCode,
        code,
        reason: country.code,
      );
    }
  });
}
