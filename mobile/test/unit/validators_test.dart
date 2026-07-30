import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/validators.dart';

/// A7 extended this file to every rule (SYSTEM.md §14, §21 row 19). Before it,
/// only `phoneNumber` was covered — and it was the static with **zero callers**,
/// while the rules the screens actually ran carried divergent inline copies.
void main() {
  group('Validators.phoneNumber (E.164)', () {
    test('accepts a current Côte d’Ivoire 10-digit number', () {
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
      expect(Validators.optionalEmail(''), isNull,
          reason: 'the consumer profile may leave it blank');
      expect(Validators.optionalEmail('pas-un-email'), isNotNull,
          reason: 'blank is allowed; wrong is not');
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

  group('Validators.localPhoneNumber — what the Mobile Money field takes', () {
    test('ten digits, however they are spaced', () {
      // deposit_settings_screen.dart:321 had NO validation at all — the field
      // that decides where a salon's deposits land.
      expect(Validators.localPhoneNumber('07 07 12 34 56'), isNull);
      expect(Validators.localPhoneNumber('0707123456'), isNull);
    });

    test('nine or eleven digits fail', () {
      expect(Validators.localPhoneNumber('070712345'), isNotNull,
          reason: 'CI moved to 10 digits in 2021');
      expect(Validators.localPhoneNumber('07071234567'), isNotNull);
      expect(
          Validators.localPhoneNumber(''), 'Saisissez un numéro de téléphone.');
    });
  });

  group('the factories that replace the inline copies', () {
    test('requiredField names itself in the message (§14 rule 4)', () {
      final rule = Validators.requiredField('le nom du salon');
      expect(rule('  '), 'Indiquez le nom du salon.',
          reason: 'say what to do, and which field to do it in');
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
        Validators.name('A'), 'Le nom doit comporter au moins 2 caractères.');
    expect(Validators.name('Awa'), isNull);
  });
}
