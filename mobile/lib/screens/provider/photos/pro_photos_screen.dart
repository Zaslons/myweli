import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/a11y/reduce_motion.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_gallery_provider.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/confirm_dialog.dart';
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
      AppSnackBar.showOn(messenger, gallery.error ?? 'Échec de l’envoi',
          kind: SnackKind.error);
    }
  }

  Future<void> _removePhoto(
      String providerId, ProGalleryProvider gallery, int index) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Supprimer cette photo ?',
      message: 'Elle disparaîtra de votre galerie publique.',
      confirmLabel: 'Supprimer la photo',
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // The removed photo and WHERE it was — undo re-inserts it into whatever
    // the gallery looks like when « Annuler » is tapped, so an upload or a
    // reorder during the 10s window survives (the review's catch).
    final removed = gallery.photos[index];
    final ok = await gallery.removePhoto(providerId, index);
    if (!ok) {
      AppSnackBar.showOn(messenger, gallery.error ?? 'Suppression impossible.',
          kind: SnackKind.error);
      return;
    }
    // Before A6 the photo simply disappeared: no confirmation, nothing
    // announced, no way back. The snackbar IS the only route back, so it
    // carries §15's 10s.
    AppSnackBar.showOn(
      messenger,
      'Photo supprimée',
      kind: SnackKind.success,
      action: SnackAction(
        label: 'Annuler',
        // A failed undo used to be silent — the Future was discarded.
        onPressed: () async {
          final restored =
              await gallery.restorePhotoAt(providerId, index, removed);
          if (!restored) {
            AppSnackBar.showOn(
                messenger, gallery.error ?? 'Restauration impossible.',
                kind: SnackKind.error);
          }
        },
      ),
    );
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
                mainAxisSpacing: AppTheme.spacingSM,
                crossAxisSpacing: AppTheme.spacingSM,
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
          child: Semantics(
            button: true,
            label: 'Supprimer la photo',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: SizedBox(
                // §13.2 48 hit area; Align keeps the × at the (4,4) corner, the
                // transparent box leaves the photo visible.
                width: 48,
                height: 48,
                child: Align(
                  alignment: Alignment.topRight,
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
            ),
          ),
        ),
        // Reorder arrows as a full-width bottom bar split into two ≥48 halves
        // (§13.2): two 48px targets can't sit side-by-side in a ~90-112px grid
        // tile, and a bottom-left/bottom-right split reads more clearly than a
        // clustered pair. Each half fills its side; the visible circle centres.
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Row(
            children: [
              Expanded(
                child: onMoveLeft != null
                    ? _ArrowButton(
                        icon: Icons.chevron_left,
                        semanticLabel: 'Déplacer vers la gauche',
                        onTap: onMoveLeft!,
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: onMoveRight != null
                    ? _ArrowButton(
                        icon: Icons.chevron_right,
                        semanticLabel: 'Déplacer vers la droite',
                        onTap: onMoveRight!,
                      )
                    : const SizedBox.shrink(),
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
              // A track, because the arc at 0 % draws NOTHING:
              // `progress_indicator.dart:673` sweeps `value * _sweep`
              // and `:1130` leaves `trackColor` null unless one is
              // given. Under reduced motion this box holds still at 0,
              // so "a still arc" had to become true rather than stay
              // a comment about an empty rectangle.
              backgroundColor: AppColors.border,
              // §9/A8: the null fallback is an INDETERMINATE spinner, and
              // `repeat()` is exactly what the framework scale cannot reach.
              // Under the flag it holds a still 0 % arc — and the
              // « Envoi… 0 % » below already carries what the spin was saying.
              value:
                  progress == 0 && !reduceMotionOf(context) ? null : progress,
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        // §13.2 touch target ≥48 tall; width comes from the Expanded half. The
        // box is transparent — only the 24px circle paints.
        height: 48,
        child: Center(
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
        ),
      ),
    );
  }
}
