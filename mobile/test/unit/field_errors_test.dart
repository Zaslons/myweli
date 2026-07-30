import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/forms/field_errors.dart';
import 'package:myweli/core/utils/validators.dart';

/// A7 — §14 rules 1–4 as a controller (SYSTEM.md §21 row 19).
///
/// The web shipped this design in B4 and its adversarial review found the one
/// bug in it: `validate()` REPLACED the error map, so a step-2 submit wiped a
/// still-unfixed step-1 error **and the submit then fired with the empty
/// value**. That reproduction is the first test here — it is worth more than
/// the class it guards.
void main() {
  FieldErrors build() => FieldErrors({
    'email': Validators.email,
    'code': Validators.otp,
    'name': Validators.requiredField('votre nom'),
  });

  group('validate — submit', () {
    test(
      'validates ONLY the keys passed (a step never fails what it cannot see)',
      () {
        final errors = build();
        expect(errors.validate({'email': 'awa@exemple.ci'}), isTrue);
        expect(
          errors['code'],
          isNull,
          reason: 'the code field was not submitted — it must not be judged',
        );
        expect(errors.isEmpty, isTrue);
      },
    );

    test('MERGES — a later submit does not wipe an earlier unfixed error', () {
      final errors = build();

      // Step 1 fails and stays failed.
      expect(errors.validate({'name': ''}), isFalse);
      expect(errors['name'], 'Indiquez votre nom.');

      // Step 2 submits a DIFFERENT field, successfully.
      expect(errors.validate({'email': 'awa@exemple.ci'}), isTrue);

      // The web's replacing version returned true here with an empty map, and
      // the caller submitted a form whose name was still blank.
      expect(
        errors['name'],
        'Indiquez votre nom.',
        reason:
            'an error persists until it is FIXED (§14 rule 1) — not '
            'until some other field is submitted',
      );
      expect(errors.isNotEmpty, isTrue);
    });

    test('clears a key that now passes, and only that key', () {
      final errors = build();
      errors.validate({'name': '', 'email': 'nope'});
      expect(errors.isNotEmpty, isTrue);

      errors.validate({'name': 'Awa'});
      expect(errors['name'], isNull);
      expect(errors['email'], 'Saisissez une adresse e-mail valide.');
    });
  });

  group('revalidate — rule 2', () {
    test('is SILENT until the field has already errored', () {
      final errors = build();
      // The user is mid-type. This is the form that yells at `s@`, and it must
      // not exist.
      errors.revalidate('email', 's@');
      expect(
        errors['email'],
        isNull,
        reason: 'never validate a field the user has not finished typing',
      );
    });

    test('goes live once errored, and clears the moment it passes', () {
      final errors = build();
      errors.validate({'email': 's@'});
      expect(errors['email'], 'Saisissez une adresse e-mail valide.');

      errors.revalidate('email', 's@exemple');
      expect(
        errors['email'],
        'Saisissez une adresse e-mail valide.',
        reason: 'still wrong — the message stays',
      );

      errors.revalidate('email', 's@exemple.ci');
      expect(errors['email'], isNull, reason: 'fixed — it disappears');
    });
  });

  group('set — server faults (rule 1 applies to those too)', () {
    test('pins a server message under its field, and rule 2 clears it', () {
      final errors = build();
      // « Code incorrect » belongs under the code field, not in a bar that
      // vanishes on a timer.
      errors.set('code', 'Code incorrect ou expiré.');
      expect(errors['code'], 'Code incorrect ou expiré.');

      errors.revalidate('code', '123456');
      expect(
        errors['code'],
        isNull,
        reason: 'a changed value that passes the client check clears it',
      );
    });

    test('null clears', () {
      final errors = build()..set('code', 'Code incorrect ou expiré.');
      errors.set('code', null);
      expect(errors.isEmpty, isTrue);
    });
  });

  test('firstErroredKey follows DECLARATION order, not hash order', () {
    final errors = build();
    errors.validate({'code': '', 'name': '', 'email': ''});
    expect(
      errors.firstErroredKey,
      'email',
      reason:
          'the focus move must land on the first field in the form’s '
          'reading order (§13.5)',
    );
  });

  test('clear wipes everything — a step change', () {
    final errors = build()..validate({'email': '', 'name': ''});
    expect(errors.isNotEmpty, isTrue);
    errors.clear();
    expect(errors.isEmpty, isTrue);
    expect(errors.firstErroredKey, isNull);
  });
}
