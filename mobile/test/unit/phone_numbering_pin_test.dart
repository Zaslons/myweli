import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/phone_numbering.dart';

/// The national-length seam (docs/design/phone-national-length.md §2.2, §8;
/// SYSTEM.md §18). « +225 → 10 chiffres » is a market fact: it lives in
/// `core/utils/phone_numbering.dart` and nowhere else in the app, and the
/// server holds the same table under the same key. Two pins hold that:
///
/// 1. the app's table equals the backend's, read from disk — a market opened
///    on one side only would let the app accept what the server refuses, or
///    refuse what it accepts;
/// 2. no other file under `lib/` writes the CURRENT length (10) as a rule —
///    `{10}`, `.length ==/!= 10`, « 10 chiffres » or a `'225': 10` row — nor
///    ANY length compared on a line that names the calling code
///    (`startsWith('+225') && cleaned.length == 12`).
///    `Validators.localPhoneNumber` was the first shape (outside every seam, no
///    caller); the OTP screens' pre-2021 8-digit mask was the second, until
///    phone-leftovers.md §5 made it generic. What this grep does NOT see:
///    another length on a line without `225`, or a quantifier other than
///    `{10}` (`\d{8,10}`).
void main() {
  /// Same stripper as `salon_time_pin_test.dart`: prose about a rule is not
  /// the rule, and a pin that reddens on its own documentation gets routed
  /// around.
  String stripDartComments(String src) => src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp('//[^\n]*'), '');

  group('PhoneNumbering — the seam itself', () {
    test(
      'normalize strips separators and reads a lone calling code as empty',
      () {
        expect(
          PhoneNumbering.normalize(' +225 07-07.12 (34) 56 '),
          '+2250707123456',
        );
        expect(PhoneNumbering.normalize(''), '');
        expect(PhoneNumbering.normalize('   '), '');
        expect(
          PhoneNumbering.normalize('+225'),
          '',
          reason: 'the calling code alone is what a cleared field holds',
        );
        expect(
          PhoneNumbering.normalize('+33612345678'),
          '+33612345678',
          reason: 'a number with no table row passes through, stripped only',
        );
      },
    );

    test('nationalLengthFor finds the row by calling code, or says none', () {
      expect(PhoneNumbering.nationalLengthFor('+2250700000'), (
        callingCode: '225',
        length: 10,
      ));
      expect(PhoneNumbering.nationalLengthFor('+33612345678'), isNull);
      expect(
        PhoneNumbering.nationalLengthFor('2250700000000'),
        isNull,
        reason: 'no `+`, no calling code to read',
      );
    });
  });

  group('the table is the backend\'s table', () {
    /// `nationalNumberLengths` as the server declares it — tests run with the
    /// cwd at `mobile/`.
    Map<String, int> backendTable() {
      final file = File('../backend/lib/src/localities/phone_numbering.dart');
      final src = stripDartComments(file.readAsStringSync());
      final literal = RegExp(
        r'nationalNumberLengths\s*=\s*\{([^}]*)\}',
      ).firstMatch(src);
      expect(
        literal,
        isNotNull,
        reason:
            'the backend seam no longer declares `nationalNumberLengths = '
            '{…}` — re-point this pin, do not delete it',
      );
      return {
        for (final m in RegExp(
          r"""['"](\d+)['"]\s*:\s*(\d+)""",
        ).allMatches(literal!.group(1)!))
          m.group(1)!: int.parse(m.group(2)!),
      };
    }

    test('the parser reads a real row — a pin that parses nothing passes '
        'everything', () {
      expect(backendTable(), isNotEmpty);
    });

    test('kNationalNumberLength == backend nationalNumberLengths', () {
      expect(
        kNationalNumberLength,
        backendTable(),
        reason:
            'a market opened on one side only: add the row to BOTH '
            'mobile/lib/core/utils/phone_numbering.dart and '
            'backend/lib/src/localities/phone_numbering.dart',
      );
    });
  });

  group('no phone-length rule outside the seams', () {
    /// The seams that may know a national length: the table itself, and the
    /// display formatter (`formatPhoneNumber` groups +225 numbers in pairs, the
    /// legacy 8-digit form included, for numbers already stored).
    const seams = [
      'core/utils/phone_numbering.dart',
      'core/utils/formatters.dart',
    ];

    /// A file "talks about phones" when its code (comments stripped) names the
    /// calling code or a phone.
    final phoneContext = RegExp(
      r'225|phone|t[ée]l[ée]phone|num[ée]ro',
      caseSensitive: false,
    );

    /// The ways a digit count gets hard-coded: a `{10}` quantifier, a length
    /// compared to 10, « 10 chiffres » in a message, a `'225': 10` row — or a
    /// length compared to ANY number on the same line as the calling code,
    /// which is how `maskPhoneNumber` wrote the pre-2021 one.
    final lengthRule = RegExp(
      r"""\{10\}|\.length\s*[!=]=\s*10\b|\b10\s+chiffres|['"]\+?225['"]\s*:\s*10\b"""
      r'|225[^\n;]*\.length\s*(?:[!=]=|[<>]=?)\s*\d+'
      r'|\.length\s*(?:[!=]=|[<>]=?)\s*\d+[^\n;]*225',
    );

    bool holdsRule(String src) {
      final code = stripDartComments(src);
      return phoneContext.hasMatch(code) && lengthRule.hasMatch(code);
    }

    List<String> offenders(Map<String, String> files) => [
      for (final entry in files.entries)
        if (!seams.any(entry.key.endsWith) && holdsRule(entry.value)) entry.key,
    ];

    test('the matcher sees the rule it exists to catch, and not its prose', () {
      // `Validators.localPhoneNumber`'s body, as it stood before this slice —
      // the case this pin was written for. A pin born green has to be shown
      // failing once (SYSTEM.md §21 row 67).
      const legacy = '''
static String? localPhoneNumber(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'[^\\d]'), '');
  if (digits.isEmpty) return 'Saisissez un numéro de téléphone.';
  return digits.length == 10 ? null : 'Le numéro doit comporter 10 chiffres.';
}
''';
      const prose = '''
// A +225 number has 10 digits — digits.length == 10 lives in the seam.
void f() {}
''';
      expect(offenders({'lib/core/utils/validators.dart': legacy}), [
        'lib/core/utils/validators.dart',
      ]);
      expect(
        offenders({'lib/core/utils/phone_numbering.dart': legacy}),
        isEmpty,
        reason: 'the seam may hold it',
      );
      expect(
        offenders({'lib/screens/x.dart': prose}),
        isEmpty,
        reason: 'a comment is not code',
      );
    });

    test('the matcher sees a length of ANY value beside the calling code — '
        'the pre-2021 mask', () {
      // `Helpers.maskPhoneNumber` as it stood before phone-leftovers.md §5: a
      // 12-character `+225` number (8 national digits), written in the helper.
      // The `{10}`-and-`10 chiffres` half of this pin could not see it.
      const legacyMask = '''
static String maskPhoneNumber(String phone) {
  final cleaned = phone.replaceAll(RegExp(r'[\\s\\-\\(\\)]'), '');
  if (cleaned.startsWith('+225') && cleaned.length == 12) {
    return '+225 XX XX \${cleaned.substring(10)}';
  }
  return phone;
}
''';
      const reversed = '''
bool f(String p) => p.length != 13 && p.startsWith('+225');
''';
      const unrelated = '''
bool otp(String code, String phone) => code.length == 6 && phone.isNotEmpty;
''';
      expect(offenders({'lib/core/utils/helpers.dart': legacyMask}), [
        'lib/core/utils/helpers.dart',
      ]);
      expect(offenders({'lib/x.dart': reversed}), ['lib/x.dart']);
      expect(
        offenders({'lib/x.dart': unrelated}),
        isEmpty,
        reason: 'a length on a line that does not name the calling code',
      );
    });

    test('no file under lib/ counts phone digits itself', () {
      final files = {
        for (final entity in Directory('lib').listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.dart'))
            entity.path: entity.readAsStringSync(),
      };
      expect(
        files.length,
        greaterThan(100),
        reason: 'the sweep read the app, not an empty directory',
      );
      expect(
        offenders(files),
        isEmpty,
        reason:
            'a national length is a market fact (SYSTEM.md §18): read it '
            'from PhoneNumbering (core/utils/phone_numbering.dart) — '
            'Validators.phoneNumber already does',
      );
    });
  });
}
