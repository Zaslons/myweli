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
  final source = await _askSource(context, title: 'Ajouter une photo');
  if (source == null) return null;
  return (await _pickOne(source))?.path;
}

/// The gallery's « Ajouter des photos » (docs/design/gallery-multi-select.md):
/// the **camera** still takes one photo; the **gallery** opens the system
/// multi-select, limited to [limit] — the room left. Older Android ignores
/// that limit, so the caller caps the list again. Empty when cancelled.
Future<List<String>> showImagesPicker(
  BuildContext context, {
  required int limit,
}) async {
  final source = await _askSource(context, title: 'Ajouter des photos');
  if (source == null) return const [];
  if (source == ImageSource.camera) {
    final one = await _pickOne(source);
    return one == null ? const [] : [one.path];
  }
  final picked = await ImagePicker().pickMultiImage(
    maxWidth: _maxSide,
    maxHeight: _maxSide,
    imageQuality: _quality,
    limit: limit < 1 ? 1 : limit,
  );
  return [for (final f in picked) f.path];
}

// Cap the source resolution up front; the pipeline compresses again before
// upload.
const double _maxSide = 2400;
const int _quality = 90;

/// Null if the person backs out of the camera/gallery.
Future<XFile?> _pickOne(ImageSource source) => ImagePicker().pickImage(
  source: source,
  maxWidth: _maxSide,
  maxHeight: _maxSide,
  imageQuality: _quality,
);

Future<ImageSource?> _askSource(BuildContext context, {required String title}) {
  return showModalBottomSheet<ImageSource>(
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
            Text(title, style: AppTextStyles.titleLarge),
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
}
