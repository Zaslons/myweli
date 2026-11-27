import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Design: docs/design/mobile-a7-forms.md · SYSTEM.md §14, §11.1.
///
/// [errorText] is **the contract for validation** (§11.1), fed by a
/// [FieldErrors] map.
///
/// A7 **removed the `validator` parameter**. Keeping it after its last caller
/// died would have left the old mechanism one autocomplete away — and the two
/// cannot coexist: a `validator` result silently *overwrites*
/// `decoration.errorText` (`text_form_field.dart:218`), so a server fault
/// pinned to a field is erased the moment the form re-validates. See
/// `core/forms/field_errors.dart` for why Flutter's own mechanism cannot
/// express §14 rule 2 in the first place.
class AppTextField extends StatelessWidget {
  final String? label;
  final String? hint;
  final String? errorText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int? maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  /// A7: so a failed submit can put the caret in the field it is complaining
  /// about (§13.5 + §14's focus amendment). There was no way to reach the field
  /// from outside before this.
  final FocusNode? focusNode;

  /// The keyboard's action key (« Rechercher », « Suivant »…) and what it
  /// does. Null: the platform's default for the field.
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  /// Take the focus — and raise the keyboard — when the screen opens.
  final bool autofocus;

  /// A line under the field that guides without blaming (« Tapez au moins 2
  /// lettres »): not an error, so not red.
  final String? helperText;

  /// What a screen reader calls the field when it has no visible [label]:
  /// the [hint] is an example, not a name (SYSTEM.md §13.4).
  final String? semanticsLabel;

  /// [maxLength] still caps the text, but no « 12/100 » is drawn under it.
  final bool showCounter;

  /// What the platform may fill in (`AutofillHints.email`…): the keyboard's
  /// suggestion of the person's own address, on the address change
  /// (account-email-change.md §5.4).
  final Iterable<String>? autofillHints;

  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.errorText,
    this.controller,
    this.onChanged,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.enabled = true,
    this.prefixIcon,
    this.suffixIcon,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
    this.helperText,
    this.semanticsLabel,
    this.showCounter = true,
    this.autofillHints,
  });

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      textInputAction: textInputAction,
      autofocus: autofocus,
      buildCounter: showCounter ? null : _noCounter,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      obscureText: obscureText,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        helperText: helperText,
        // A helper is a sentence, and wraps: the default single line would
        // clip it at 200 % (§13.3). Only the fields that pass a helper see
        // it; the errors keep their default.
        helperMaxLines: 3,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingM,
          vertical: AppTheme.spacingM,
        ),
      ),
    );
    final name = semanticsLabel;
    if (name == null) return field;
    // A plain label, merged into the text field's own node — named first,
    // the hint after it, the name kept once text is typed. `textField: true`
    // here made a SECOND node above the field's, read twice.
    return Semantics(label: name, child: field);
  }

  static Widget? _noCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) => null;
}
