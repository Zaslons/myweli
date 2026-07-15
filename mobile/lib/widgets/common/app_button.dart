import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import 'brand_loader.dart';

enum AppButtonType { primary, secondary, text }

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final AppButtonType type;
  final bool isLoading;
  final bool isFullWidth;
  final IconData? icon;

  /// Arbitrary leading widget (e.g. a multicolor brand logo that can't be an
  /// [IconData], like the Google « G »). Takes precedence over [icon].
  final Widget? leading;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.type = AppButtonType.primary,
    this.isLoading = false,
    this.isFullWidth = true,
    this.icon,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null && !isLoading;

    if (type == AppButtonType.text) {
      return TextButton(
        onPressed: isEnabled ? onPressed : null,
        child: isLoading
            ? const BrandLoader(size: 20, fast: true)
            : Row(
                mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: AppTheme.spacingS),
                  ] else if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: AppTheme.spacingS),
                  ],
                  Text(text),
                ],
              ),
      );
    }

    if (type == AppButtonType.secondary) {
      return OutlinedButton(
        onPressed: isEnabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          minimumSize:
              isFullWidth ? const Size(double.infinity, 48) : const Size(0, 48),
        ),
        child: isLoading
            ? const BrandLoader(size: 20, fast: true)
            : Row(
                mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: AppTheme.spacingS),
                  ] else if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: AppTheme.spacingS),
                  ],
                  Text(text),
                ],
              ),
      );
    }

    return ElevatedButton(
      onPressed: isEnabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
        // A legible-inert disabled pair (SYSTEM.md §21 row 24). The old
        // primary@40% was #999 under white text — 2.21:1.
        disabledBackgroundColor: AppColors.surfaceVariant,
        disabledForegroundColor: AppColors.textDisabled,
        minimumSize:
            isFullWidth ? const Size(double.infinity, 48) : const Size(0, 48),
      ),
      child: isLoading
          ? const BrandLoader(size: 20, fast: true, onDark: true)
          : Row(
              mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: AppTheme.spacingS),
                ] else if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: AppTheme.spacingS),
                ],
                Text(text),
              ],
            ),
    );
  }
}
