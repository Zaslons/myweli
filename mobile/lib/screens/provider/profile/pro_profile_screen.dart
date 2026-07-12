import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/pro_membership.dart';
import '../../../models/provider_user.dart';
import '../../../models/team_member.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_team_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/team/team_role_chip.dart';

class ProProfileScreen extends StatefulWidget {
  const ProProfileScreen({super.key});

  @override
  State<ProProfileScreen> createState() => _ProProfileScreenState();
}

class _ProProfileScreenState extends State<ProProfileScreen> {
  @override
  void initState() {
    super.initState();
    // The « Invitations » row only appears when the identity has pending
    // team invitations (module access R3).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ProTeamProvider>().loadMyInvitations(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profil'),
      ),
      body: Consumer<ProAuthProvider>(
        builder: (context, authProvider, _) {
          if (!authProvider.isAuthenticated || authProvider.provider == null) {
            return const Center(child: Text('Veuillez vous connecter'));
          }

          final provider = authProvider.provider!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (authProvider.role != TeamRole.owner)
                  // Member header (access R4b): a personal card — the salon
                  // is not theirs to edit.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingM),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (provider.name?.isNotEmpty ?? false)
                                      ? provider.name!
                                      : (provider.email ?? ''),
                                  style: AppTextStyles.titleMedium.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TeamRoleChip(role: authProvider.role),
                            ],
                          ),
                          if (provider.email != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              provider.email!,
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Salon',
                            style: AppTextStyles.titleMedium
                                .copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            authProvider.salonName,
                            style: AppTextStyles.bodyLarge
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingM),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nom de l\'entreprise',
                            style: AppTextStyles.titleMedium
                                .copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            provider.businessName,
                            style: AppTextStyles.bodyLarge
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Type d\'entreprise',
                            style: AppTextStyles.titleMedium
                                .copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getBusinessTypeLabel(provider.businessType),
                            style: AppTextStyles.bodyLarge
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          if (provider.address != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Adresse',
                              style: AppTextStyles.titleMedium
                                  .copyWith(color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              provider.address!,
                              style: AppTextStyles.bodyLarge
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Téléphone',
                            style: AppTextStyles.titleMedium
                                .copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            provider.phoneNumber,
                            style: AppTextStyles.bodyLarge
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // Role-gated rows (access R4b) — UI hiding is convenience;
                // the routes 403 server-side regardless.
                if (authProvider.can(ProCap.salonPublish)) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.checklist_rounded),
                      title: const Text('Configurer mon profil'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/onboarding'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (authProvider.can(ProCap.profileManage)) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: const Text('Profil du salon'),
                      subtitle: const Text('Infos publiques, catégorie, carte'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/salon-profile'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (authProvider.can(ProCap.salonPublish)) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Vérification'),
                      subtitle: Text(
                        _verificationLabel(provider.verificationStatus),
                        style: AppTextStyles.bodySmall.copyWith(
                          color:
                              _verificationColor(provider.verificationStatus),
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/verification'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (authProvider.can(ProCap.membersManage)) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.group_outlined),
                      title: const Text('Équipe'),
                      subtitle: const Text('Invitez et gérez vos accès'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/team'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Consumer<ProTeamProvider>(
                  builder: (context, team, _) => team.invitationCount == 0
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              leading: const Icon(Icons.mail_outline),
                              title: const Text('Invitations'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.radiusSmall,
                                      ),
                                    ),
                                    child: Text(
                                      '${team.invitationCount}',
                                      style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.secondary,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () => context.push('/pro/invitations'),
                            ),
                          ),
                        ),
                ),
                if (authProvider.can(ProCap.subscriptionManage)) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: const Text('Mon abonnement'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/subscription'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (authProvider.can(ProCap.depositManage)) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: const Text('Paramètres d\'acompte'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/deposit-settings'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (authProvider.can(ProCap.catalogueManage)) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('Photos du salon'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/photos'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.compare_outlined),
                      title: const Text('Avant / Après'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/before-after'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (authProvider.can(ProCap.salonPublish))
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('Mes données'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/data-export'),
                    ),
                  ),
                const SizedBox(height: 24),
                AppButton(
                  text: 'Déconnexion',
                  type: AppButtonType.secondary,
                  onPressed: () async {
                    await authProvider.logout();
                    if (context.mounted) {
                      context.go('/pro/login');
                    }
                  },
                ),
                const SizedBox(height: 12),
                // Audit 11.5 (AUTH-004 pros): definitive account deletion.
                AppButton(
                  text: 'Supprimer mon compte',
                  type: AppButtonType.text,
                  onPressed: () => _deleteAccount(context, authProvider),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Double-confirm deletion (audit 11.5): warn, call the self-scoped
  /// DELETE, map `future_bookings`, then sign out.
  Future<void> _deleteAccount(
    BuildContext context,
    ProAuthProvider authProvider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer votre compte ?'),
        content: const Text(
          'Cette action est définitive. Votre salon sera retiré de MyWeli. '
          'Pensez à exporter vos données avant.',
        ),
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
    if (confirmed != true || !context.mounted) return;

    final res = await serviceLocator.proService.deleteProviderAccount();
    if (!res.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            res.code == 'future_bookings'
                ? 'Terminez ou annulez vos rendez-vous à venir avant de '
                    'supprimer votre compte.'
                : res.error ?? 'La suppression a échoué. Réessayez.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    await authProvider.logout();
    router.go('/pro/login');
  }

  String _getBusinessTypeLabel(BusinessType type) {
    switch (type) {
      case BusinessType.salon:
        return 'Salon de beauté';
      case BusinessType.barber:
        return 'Barbier';
      case BusinessType.spa:
        return 'Spa';
      case BusinessType.nailSalon:
        return 'Institut de manucure';
      case BusinessType.massage:
        return 'Massage';
      case BusinessType.other:
        return 'Autre';
    }
  }

  String _verificationLabel(VerificationStatus status) {
    switch (status) {
      case VerificationStatus.pending:
        return 'En attente de vérification';
      case VerificationStatus.verified:
        return 'Compte vérifié';
      case VerificationStatus.rejected:
        return 'Vérification refusée';
    }
  }

  Color _verificationColor(VerificationStatus status) {
    switch (status) {
      case VerificationStatus.pending:
        return AppColors.warning;
      case VerificationStatus.verified:
        return AppColors.success;
      case VerificationStatus.rejected:
        return AppColors.error;
    }
  }
}
