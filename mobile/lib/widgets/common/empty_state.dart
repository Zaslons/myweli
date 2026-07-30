import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import 'app_button.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? actionText;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(AppTheme.spacingXL),
      child: Column(
        // `min`, not the old `mainAxisAlignment: center`. A Column defaults to
        // `MainAxisSize.max`, so inside a `Center` it took the full height and
        // the ALIGNMENT did the centring. Inside the `ConstrainedBox` below the
        // outer `Center` centres, and the Column must shrink-wrap — otherwise
        // it re-fills the box and the scroll view has nothing to scroll.
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: AppTheme.iconXL,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppTheme.spacingL),
          Text(
            title,
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (description != null) ...[
            const SizedBox(height: AppTheme.spacingS),
            Text(
              description!,
              // §4 (SYSTEM §21 row 27): the empty-state body is reading copy
              // — bodyLarge, "Default reading text".
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (actionText != null && onAction != null) ...[
            const SizedBox(height: AppTheme.spacingL),
            AppButton(
              text: actionText!,
              onPressed: onAction,
              isFullWidth: false,
            ),
          ],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // **Already inside a scroller.** `AdminDataTable` returns an
        // `EmptyState` under a `SingleChildScrollView` on SIX admin screens —
        // five of them via a `Column`, and `admin_kyc_queue_screen.dart:47`
        // with the table directly under the scroller, which is the same
        // unbounded host by a shorter path. (A12 said five; the adversarial
        // review counted six, and the sixth is the one that shows the shape
        // does not depend on the `Column` at all.) The incoming height is
        // therefore unbounded — and a second viewport
        // there is *"Vertical viewport was given unbounded height"*, while a
        // `minHeight: constraints.maxHeight` of infinity is an assert. There is
        // also nothing to fix: the parent scroller IS the escape.
        if (!constraints.hasBoundedHeight) return Center(child: content);

        return SingleChildScrollView(
          child: ConstrainedBox(
            // Centred while it fits — identical pixels to before — and
            // scrollable the moment it does not.
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}
