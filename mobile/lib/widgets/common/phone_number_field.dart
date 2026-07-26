import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

/// Phone entry with an international country-code picker (defaults to Côte
/// d'Ivoire, +225 — users can pick any country). [onChanged] receives the full
/// **E.164** number (e.g. `+2250701020304`). Wraps `intl_phone_field`; inherits
/// the app's `InputDecorationTheme`. Shared widget — consumer + pro auth.
///
/// A7: it takes an [errorText] like every other field, because its own
/// `FormField` validation only ever ran inside a `Form` — and **two of its five
/// call sites had none** (`login_screen:331`, `client_list_screen:373`), so the
/// package's per-country length check could never fire there. The field now
/// states its fault the same way `AppTextField` does, from a `FieldErrors` map,
/// whether or not a `Form` is anywhere near it (SYSTEM.md §14 rule 1).
class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.onChanged,
    this.label = 'Numéro de téléphone',
    this.initialCountryCode = 'CI',
    this.initialValue,
    this.errorText,
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

  @override
  Widget build(BuildContext context) {
    return IntlPhoneField(
      initialCountryCode: initialCountryCode,
      initialValue: initialValue,
      languageCode: 'fr',
      invalidNumberMessage: 'Saisissez un numéro de téléphone valide.',
      decoration: InputDecoration(labelText: label, errorText: errorText),
      onChanged: (phone) => onChanged(phone.completeNumber),
    );
  }
}
