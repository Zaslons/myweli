import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/external_link.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/settings_tile.dart';
import '../../widgets/common/timed_cached_image.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profil')),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          final user = authProvider.user;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Column(
              children: [
                const SizedBox(height: AppTheme.spacingL),
                // Avatar
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.surface,
                  child: user?.avatarUrl == null
                      ? const Icon(
                          Icons.person,
                          size: AppTheme.iconL,
                          color: AppColors.textTertiary,
                        )
                      : ClipOval(
                          child: TimedCachedImage(
                            imageUrl: user!.avatarUrl!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
                const SizedBox(height: AppTheme.spacingM),
                // Name
                Text(
                  user?.name ?? 'Utilisateur',
                  style: AppTextStyles.headlineMedium,
                ),
                const SizedBox(height: AppTheme.spacingS),
                // Phone
                Text(
                  user?.phoneNumber ?? '',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingXL),
                // Settings List
                SettingsTile(
                  icon: Icons.edit,
                  title: 'Modifier le profil',
                  onTap: () {
                    if (user == null) {
                      context.go(
                        '/login?returnTo=${Uri.encodeComponent('/profile')}',
                      );
                      return;
                    }
                    context.push('/profile/edit');
                  },
                ),
                if (user != null)
                  SettingsTile(
                    icon: Icons.favorite,
                    title: 'Mes favoris',
                    onTap: () {
                      context.push('/carte');
                    },
                  ),
                if (user != null)
                  SettingsTile(
                    icon: Icons.notifications,
                    title: 'Préférences de notification',
                    onTap: () => context.push('/profile/notifications'),
                  ),
                SettingsTile(
                  icon: Icons.language,
                  title: 'Langue',
                  trailing: const Text('Français'),
                  onTap: () {
                    AppSnackBar.show(context, 'Fonctionnalité à venir');
                  },
                ),
                SettingsTile(
                  icon: Icons.help_outline,
                  title: 'Aide & Support',
                  // Parity 15.2: manual intake via WhatsApp support.
                  onTap: () => openWhatsApp(
                    context,
                    number: AppConfig.supportWhatsApp,
                    message:
                        'Bonjour MyWeli, j’ai besoin d’aide concernant '
                        'mon compte.',
                  ),
                ),
                SettingsTile(
                  icon: Icons.info_outline,
                  title: 'À propos',
                  // L1: it rendered a chevron it did not honour since PR-0 —
                  // `onTap` was simply absent — and printed the version as a
                  // literal beside `AppConstants.appVersion`. Now it opens the
                  // legal surface, which is what a store reviewer taps it for.
                  onTap: () => context.push('/a-propos'),
                ),
                if (user != null) ...[
                  SettingsTile(
                    icon: Icons.download_outlined,
                    title: 'Exporter mes données',
                    onTap: () => context.push('/profile/data'),
                  ),
                  SettingsTile(
                    icon: Icons.delete_outline,
                    title: 'Supprimer mon compte',
                    danger: true,
                    onTap: () => _handleDelete(context, authProvider),
                  ),
                ],
                const SizedBox(height: AppTheme.spacingXL),
                // Logout Button (only show if authenticated)
                if (user != null)
                  AppButton(
                    text: 'Déconnexion',
                    type: AppButtonType.secondary,
                    onPressed: () async {
                      final confirmed = await showConfirmDialog(
                        context,
                        title: 'Déconnexion',
                        message:
                            'Vous devrez vous reconnecter pour '
                            'retrouver vos rendez-vous.',
                        confirmLabel: 'Se déconnecter',
                        // Reversible — you log back in. Red would be a lie.
                        isDestructive: false,
                      );

                      if (confirmed && context.mounted) {
                        // Clear favorites from state (but keep in storage per user)
                        final favoritesProvider =
                            Provider.of<FavoritesProvider>(
                              context,
                              listen: false,
                            );
                        favoritesProvider.clearFavorites();

                        await authProvider.logout();
                        if (context.mounted) {
                          context.go('/login');
                        }
                      }
                    },
                  )
                else
                  AppButton(
                    text: 'Se connecter',
                    onPressed: () {
                      context.go(
                        '/login?returnTo=${Uri.encodeComponent('/profile')}',
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleDelete(
    BuildContext context,
    AuthProvider authProvider,
  ) async {
    final confirmed = await _confirmDeletion(context);
    if (!confirmed || !context.mounted) return;

    final favoritesProvider = Provider.of<FavoritesProvider>(
      context,
      listen: false,
    );
    final success = await authProvider.deleteAccount();
    if (!context.mounted) return;

    if (success) {
      favoritesProvider.clearFavorites();
      context.go('/login');
      AppSnackBar.show(context, 'Compte supprimé', kind: SnackKind.success);
    } else {
      AppSnackBar.show(
        context,
        authProvider.error ?? 'Erreur lors de la suppression',
        kind: SnackKind.error,
      );
    }
  }

  /// A6: the hand-rolled StatefulBuilder + gating + its own controller became
  /// three arguments — the ladder's top rung expressed as parameters.
  Future<bool> _confirmDeletion(BuildContext context) => showConfirmDialog(
    context,
    title: 'Supprimer mon compte',
    // **This copy was false, and stayed false after the cascade landed.**
    // It promised that appointments and reviews « seront supprimés ». They
    // are not: the booking survives stripped of your name, phone and notes
    // (the salon needs it to reconcile takings) and the review survives
    // without its author (the rating is an aggregate the salon earned).
    // Saying « supprimés » of either would be describing an erasure the
    // backend deliberately does not perform.
    //
    // One transcription, three surfaces: this dialog, `openapi.yaml`'s
    // `/me` `delete:` description, and myweli.com/suppression-compte.
    message:
        'Cette action est définitive. Votre profil, vos favoris et '
        'vos notifications sont supprimés ; vos rendez-vous et vos avis '
        'restent chez le salon, sans votre nom. Pensez à exporter vos '
        'données avant.',
    confirmLabel: 'Supprimer définitivement',
    icon: Icons.warning_amber_rounded,
    confirmWord: 'SUPPRIMER',
  );
}
