import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/validators.dart';

/// A7 extended this file to every rule (SYSTEM.md §14, §21 row 19). Before it,
/// only `phoneNumber` was covered — and it was the static with **zero callers**,
/// while the rules the screens actually ran carried divergent inline copies.
void main() {
  /// docs/design/phone-national-length.md §2.1 — one rule, three surfaces.
  /// Seen on the simulator on 2026-10-15: the sign-in phone step saved
  /// `+2250700000`, 7 digits after +225, because the only check was the
  /// generic E.164 one (`+` then 8–15 digits).
  group('Validators.phoneNumber — a +225 number has exactly 10 digits', () {
    const tenDigits = 'Le numéro doit comporter 10 chiffres après +225.';

    test('accepts a current Côte d’Ivoire 10-digit number', () {
      // The old validator wrongly rejected this (it required 8 digits).
      expect(Validators.phoneNumber('+2250712345678'), isNull);
    });

    test('7, 11 and 4 national digits each say what to do', () {
      // 7 — the number the simulator saved.
      expect(Validators.phoneNumber('+2250700000'), tenDigits);
      // 11 — the generic rule had no CI upper bound either.
      expect(Validators.phoneNumber('+225070000000011'), tenDigits);
      // 4 — short enough that the generic rule would have said « valide »:
      // the +225 rule runs first, so the message is the precise one.
      expect(Validators.phoneNumber('+2250700'), tenDigits);
    });

    test('separators are stripped before counting — what is checked is what '
        'is sent', () {
      expect(Validators.phoneNumber('+225 07 07 12 34 56'), isNull);
      expect(Validators.phoneNumber('+225-07.07(12)34 56'), isNull);
    });

    test('empty, or the calling code alone, is EMPTY — not « invalide »', () {
      // A cleared PhoneNumberField used to emit `+225`, which read as
      // « Saisissez un numéro de téléphone valide. » on a field holding nothing.
      expect(Validators.phoneNumber(''), 'Saisissez un numéro de téléphone.');
      expect(
        Validators.phoneNumber('+225'),
        'Saisissez un numéro de téléphone.',
      );
      expect(
        Validators.phoneNumber(' + 225 '),
        'Saisissez un numéro de téléphone.',
      );
    });

    test('any other calling code keeps the generic E.164 rule', () {
      expect(Validators.phoneNumber('+33612345678'), isNull);
      expect(
        Validators.phoneNumber('+12345'),
        'Saisissez un numéro de téléphone valide.',
      );
    });

    test('rejects a number without the + country code', () {
      expect(
        Validators.phoneNumber('0712345678'),
        'Saisissez un numéro de téléphone valide.',
      );
    });
  });

  /// The optional twin — WhatsApp, the consumer profile, a Mobile Money number
  /// on a salon that takes no deposit. Three screens hand-rolled it as
  /// `value.trim().isEmpty ? null : phoneNumber(value)`, and a cleared field's
  /// `+225` was not "empty" to that test, so an optional phone could not be
  /// cleared.
  group('Validators.optionalPhoneNumber — empty passes, typed is judged', () {
    test('empty and the lone calling code pass', () {
      expect(Validators.optionalPhoneNumber(''), isNull);
      expect(Validators.optionalPhoneNumber(null), isNull);
      expect(Validators.optionalPhoneNumber('+225'), isNull);
    });

    test('anything typed meets the same rule as the required field', () {
      expect(
        Validators.optionalPhoneNumber('+2250700000'),
        'Le numéro doit comporter 10 chiffres après +225.',
      );
      expect(Validators.optionalPhoneNumber('+2250707123456'), isNull);
      expect(
        Validators.optionalPhoneNumber('abc'),
        'Saisissez un numéro de téléphone valide.',
      );
    });
  });

  group('e-mail — there is ONE definition', () {
    test('accepts a real address, rejects what the loose copy allowed', () {
      expect(Validators.email('awa@exemple.ci'), isNull);
      // The four funnel copies used `^[^@\s]+@[^@\s]+\.[^@\s]+$`, which
      // accepts a single-character TLD and a doubled @. The strict rule — the
      // one that survives — does not.
      expect(Validators.email('awa@exemple.c'), isNotNull);
      expect(Validators.email('awa@@exemple.ci'), isNotNull);
      expect(Validators.email('s@'), isNotNull);
    });

    test('required vs optional are different rules, deliberately', () {
      expect(Validators.email(''), 'Saisissez une adresse e-mail.');
      expect(
        Validators.optionalEmail(''),
        isNull,
        reason: 'the consumer profile may leave it blank',
      );
      expect(
        Validators.optionalEmail('pas-un-email'),
        isNotNull,
        reason: 'blank is allowed; wrong is not',
      );
    });

    test('trims — a pasted address with a trailing space is valid', () {
      expect(Validators.email('  awa@exemple.ci '), isNull);
    });
  });

  group('Validators.otp — six digits, the number everything else said', () {
    test('exactly six digits passes', () {
      expect(Validators.otp('123456'), isNull);
    });

    test('FOUR digits fails — the bug three live screens shipped', () {
      // login_screen:282, pro_login:352 and pro_register:354 gated on
      // `length < 4`, on a field labelled « Code à 6 chiffres » with
      // maxLength: 6. A four-digit code walked straight through.
      expect(Validators.otp('1234'), 'Le code doit comporter 6 chiffres.');
    });

    test('non-digits and overlong fail; empty asks for the code', () {
      expect(Validators.otp('12345a'), 'Le code doit comporter 6 chiffres.');
      expect(Validators.otp('1234567'), isNotNull);
      expect(Validators.otp(''), 'Saisissez le code reçu.');
    });

    test('the message is the one the golden baseline photographs', () {
      // components_inputs_golden_test.dart:82 — the spec image for row 19.
      expect(Validators.otp('1'), 'Le code doit comporter 6 chiffres.');
    });
  });

  group('the factories that replace the inline copies', () {
    test('requiredField names itself in the message (§14 rule 4)', () {
      final rule = Validators.requiredField('le nom du salon');
      expect(
        rule('  '),
        'Indiquez le nom du salon.',
        reason: 'say what to do, and which field to do it in',
      );
      expect(rule('Beauté Divine'), isNull);
    });

    test('amount — FCFA, digits, strictly positive', () {
      final rule = Validators.amount('un prix');
      expect(rule(''), 'Indiquez un prix.');
      expect(rule('0'), 'Indiquez un prix supérieur à 0.');
      expect(rule('15000'), isNull);
      expect(rule('15 000'), isNull, reason: 'spaces are how FCFA is written');
    });

    test('minutes — whole, strictly positive', () {
      final rule = Validators.minutes('une durée');
      expect(rule('0'), isNotNull);
      expect(rule('45'), isNull);
      expect(rule('45,5'), isNotNull, reason: 'minutes are whole');
    });
  });

  test('Validators.name — required, then at least 2 characters', () {
    expect(Validators.name(''), 'Saisissez un nom.');
    expect(
      Validators.name('A'),
      'Le nom doit comporter au moins 2 caractères.',
    );
    expect(Validators.name('Awa'), isNull);
  });
}
