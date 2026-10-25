import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/chip_tone.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

export '../../core/theme/chip_tone.dart';

/// The chip (SYSTEM.md §11.3): `radiusPill`; **filled** when chosen,
/// **outlined** (`borderStrong`) otherwise, **tinted** for a status. Built in
/// B9.8 F3 (docs/design/hygiene-batch9.md §2.7.4); every chip on a screen is
/// one, and `chips_pin_test.dart` holds it.
///
/// The three that act are Material's own chips under `chipTheme`, so a
/// screen reader hears « sélectionné », a keyboard reaches them and the
/// target is 48: the theme draws them, and nothing here overrides it.
/// A chosen chip shows the ✓ (Q16): the selection is not the fill alone
/// (§13), and the ✓ takes the place of the icon.
class AppChip extends StatelessWidget {
  /// One of several — a filter, an option.
  const AppChip.choice({
    super.key,
    required this.label,
    required bool this.selected,
    required ValueChanged<bool> this.onSelected,
    this.icon,
  }) : _kind = _Kind.choice,
       onPressed = null,
       tone = null,
       dense = false;

  /// A label of the thing: a client's tag. Outlined, and nothing to do.
  const AppChip.tag({super.key, required this.label, this.icon})
    : _kind = _Kind.tag,
      selected = null,
      onSelected = null,
      onPressed = null,
      tone = null,
      dense = false;

  /// Something to do, in a row of tags: « + Tags ».
  const AppChip.action({
    super.key,
    required this.label,
    required VoidCallback this.onPressed,
    this.icon,
  }) : _kind = _Kind.action,
       selected = null,
       onSelected = null,
       tone = null,
       dense = false;

  /// A status or a badge: the tone's 12% tint and its label in the tone's
  /// colour — measured ≥ 4.5:1 for every tone on `background`, the darker of
  /// the two surfaces it sits on. [dense] drops the vertical padding, for a
  /// row whose height is the text's (the rating line of a salon card).
  const AppChip.status({
    super.key,
    required this.label,
    required AppChipTone this.tone,
    this.icon,
    this.dense = false,
  }) : _kind = _Kind.status,
       selected = null,
       onSelected = null,
       onPressed = null;

  final String label;
  final IconData? icon;
  final bool? selected;
  final ValueChanged<bool>? onSelected;
  final VoidCallback? onPressed;
  final AppChipTone? tone;
  final bool dense;
  final _Kind _kind;

  /// The share of the tone's colour in its tint.
  static const double tintAlpha = 0.12;

  @override
  Widget build(BuildContext context) => switch (_kind) {
    _Kind.choice => ChoiceChip(
      label: Text(label),
      selected: selected!,
      onSelected: onSelected,
      showCheckmark: true,
      // Chosen, the ✓ takes the icon's place (Q16): Material paints its
      // check OVER an avatar, and the icon still showed through.
      avatar: icon == null || selected!
          ? null
          : Icon(icon, size: AppTheme.iconXS, color: AppColors.textPrimary),
    ),
    _Kind.tag => Chip(
      label: Text(label),
      avatar: icon == null
          ? null
          : Icon(icon, size: AppTheme.iconXS, color: AppColors.textPrimary),
    ),
    _Kind.action => ActionChip(
      label: Text(label),
      onPressed: onPressed,
      avatar: icon == null
          ? null
          : Icon(icon, size: AppTheme.iconXS, color: AppColors.textPrimary),
    ),
    _Kind.status => _status(),
  };

  Widget _status() {
    final (tint, ink, border) = switch (tone!) {
      AppChipTone.success => (AppColors.success, AppColors.success, null),
      AppChipTone.warning => (AppColors.warning, AppColors.warning, null),
      AppChipTone.error => (AppColors.error, AppColors.error, null),
      AppChipTone.info => (AppColors.info, AppColors.info, null),
      AppChipTone.neutral => (
        AppColors.textSecondary,
        AppColors.textSecondary,
        null,
      ),
      AppChipTone.strong => (AppColors.primary, AppColors.textPrimary, null),
      // The tint alone is faint for a hue this light: the owner's line too,
      // as `TeamRoleChip` drew it.
      AppChipTone.gold => (
        AppColors.gold,
        AppColors.textPrimary,
        AppColors.gold.withValues(alpha: 0.5),
      ),
    };
    final style = AppTextStyles.labelSmall.copyWith(color: ink);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint.withValues(alpha: tintAlpha),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.spacingS,
          vertical: dense ? 0 : AppTheme.spacingXS,
        ),
        child: icon == null
            ? Text(label, style: style)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: AppTheme.iconXS, color: ink),
                  const SizedBox(width: AppTheme.spacingXS),
                  // A long badge wraps inside its pill rather than run out of
                  // it (« Réservation vérifiée » at 200%, A11 C5).
                  Flexible(child: Text(label, style: style)),
                ],
              ),
      ),
    );
  }
}

enum _Kind { choice, tag, action, status }
