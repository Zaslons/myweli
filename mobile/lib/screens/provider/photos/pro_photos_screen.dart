import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_gallery_provider.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';
import '../../../widgets/common/timed_cached_image.dart';
import '../../../widgets/provider/image_picker_sheet.dart';
import '../../../widgets/provider/mock_image_picker_sheet.dart';

class ProPhotosScreen extends StatefulWidget {
  const ProPhotosScreen({super.key});

  @override
  State<ProPhotosScreen> createState() => _ProPhotosScreenState();
}

class _ProPhotosScreenState extends State<ProPhotosScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = context.read<ProAuthProvider>().activeSalonId;
      if (id != null && id.isNotEmpty) {
        context.read<ProGalleryProvider>().load(id);
      }
    });
  }

  Future<void> _addPhoto(String providerId, ProGalleryProvider gallery) async {
    final messenger = ScaffoldMessenger.of(context);
    // Real camera/gallery picker against the backend; the sample-image sheet
    // in demo (mock) mode so previews still render without a device file.
    final String? source;
    if (AppConfig.useApiBackend) {
      source = await showImagePicker(context);
    } else {
      source = await showMockImagePicker(context);
    }
    if (source == null) return;
    final ok = await gallery.addPhoto(providerId, source);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(gallery.error ?? 'Échec de l’envoi'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _removePhoto(
      String providerId, ProGalleryProvider gallery, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette photo ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await gallery.removePhoto(providerId, index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Photos du salon')),
      body: Consumer2<ProAuthProvider, ProGalleryProvider>(
        builder: (context, auth, gallery, _) {
          final providerId = auth.activeSalonId;
          if (providerId == null || providerId.isEmpty) {
            return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Profil incomplet',
              description: 'Configurez votre profil pour gérer vos photos.',
            );
          }
          if (gallery.isLoading) {
            return const LoadingIndicator();
          }
          if (gallery.loadFailed) {
            return EmptyState(
              icon: Icons.wifi_off,
              title: 'Chargement impossible',
              description: 'Vérifiez votre connexion et réessayez.',
              actionText: 'Réessayer',
              onAction: () => gallery.load(providerId),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            children: [
              Text(
                'Ajoutez au moins 3 photos de qualité. La première sert de '
                'couverture. Les images sont optimisées automatiquement.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppTheme.spacingM),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  for (var i = 0; i < gallery.photos.length; i++)
                    _PhotoTile(
                      url: gallery.photos[i],
                      isCover: i == 0,
                      onRemove: () => _removePhoto(providerId, gallery, i),
                      // Audit 3.6: reorder — the first photo is the cover.
                      onMoveLeft: i > 0
                          ? () => gallery.movePhoto(providerId, i, -1)
                          : null,
                      onMoveRight: i < gallery.photos.length - 1
                          ? () => gallery.movePhoto(providerId, i, 1)
                          : null,
                    ),
                  if (gallery.isUploading)
                    _UploadingTile(progress: gallery.uploadProgress),
                  _AddTile(
                    onTap: gallery.isUploading
                        ? null
                        : () => _addPhoto(providerId, gallery),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String url;
  final bool isCover;
  final VoidCallback onRemove;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;

  const _PhotoTile({
    required this.url,
    required this.isCover,
    required this.onRemove,
    this.onMoveLeft,
    this.onMoveRight,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: TimedCachedImage(imageUrl: url, fit: BoxFit.cover),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(AppTheme.spacingXS),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close,
                  size: AppTheme.iconXS, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          right: 4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onMoveLeft != null)
                _ArrowButton(
                  icon: Icons.chevron_left,
                  semanticLabel: 'Déplacer vers la gauche',
                  onTap: onMoveLeft!,
                ),
              if (onMoveLeft != null && onMoveRight != null)
                const SizedBox(width: AppTheme.spacingXS),
              if (onMoveRight != null)
                _ArrowButton(
                  icon: Icons.chevron_right,
                  semanticLabel: 'Déplacer vers la droite',
                  onTap: onMoveRight!,
                ),
            ],
          ),
        ),
        if (isCover)
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingS, vertical: AppTheme.spacingXS),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              ),
              child: Text(
                'Couverture',
                style: AppTextStyles.labelSmall.copyWith(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

class _UploadingTile extends StatelessWidget {
  final double progress;

  const _UploadingTile({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              value: progress == 0 ? null : progress,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Envoi… ${(progress * 100).round()}%',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback? onTap;

  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DottedBorderBox(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined,
                color: AppColors.textSecondary, size: AppTheme.iconM),
            const SizedBox(height: AppTheme.spacingXS),
            Text('Ajouter',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class DottedBorderBox extends StatelessWidget {
  final Widget child;

  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: child,
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  const _ArrowButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingXS),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: AppTheme.iconXS,
          color: Colors.white,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}
