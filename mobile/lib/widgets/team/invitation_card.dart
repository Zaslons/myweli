import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../models/team_invitation.dart';
import '../common/app_button.dart';

/// « {Salon} vous invite comme {Rôle} » — shared by the login
/// « Invitations » step and the authed Profil → Invitations screen
/// (module `access` R3 §2.2/§2.3).
/// Whether « Rejoindre » (filled) and « Refuser » (text) fit on one line each,
/// side by side, in [maxWidth] — measured with the style and horizontal
/// padding the button themes really apply (`AppTheme`: `labelLarge`,
/// `spacingM` each side), at the current text scale.
bool _actionsFitSideBySide(BuildContext context, double maxWidth) {
  final theme = Theme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  double label(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  final joinStyle = theme.elevatedButtonTheme.style?.textStyle?.resolve({});
  final declineStyle = theme.textButtonTheme.style?.textStyle?.resolve({});
  const chrome = 2 * AppTheme.spacingM; // each button's horizontal padding
  final need =
      label('Rejoindre', joinStyle) +
      chrome +
      AppTheme.spacingM + // the gap between them
      label('Refuser', declineStyle) +
      chrome;
  return need <= maxWidth;
}

class InvitationCard extends StatelessWidget {
  const InvitationCard({
    super.key,
    required this.invitation,
    required this.onAccept,
    required this.onDecline,
    this.busy = false,
    this.locked = false,
  });

  final TeamInvitation invitation;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  /// This card's answer is out: « Rejoindre » spins, both buttons wait.
  final bool busy;

  /// Another card's answer is out: both buttons wait, without a spinner — one
  /// answer at a time (pro-app-batch7.md §2.6, as the web's card).
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.surfaceVariant,
                      child: Icon(
                        Icons.storefront_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingM),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: AppTextStyles.bodyLarge,
                          children: [
                            TextSpan(
                              text: invitation.salonName,
                              style: AppTextStyles.titleMedium,
                            ),
                            const TextSpan(text: ' vous invite comme '),
                            TextSpan(
                              text: invitation.roleLabel,
                              style: AppTextStyles.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (invitation.expiresAt != null) ...[
                  const SizedBox(height: AppTheme.spacingS),
                  Text(
                    'Expire le ${Formatters.formatDate(invitation.expiresAt!)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          LayoutBuilder(
            builder: (context, constraints) {
              final join = AppButton(
                text: 'Rejoindre',
                isLoading: busy,
                onPressed: busy || locked ? null : onAccept,
              );
              // Side by side while « Rejoindre » can sit WHOLE beside
              // « Refuser »; otherwise stacked, each full width. §13.3: a
              // control's label wraps between words, never inside one — and
              // the first Linux golden of the rejoin gate showed « Rejoind/re »
              // at 360dp × 2 (needs 119.5dp, got 100.5). Measured with the
              // buttons' own theme style and padding rather than a text-scale
              // threshold, which would arrive late on a narrower card. At 1×
              // it is side by side, as before, so every 1× picture is unchanged.
              // docs/design/pro-rejoin-gate.md
              if (_actionsFitSideBySide(context, constraints.maxWidth)) {
                return Row(
                  children: [
                    Expanded(child: join),
                    const SizedBox(width: AppTheme.spacingM),
                    // `isFullWidth: false`, and it is load-bearing (A11 C8).
                    // A Row hands a NON-flex child an unbounded width, and this
                    // was the one button in the app sitting in such a slot:
                    // « Rejoindre » is `Expanded`, this one is not. Once
                    // AppButton's label became flexible, a `MainAxisSize.max`
                    // row could no longer be laid out there — `RenderFlex`
                    // allows flex children under an unbounded main axis only
                    // for **min + loose**, which is exactly what
                    // `isFullWidth: false` selects.
                    AppButton(
                      text: 'Refuser',
                      type: AppButtonType.text,
                      isFullWidth: false,
                      onPressed: busy || locked ? null : onDecline,
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  join,
                  const SizedBox(height: AppTheme.spacingS),
                  AppButton(
                    text: 'Refuser',
                    type: AppButtonType.text,
                    onPressed: busy || locked ? null : onDecline,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
