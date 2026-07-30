import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import 'brand_loader.dart';

enum AppButtonType { primary, secondary, text }

/// The app's button (SYSTEM.md §11.1; its 48dp floor is §13.2).
///
/// ## The label is a FLEXIBLE child, and it has to be (A11 C8)
///
/// A `Row` lays a non-flex child out with an **unbounded** main-axis
/// constraint. So a bare `Text` here measured its full intrinsic width and the
/// Row overflowed rather than the label shrinking: « Voir toutes les communes »
/// ran **65px** past a 360dp screen at 200% text, and « + Nouveau rendez-vous »
/// **32px**. Both are `EmptyState` actions, i.e. the one control on an
/// otherwise empty screen.
///
/// **No gate caught it, and no gate could.** The striped overflow banner is
/// debug-only; in a release build the label is silently cut off. It was found by
/// running the pro app on a 360dp Android device at 200% text — the surface
/// A11 exists to defend, and the first slice to actually put the app on one.
///
/// `Flexible` bounds the Text, so a label too long for the width **wraps between
/// words** and the button grows taller. §13.3 permits that for a control and
/// forbids a mid-word break; `app_button_test.dart` measures both.
///
/// ## The one cost: `isFullWidth: true` now needs a BOUNDED width
///
/// This is narrower than it first looks, and the narrow version is the true one
/// — `app_button_test.dart` measures both halves rather than asserting either.
///
/// `RenderFlex` refuses a flex child under an unbounded main axis, but **only**
/// for `MainAxisSize.max`: min + `FlexFit.loose` is explicitly permitted, and
/// that is what `isFullWidth: false` selects. So an intrinsic-width button
/// still drops into any slot at all, including a bare `Row` child.
///
/// For `isFullWidth: true` the primary and secondary variants already required
/// a bound — a `minimumSize` of `Size(double.infinity, 48)` cannot resolve
/// against an infinite constraint either. That left the **text** variant, which
/// sets no `minimumSize` and could therefore live anywhere. Exactly one did:
/// `InvitationCard` put « Refuser » beside an `Expanded` « Rejoindre », i.e. in
/// an unbounded slot. It is now declared `isFullWidth: false` — which renders
/// identically, because with no bound to fill, max and min both shrink-wrap.
///
/// Six tests went red the moment that was wrong, which is the argument for
/// keeping the assertion loud rather than papering over it with a
/// `LayoutBuilder`: a LayoutBuilder cannot answer intrinsic queries, and
/// `IntrinsicHeight` is used twice in `lib/`.
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
            ? const BrandLoader(size: AppTheme.iconS, fast: true)
            : Row(
                mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: AppTheme.spacingS),
                  ] else if (icon != null) ...[
                    Icon(icon, size: AppTheme.iconS),
                    const SizedBox(width: AppTheme.spacingS),
                  ],
                  // Flexible, not bare — see the class doc (A11 C8).
                  Flexible(child: Text(text, textAlign: TextAlign.center)),
                ],
              ),
      );
    }

    if (type == AppButtonType.secondary) {
      return OutlinedButton(
        onPressed: isEnabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          minimumSize: isFullWidth
              ? const Size(double.infinity, 48)
              : const Size(0, 48),
        ),
        child: isLoading
            ? const BrandLoader(size: AppTheme.iconS, fast: true)
            : Row(
                mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: AppTheme.spacingS),
                  ] else if (icon != null) ...[
                    Icon(icon, size: AppTheme.iconS),
                    const SizedBox(width: AppTheme.spacingS),
                  ],
                  // Flexible, not bare — see the class doc (A11 C8).
                  Flexible(child: Text(text, textAlign: TextAlign.center)),
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
        minimumSize: isFullWidth
            ? const Size(double.infinity, 48)
            : const Size(0, 48),
      ),
      child: isLoading
          ? const BrandLoader(size: AppTheme.iconS, fast: true, onDark: true)
          : Row(
              mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: AppTheme.spacingS),
                ] else if (icon != null) ...[
                  Icon(icon, size: AppTheme.iconS),
                  const SizedBox(width: AppTheme.spacingS),
                ],
                // Flexible, not bare — see the class doc (A11 C8).
                Flexible(child: Text(text, textAlign: TextAlign.center)),
              ],
            ),
    );
  }
}
