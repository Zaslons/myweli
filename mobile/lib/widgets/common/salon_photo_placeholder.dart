import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';

/// What a salon with no photo shows: a quiet tile with the shop glyph, drawn
/// on the phone.
///
/// It replaces `https://via.placeholder.com/400x300`, which the salon card
/// fetched for every salon without a photo: a request to a third party that
/// the privacy label does not declare (docs/design/consumer-app-truth.md
/// §2.5). Decorative, so it is excluded from semantics: the card's name says
/// which salon this is.
class SalonPhotoPlaceholder extends StatelessWidget {
  const SalonPhotoPlaceholder({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        color: AppColors.surface,
        alignment: Alignment.center,
        child: const Icon(
          Icons.store,
          size: AppTheme.iconL,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
