import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

/// Phone entry with an international country-code picker (defaults to Côte
/// d'Ivoire, +225 — users can pick any country). [onChanged] receives the full
/// **E.164** number (e.g. `+2250701020304`). Wraps `intl_phone_field`; inherits
/// the app's `InputDecorationTheme`. Shared widget — consumer + pro auth.
///
/// It takes an [errorText] like every other field and states its fault from a
/// [FieldErrors] map (SYSTEM.md §14 rule 1).
///
/// **`autovalidateMode` is `disabled` deliberately, and the reason is a
/// correction.** A7 shipped a comment here claiming the package's own
/// `FormField` check "only ever ran inside a `Form`", and used that claim to
/// triage a conflicting second validator as cosmetic. It is false, and the
/// review measured it: `IntlPhoneField` defaults to
/// `AutovalidateMode.onUserInteraction` (intl_phone_field-3.2.0:279) and runs
/// its validator whenever that is not `disabled` (:413) — `Form.maybeOf` is
/// null-safe, so **no `Form` ancestor is required**. So on all five call sites
/// the package was judging the number from the first keystroke, which is
/// exactly what §14 rule 2 forbids; and its message *replaced* the app's,
/// because `TextFormField` does `copyWith(errorText: field.errorText)` and
/// `InputDecoration.copyWith` keeps the non-null one. Two rules, disagreeing,
/// with the wrong one winning.
///
/// One rule now: [FieldErrors], on submit.
class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.onChanged,
    this.label = 'Numéro de téléphone',
    this.initialCountryCode = 'CI',
    this.initialValue,
    this.errorText,
    this.enabled = true,
  });

  /// The field-level fault — see [AppTextField.errorText], same contract.
  final String? errorText;

  /// Called with the complete E.164 number on every change.
  final ValueChanged<String> onChanged;
  final String label;
  final String initialCountryCode;

  /// Prefill with a full number (E.164, e.g. `+2250701020304`) — the picker
  /// derives the country from it.
  final String? initialValue;

  /// Greys the field out (the walk-in checkbox's contract) — same meaning as
  /// [AppTextField.enabled].
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IntlPhoneField(
      enabled: enabled,
      initialCountryCode: initialCountryCode,
      initialValue: initialValue,
      languageCode: 'fr',
      // Silences the package's own check — see the note above. The message is
      // kept for the day someone re-enables it deliberately.
      autovalidateMode: AutovalidateMode.disabled,
      invalidNumberMessage: 'Saisissez un numéro de téléphone valide.',
      decoration: InputDecoration(labelText: label, errorText: errorText),
      onChanged: (phone) => onChanged(phone.completeNumber),
    );
  }
}
