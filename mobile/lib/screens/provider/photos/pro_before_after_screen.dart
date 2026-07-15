import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_before_after_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';
import '../../../widgets/common/timed_cached_image.dart';
import '../../../widgets/provider/image_picker_sheet.dart';
import '../../../widgets/provider/mock_image_picker_sheet.dart';

/// Pro management of the salon's before/after pairs (FR-DISC-006). Add (two
/// uploads + optional caption), list, delete. Design: docs/design/provider-before-after.md.
class ProBeforeAfterScreen extends StatefulWidget {
  const ProBeforeAfterScreen({super.key});

  @override
  State<ProBeforeAfterScreen> createState() => _ProBeforeAfterScreenState();
}

class _ProBeforeAfterScreenState extends State<ProBeforeAfterScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = context.read<ProAuthProvider>().activeSalonId;
      if (id != null && id.isNotEmpty) {
        context.read<ProBeforeAfterProvider>().load(id);
      }
    });
  }

  Future<String?> _pick() async => AppConfig.useApiBackend
      ? showImagePicker(context)
      : showMockImagePicker(context);

  Future<void> _addPair(String providerId, ProBeforeAfterProvider p) async {
    final messenger = ScaffoldMessenger.of(context);
    final before = await _pick();
    if (before == null || !mounted) return;
    final after = await _pick();
    if (after == null || !mounted) return;
    final caption = await _askCaption();
    if (!mounted) return;
    final ok = await p.addPair(
      providerId,
      beforeSource: before,
      afterSource: after,
      caption: caption,
    );
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(p.error ?? 'Échec de l’envoi'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<String?> _askCaption() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Légende (optionnel)'),
        content: TextField(
          controller: controller,
          maxLength: 120,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex. Tresses collées'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Passer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _removePair(
    String providerId,
    ProBeforeAfterProvider p,
    int index,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette paire ?'),
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
    if (confirmed == true) await p.removePair(providerId, index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Avant / Après')),
      body: Consumer2<ProAuthProvider, ProBeforeAfterProvider>(
        builder: (context, auth, p, _) {
          final providerId = auth.activeSalonId;
          if (providerId == null || providerId.isEmpty) {
            return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Profil incomplet',
              description:
                  'Configurez votre profil pour gérer vos réalisations.',
            );
          }
          if (p.isLoading) return const LoadingIndicator();
          if (p.loadFailed) {
            return EmptyState(
              icon: Icons.wifi_off,
              title: 'Chargement impossible',
              description: 'Vérifiez votre connexion et réessayez.',
              actionText: 'Réessayer',
              onAction: () => p.load(providerId),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            children: [
              Text(
                'Montrez vos plus belles transformations. Choisissez la photo '
                'avant puis la photo après ; les images sont optimisées '
                'automatiquement.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppTheme.spacingM),
              if (p.pairs.isEmpty && !p.isUploading)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppTheme.spacingXL),
                  child: Text(
                    'Aucune réalisation pour le moment.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ),
              for (var i = 0; i < p.pairs.length; i++)
                _PairCard(
                  before: p.pairs[i].before,
                  after: p.pairs[i].after,
                  caption: p.pairs[i].caption,
                  onRemove: () => _removePair(providerId, p, i),
                ),
              if (p.isUploading)
                Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          value:
                              p.uploadProgress == 0 ? null : p.uploadProgress,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingM),
                      Text('Envoi… ${(p.uploadProgress * 100).round()}%',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textTertiary)),
                    ],
                  ),
                ),
              const SizedBox(height: AppTheme.spacingM),
              AppButton(
                text: 'Ajouter une paire',
                onPressed: p.isUploading ? null : () => _addPair(providerId, p),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PairCard extends StatelessWidget {
  const _PairCard({
    required this.before,
    required this.after,
    required this.caption,
    required this.onRemove,
  });

  final String before;
  final String after;
  final String? caption;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _labelled('Avant', before, true)),
              Expanded(child: _labelled('Après', after, false)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.spacingM,
                AppTheme.spacingS, AppTheme.spacingS, AppTheme.spacingS),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    caption ?? '—',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: caption == null
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onRemove,
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  icon: const Icon(Icons.delete_outline, size: AppTheme.iconS),
                  label: const Text('Supprimer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelled(String label, String url, bool left) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(left ? AppTheme.radiusMedium : 0),
            topRight: Radius.circular(left ? 0 : AppTheme.radiusMedium),
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: TimedCachedImage(imageUrl: url, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: 6,
          left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingS, vertical: AppTheme.spacingXS),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            ),
            child: Text(label,
                style: AppTextStyles.labelSmall.copyWith(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
