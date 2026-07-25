import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/timed_cached_image.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profil'),
      ),
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
                _SettingsItem(
                  icon: Icons.edit,
                  title: 'Modifier le profil',
                  onTap: () {
                    if (user == null) {
                      context.go(
                          '/login?returnTo=${Uri.encodeComponent('/profile')}');
                      return;
                    }
                    context.push('/profile/edit');
                  },
                ),
                if (user != null)
                  _SettingsItem(
                    icon: Icons.favorite,
                    title: 'Mes favoris',
                    onTap: () {
                      context.push('/favorites');
                    },
                  ),
                if (user != null)
                  _SettingsItem(
                    icon: Icons.notifications,
                    title: 'Notifications',
                    onTap: () => context.push('/profile/notifications'),
                  ),
                _SettingsItem(
                  icon: Icons.language,
                  title: 'Langue',
                  trailing: const Text('Français'),
                  onTap: () {
                    AppSnackBar.show(context, 'Fonctionnalité à venir');
                  },
                ),
                _SettingsItem(
                  icon: Icons.help_outline,
                  title: 'Aide & Support',
                  // Parity 15.2: manual intake via WhatsApp support.
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final number = AppConfig.supportWhatsApp;
                    if (number.isEmpty) {
                      AppSnackBar.showOn(
                          messenger, 'Contact bientôt disponible.');
                      return;
                    }
                    final uri = Uri.parse(
                      'https://wa.me/$number?text=${Uri.encodeComponent('Bonjour MyWeli, j’ai besoin d’aide concernant mon compte.')}',
                    );
                    if (!await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    )) {
                      AppSnackBar.showOn(
                          messenger, 'Impossible d’ouvrir WhatsApp.',
                          kind: SnackKind.error);
                    }
                  },
                ),
                const _SettingsItem(
                  icon: Icons.info_outline,
                  title: 'À propos',
                  trailing: Text('Version 1.0.0'),
                ),
                if (user != null) ...[
                  _SettingsItem(
                    icon: Icons.download_outlined,
                    title: 'Exporter mes données',
                    onTap: () => context.push('/profile/data'),
                  ),
                  _SettingsItem(
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
                        message: 'Vous devrez vous reconnecter pour '
                            'retrouver vos rendez-vous.',
                        confirmLabel: 'Se déconnecter',
                        // Reversible — you log back in. Red would be a lie.
                        isDestructive: false,
                      );

                      if (confirmed && context.mounted) {
                        // Clear favorites from state (but keep in storage per user)
                        final favoritesProvider =
                            Provider.of<FavoritesProvider>(context,
                                listen: false);
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
                          '/login?returnTo=${Uri.encodeComponent('/profile')}');
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

    final favoritesProvider =
        Provider.of<FavoritesProvider>(context, listen: false);
    final success = await authProvider.deleteAccount();
    if (!context.mounted) return;

    if (success) {
      favoritesProvider.clearFavorites();
      context.go('/login');
      AppSnackBar.show(context, 'Compte supprimé', kind: SnackKind.success);
    } else {
      AppSnackBar.show(
          context, authProvider.error ?? 'Erreur lors de la suppression',
          kind: SnackKind.error);
    }
  }

  /// A6: the hand-rolled StatefulBuilder + gating + its own controller became
  /// three arguments — the ladder's top rung expressed as parameters.
  Future<bool> _confirmDeletion(BuildContext context) => showConfirmDialog(
        context,
        title: 'Supprimer mon compte',
        message: 'Cette action est définitive. Vos rendez-vous, favoris et '
            'avis seront supprimés. Pensez à exporter vos données avant.',
        confirmLabel: 'Supprimer définitivement',
        icon: Icons.warning_amber_rounded,
        confirmWord: 'SUPPRIMER',
      );
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  const _SettingsItem({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: AppTextStyles.bodyLarge.copyWith(color: color)),
      trailing: trailing ??
          const Icon(Icons.chevron_right, color: AppColors.textTertiary),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingM,
        vertical: AppTheme.spacingS,
      ),
    );
  }
}
