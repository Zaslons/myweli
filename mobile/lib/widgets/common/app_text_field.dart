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
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingM,
          vertical: AppTheme.spacingM,
        ),
      ),
    );
  }
}
