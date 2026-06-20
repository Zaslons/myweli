import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/app_theme.dart';
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
                      context.go('/login?returnTo=${Uri.encodeComponent('/profile')}');
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
                        content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
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
                      final favoritesProvider = Provider.of<FavoritesProvider>(context, listen: false);
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
                      context.go('/login?returnTo=${Uri.encodeComponent('/profile')}');
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsItem({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(title, style: AppTextStyles.bodyLarge),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: AppColors.textTertiary),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingM,
        vertical: AppTheme.spacingS,
      ),
    );
  }
}



