import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';

/// Compact top-bar search for admin lists; fires [onSubmitted] on Enter.
/// Design: docs/design/admin-console-ui.md §2.
class AdminSearchField extends StatelessWidget {
  const AdminSearchField({
    super.key,
    required this.hint,
    required this.onSubmitted,
  });

  final String hint;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      // No height: the constant 38 clipped the input at 200% (it measured 38 at
      // both 1× and 2× while the text grew inside it — §13.3). Unbounded, the
      // field takes its intrinsic height: 48 at 1×, 56 at 200%. A `minHeight: 38`
      // floor would be dead code — Flutter already floors a decorated field with
      // a prefixIcon at kMinInteractiveDimension (48).
      child: TextField(
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: AppTextStyles.bodyMedium,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
          prefixIcon: const Icon(Icons.search, size: AppTheme.iconS),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
          filled: true,
          fillColor: AppColors.secondary,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            borderSide: const BorderSide(color: AppColors.borderStrong),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            borderSide: const BorderSide(color: AppColors.borderFocus),
          ),
        ),
      ),
    );
  }
}
