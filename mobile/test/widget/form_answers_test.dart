import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/forms/field_errors.dart';
import 'package:myweli/core/utils/validators.dart';

/// A7 — the small contracts on `FieldErrors` that the per-funnel tests rely on.
///
/// **This file used to be bigger, and the bigger version was theatre.** A7's
/// fix commit added a `FieldErrors.unvalidatedKeys` getter and four assertions
/// here, and claimed it was "the invariant that makes the whole class
/// impossible". The second review measured it: five references in the entire
/// repo — the getter plus these four assertions — and not one of them pumped a
/// screen. It proved the CLASS could compute a set difference; the defect class
/// is a **screen-level omission**, so it could not see a single one of the four
/// bugs it was written for. It was also unreadable from any screen (every
/// `_errors` is private state) and its invariant was false on two correct flows.
///
/// A7⑥ deleted `AppTextField.validator` on the principle that a zero-caller API
/// must go. The getter got the same treatment, and the real gate is behavioural,
/// per funnel — see `login_screen_test.dart` and the five other funnel files §20 names.
void main() {
  /// A fault that is computed but has
  /// nowhere to render. `pro_register` blocked its submit on a missing
  /// « Type d'entreprise » and rendered the message nowhere — a press that does
  /// literally nothing, which is worse than the disabled button rule 5 removed.
  group('a rule that can fail must have somewhere to say so', () {
    test('every declared key is reachable through the subscript operator', () {
      final errors = FieldErrors({
        'businessType': Validators.requiredField('le type d’entreprise'),
      });
      expect(errors.validate({'businessType': ''}), isFalse);
      expect(
        errors['businessType'],
        isNotNull,
        reason:
            'the message exists — the screen must bind it to an '
            'errorText or an InlineFeedback, which is what the per-funnel '
            'widget tests assert',
      );
    });
  });

  /// §14 rule 2's other half, which the review found missing on six screens:
  /// a SELECTION fault (no field to sit under) was set on submit and then never
  /// cleared, so it sat on screen after the user had visibly fixed it.
  group('rule 2 applies to selection faults too', () {
    test('re-validating a selection clears it without a second submit', () {
      final errors = FieldErrors({'role': Validators.requiredField('un rôle')});
      expect(errors.validate({'role': ''}), isFalse);
      expect(errors['role'], isNotNull);

      // The user picks a role. Nothing is submitted yet.
      errors.revalidate('role', 'manager');
      expect(
        errors['role'],
        isNull,
        reason:
            'the message must go the moment the user fixes the thing it '
            'is about — a stale fault under a now-valid selection reads as '
            'a broken form',
      );
    });
  });
}
