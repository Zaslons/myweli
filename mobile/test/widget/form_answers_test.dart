import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/forms/field_errors.dart';
import 'package:myweli/core/utils/validators.dart';

/// A7 — **the gate §20 claimed before it existed.**
///
/// The slice's own adversarial review found six high-severity defects, and four
/// of them share one shape: a screen declares a rule in its `FieldErrors` map,
/// binds `errorText` to it, wires `revalidate` — and never calls `validate` on
/// submit. The rule never runs, the `errorText` is structurally unreachable, and
/// because A7 also removed the disabled-button gate under §14 rule 5, the press
/// now *succeeds* where it used to be blocked.
///
/// That is precisely the pathology row 19 exists to kill (`invite_member_sheet`
/// shipped it for months), re-created by a mechanical sweep. The per-funnel
/// widget tests the docs promised would have caught it; they did not exist.
///
/// This file is the **structural** half, and it is deliberately cheap: it holds
/// the invariant that makes the pathology impossible, without needing a live
/// router, provider stack and service seam per funnel. The behavioural half —
/// submit-invalid renders under the field and raises no `SnackBar` — lives with
/// each funnel's own test (see `invite_member_sheet_test.dart`).
void main() {
  /// Every key a screen DECLARES must be a key it VALIDATES. A declared-but-
  /// never-validated rule is a lie: the field wears an `errorText` that cannot
  /// be populated, and after rule 5 nothing else is holding the door.
  ///
  /// Expressed as a contract on `FieldErrors` itself, so it holds for every
  /// screen without needing to pump one: if a caller only ever submits a subset
  /// of its declared keys, the keys it skips are silently unenforced.
  group('a declared rule is an enforced rule', () {
    test('validate() reports which declared keys it has never judged', () {
      final errors = FieldErrors({
        'email': Validators.email,
        'code': Validators.otp,
        'phone': Validators.phoneNumber,
      });

      // The bug shape: two steps each submit their own field, and a third rule
      // rides along declared but unreachable.
      errors.validate({'email': 'awa@exemple.ci'});
      errors.validate({'code': '123456'});

      expect(errors.unvalidatedKeys, {'phone'},
          reason: 'login_screen declared a phone rule, bound errorText to it, '
              'and never submitted it — so an empty phone sailed through the '
              'MANDATORY contact step and the message could never render');
    });

    test('a fully-submitted form leaves nothing unenforced', () {
      final errors = FieldErrors({
        'name': Validators.name,
        'phone': Validators.phoneNumber,
      });
      errors.validate({'name': 'Awa', 'phone': '+2250707123456'});
      expect(errors.unvalidatedKeys, isEmpty);
    });

    test('a subset submit is legal — it just has to happen eventually', () {
      final errors = FieldErrors({
        'email': Validators.email,
        'code': Validators.otp,
      });
      errors.validate({'email': 'awa@exemple.ci'});
      expect(errors.unvalidatedKeys, {'code'},
          reason: 'mid-funnel this is expected; the gate is that the LAST step '
              'leaves it empty');
      errors.validate({'code': '123456'});
      expect(errors.unvalidatedKeys, isEmpty);
    });
  });

  /// The second half of the same defect: a fault that is computed but has
  /// nowhere to render. `pro_register` blocked its submit on a missing
  /// « Type d'entreprise » and rendered the message nowhere — a press that does
  /// literally nothing, which is worse than the disabled button rule 5 removed.
  group('a rule that can fail must have somewhere to say so', () {
    test('every declared key is reachable through the subscript operator', () {
      final errors = FieldErrors({
        'businessType': Validators.requiredField("le type d'entreprise"),
      });
      expect(errors.validate({'businessType': ''}), isFalse);
      expect(errors['businessType'], isNotNull,
          reason: 'the message exists — the screen must bind it to an '
              'errorText or an InlineFeedback, which is what the per-funnel '
              'widget tests assert');
    });
  });

  /// §14 rule 2's other half, which the review found missing on six screens:
  /// a SELECTION fault (no field to sit under) was set on submit and then never
  /// cleared, so it sat on screen after the user had visibly fixed it.
  group('rule 2 applies to selection faults too', () {
    test('re-validating a selection clears it without a second submit', () {
      final errors = FieldErrors({
        'role': Validators.requiredField('un rôle'),
      });
      expect(errors.validate({'role': ''}), isFalse);
      expect(errors['role'], isNotNull);

      // The user picks a role. Nothing is submitted yet.
      errors.revalidate('role', 'manager');
      expect(errors['role'], isNull,
          reason: 'the message must go the moment the user fixes the thing it '
              'is about — a stale fault under a now-valid selection reads as '
              'a broken form');
    });
  });
}
