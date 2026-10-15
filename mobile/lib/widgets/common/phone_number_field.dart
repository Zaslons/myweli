import 'package:flutter/material.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../../core/utils/phone_numbering.dart';

/// Phone entry with an international country-code picker (defaults to Côte
/// d'Ivoire, +225 — users can pick any country). Wraps `intl_phone_field`;
/// inherits the app's `InputDecorationTheme`. Shared widget — every phone the
/// two apps take (SYSTEM.md §11.1).
///
/// [onChanged] receives the number **normalized** (phone-national-length.md
/// §2.3): `''` while no national digit is typed, else `+<calling code><digits>`
/// without a separator (e.g. `+2250701020304`) — what the screen checks is what
/// it sends. Picking another country re-emits the number under it. It used to
/// emit `+225` for a cleared field (so a required field said « valide » and an
/// optional one could not be cleared), keep the old country's number after a
/// switch until the next keystroke, and pass separators to a server that
/// refuses them.
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
/// One rule now: [FieldErrors], on submit — `Validators.phoneNumber`.
class PhoneNumberField extends StatefulWidget {
  const PhoneNumberField({
    super.key,
    required this.onChanged,
    this.label = 'Numéro de téléphone',
    this.initialCountryCode = 'CI',
    this.initialValue,
    this.errorText,
    this.enabled = true,
    this.focusNode,
  });

  /// The field-level fault — see [AppTextField.errorText], same contract.
  final String? errorText;

  /// Called with the normalized number on every edit and country switch — not
  /// at mount: an untouched field leaves the screen's own copy of the stored
  /// value as it is.
  final ValueChanged<String> onChanged;
  final String label;

  /// The picker's country when [initialValue] does not name one (ISO code).
  final String initialCountryCode;

  /// Prefill with a stored number (E.164, e.g. `+2250701020304`). It is shown
  /// under ITS country — the longest calling code it starts with — as its
  /// national part. Read once, when the field is first built; a screen whose
  /// list may cull the field passes its current value, so the field comes back
  /// as it was left.
  final String? initialValue;

  /// Greys the field out (the walk-in checkbox's contract) — same meaning as
  /// [AppTextField.enabled].
  final bool enabled;

  /// So `focusFirstError` can take the user here (SYSTEM.md §14).
  final FocusNode? focusNode;

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  late Country _country;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final (country, national) = _split(
      PhoneNumbering.normalize(widget.initialValue ?? ''),
    );
    _country = country;
    _controller = TextEditingController(text: national);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// [value] as a country and the digits after its calling code. The package
  /// only parses a prefill when it is given NO `initialCountryCode`, and then
  /// takes the first prefix match in its list — Guernsey before the United
  /// Kingdom for `+44` — so the country is resolved here: the longest calling
  /// code, then the country whose length bounds fit the rest. A value with no
  /// `+`, or no known calling code, stays whole under the default country.
  (Country, String) _split(String value) {
    final fallback = countries.firstWhere(
      (c) => c.code == widget.initialCountryCode,
    );
    if (!value.startsWith('+')) return (fallback, value);
    final digits = value.substring(1);
    var longest = 0;
    for (final c in countries) {
      final code = c.fullCountryCode;
      if (digits.startsWith(code) && code.length > longest) {
        longest = code.length;
      }
    }
    if (longest == 0) return (fallback, value);
    final national = digits.substring(longest);
    final matches = [
      for (final c in countries)
        if (c.fullCountryCode == digits.substring(0, longest)) c,
    ];
    final country = matches.contains(fallback)
        ? fallback
        : matches.firstWhere(
            (c) =>
                national.length >= c.minLength &&
                national.length <= c.maxLength,
            orElse: () => matches.first,
          );
    return (country, national);
  }

  void _emit() => widget.onChanged(
    PhoneNumbering.compose(_country.fullCountryCode, _controller.text),
  );

  @override
  Widget build(BuildContext context) {
    return IntlPhoneField(
      controller: _controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      // Read once, by the package's own initState — the resolved country.
      initialCountryCode: _country.code,
      languageCode: 'fr',
      // Silences the package's own check — see the note above. The message is
      // kept for the day someone re-enables it deliberately.
      autovalidateMode: AutovalidateMode.disabled,
      invalidNumberMessage: 'Saisissez un numéro de téléphone valide.',
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
      ),
      onChanged: (_) => _emit(),
      onCountryChanged: (country) {
        _country = country;
        _emit();
      },
    );
  }
}
