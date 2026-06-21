import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../widgets/common/app_button.dart';

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
                const SizedBox(height: 24),
                // Avatar
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.surface,
                  child: Icon(
                    Icons.person,
                    size: 40,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 16),
                // Name
                Text(
                  user?.name ?? 'Utilisateur',
                  style: AppTextStyles.headlineMedium,
                ),
                const SizedBox(height: 8),
                // Phone
                Text(
                  user?.phoneNumber ?? '',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
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
                _SettingsItem(
                  icon: Icons.notifications,
                  title: 'Notifications',
                  trailing: Switch(
                    value: true,
                    onChanged: (value) {},
                  ),
                ),
                _SettingsItem(
                  icon: Icons.language,
                  title: 'Langue',
                  trailing: const Text('Français'),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fonctionnalité à venir')),
                    );
                  },
                ),
                _SettingsItem(
                  icon: Icons.help_outline,
                  title: 'Aide & Support',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fonctionnalité à venir')),
                    );
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
                const SizedBox(height: 32),
                // Logout Button (only show if authenticated)
                if (user != null)
                  AppButton(
                    text: 'Déconnexion',
                    type: AppButtonType.secondary,
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Déconnexion'),
                          content: const Text(
                              'Êtes-vous sûr de vouloir vous déconnecter ?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Annuler'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Déconnexion'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true && context.mounted) {
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
    if (confirmed != true || !context.mounted) return;

    final favoritesProvider =
        Provider.of<FavoritesProvider>(context, listen: false);
    final success = await authProvider.deleteAccount();
    if (!context.mounted) return;

    if (success) {
      favoritesProvider.clearFavorites();
      context.go('/login');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte supprimé')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.error ?? 'Erreur lors de la suppression'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<bool?> _confirmDeletion(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          final canDelete = controller.text.trim().toUpperCase() == 'SUPPRIMER';
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.error),
                SizedBox(width: 8),
                Expanded(child: Text('Supprimer mon compte')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cette action est définitive. Vos rendez-vous, favoris et '
                  'avis seront supprimés. Pensez à exporter vos données avant.',
                ),
                const SizedBox(height: 16),
                Text(
                  'Tapez SUPPRIMER pour confirmer',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setLocalState(() {}),
                  decoration: const InputDecoration(hintText: 'SUPPRIMER'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: canDelete ? () => Navigator.pop(ctx, true) : null,
                child: Text(
                  'Supprimer définitivement',
                  style: TextStyle(
                    color: canDelete ? AppColors.error : AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }
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
