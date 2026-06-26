import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// Bottom sheet to pick a salon photo from the **camera** or the **gallery**,
/// returning the chosen file path (or null if cancelled / nothing picked).
/// Bytes are compressed + uploaded by the image pipeline
/// (docs/design/pro-image-upload-pipeline.md).
Future<String?> showImagePicker(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.secondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusXL),
      ),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ajouter une photo', style: AppTextStyles.titleLarge),
            const SizedBox(height: AppTheme.spacingM),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Appareil photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
  if (source == null) return null;

  // Cap the source resolution up front; the pipeline compresses again before
  // upload. Returns null if the user backs out of the camera/gallery.
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 90,
  );
  return picked?.path;
}
