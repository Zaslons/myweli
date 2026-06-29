import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

/// Phone entry with an international country-code picker (defaults to Côte
/// d'Ivoire, +225 — users can pick any country). [onChanged] receives the full
/// **E.164** number (e.g. `+2250701020304`). It's a `FormField`, so the enclosing
/// `Form`'s `validate()` checks the per-country length and shows
/// [invalidNumberMessage] when wrong. Wraps `intl_phone_field`; inherits the
/// app's `InputDecorationTheme`. Shared widget — used by the consumer + pro auth.
class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.onChanged,
    this.label = 'Numéro de téléphone',
    this.initialCountryCode = 'CI',
  });

  /// Called with the complete E.164 number on every change.
  final ValueChanged<String> onChanged;
  final String label;
  final String initialCountryCode;

  @override
  Widget build(BuildContext context) {
    return IntlPhoneField(
      initialCountryCode: initialCountryCode,
      languageCode: 'fr',
      invalidNumberMessage: 'Numéro de téléphone invalide',
      decoration: InputDecoration(labelText: label),
      onChanged: (phone) => onChanged(phone.completeNumber),
    );
  }
}
