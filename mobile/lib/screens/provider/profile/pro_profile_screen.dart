import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/salon_categories.dart';
import '../../../core/constants/unnamed_salon.dart';
import '../../../core/di/dependency_injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/external_link.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/team_error_messages.dart';
import '../../../models/pro_membership.dart';
import '../../../models/provider_user.dart';
import '../../../models/team_member.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_team_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_skeleton.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../../../widgets/provider/salon_picker_sheet.dart';
import '../../../widgets/team/team_role_chip.dart';

class ProProfileScreen extends StatefulWidget {
  const ProProfileScreen({super.key});

  @override
  State<ProProfileScreen> createState() => _ProProfileScreenState();
}

class _ProProfileScreenState extends State<ProProfileScreen> {
  /// R6: open the « Mes salons » switcher; route the add flow and the
  /// staff-shell reshape after a switch.
  Future<void> _openSalonPicker() async {
    final result = await showSalonPicker(context);
    if (!mounted || result == null) return;
    if (result == 'add') {
      unawaited(context.push('/pro/salons/nouveau'));
      return;
    }
    final auth = context.read<ProAuthProvider>();
    context.go(auth.isStaff ? '/pro/staff' : '/pro/dashboard');
  }

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
      appBar: AppBar(title: const Text('Profil')),
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
                            const SizedBox(height: AppTheme.spacingS),
                            Text(
                              provider.email!,
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppTheme.spacingM),
                          Text(
                            'Salon',
                            style: AppTextStyles.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacingS),
                          Text(
                            salonNameOr(
                              authProvider.knownSalonName,
                              kUnnamedSalon,
                            ),
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const _SalonCard(),
                const SizedBox(height: AppTheme.spacingM),
                // « Mes salons » (R6): every membership + the switcher — for
                // ALL roles (a member can belong to several salons too).
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.storefront),
                    title: const Text('Mes salons'),
                    subtitle: Text(
                      authProvider.hasMultipleSalons
                          ? '${authProvider.salons.length} salons — '
                                'actif : ${salonNameOr(authProvider.knownSalonName, kUnnamedSalon)}'
                          : salonNameOr(
                              authProvider.knownSalonName,
                              kUnnamedSalon,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openSalonPicker,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingM),
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
                  const SizedBox(height: AppTheme.spacingM),
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
                  const SizedBox(height: AppTheme.spacingM),
                ],
                if (authProvider.can(ProCap.salonPublish)) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Vérification'),
                      subtitle: Text(
                        _verificationLabel(provider.verificationStatus),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: _verificationColor(
                            provider.verificationStatus,
                          ),
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/verification'),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingM),
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
                  const SizedBox(height: AppTheme.spacingS),
                ],
                Consumer<ProTeamProvider>(
                  builder: (context, team, _) => team.invitationCount == 0
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppTheme.spacingS,
                          ),
                          child: Card(
                            child: ListTile(
                              leading: const Icon(Icons.mail_outline),
                              title: const Text('Invitations'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppTheme.spacingS,
                                      vertical: AppTheme.spacingXS,
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
                  const SizedBox(height: AppTheme.spacingS),
                ],
                if (authProvider.can(ProCap.depositManage)) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: const Text('Paramètres d’acompte'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/deposit-settings'),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
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
                  const SizedBox(height: AppTheme.spacingS),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.compare_outlined),
                      title: const Text('Avant / Après'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/pro/before-after'),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
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
                const SizedBox(height: AppTheme.spacingL),
                // L1 — legal is NOT capability-gated: every role, and a signed-out store
                // reviewer, must reach the privacy policy. Above « Déconnexion » so
                // `pro_profile_role_test`'s existing scroll ladder still reaches it.
                // Hand-written in this file's own `Card { ListTile }` idiom rather
                // than `SettingsTile`: its thirteen rows are all built this way, and
                // unifying them is a refactor that does not belong in a
                // store-submission change.
                // **The Pro app had no support affordance anywhere.** Its only
                // contact control lived on the subscription screen, three taps
                // in, and it opened a WhatsApp link that no build configures.
                // A salon with a problem had nowhere to go.
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Aide & Support'),
                    subtitle: const Text('Nous écrire'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openExternalUrl(context, AppConfig.supportUrl),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingM),

                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('À propos'),
                    subtitle: const Text(
                      'Confidentialité, CGU, mentions légales',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/a-propos'),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingM),

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
                const SizedBox(height: AppTheme.spacingSM),
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
  /// DELETE, map the two refusals the user can be told about
  /// (`future_bookings`, `demo_account_locked`), then sign out.
  ///
  /// The entry is offered to EVERY account, the shared App Review demo
  /// account included: the reviewer has to see that deletion exists. The
  /// server refuses that one account after the confirmation, and the user
  /// stays signed in — nothing local is cleared on a refusal.
  /// Design: docs/design/demo-account-deletion-lock.md §7.1.
  Future<void> _deleteAccount(
    BuildContext context,
    ProAuthProvider authProvider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Supprimer votre compte ?',
      // What the server will do (B7.3): an owner's salons go, a member's
      // account only — docs/design/pro-app-batch7.md §2.3.
      message: authProvider.ownsASalon
          ? 'Cette action est définitive. Votre salon sera retiré de '
                'MyWeli. Pensez à exporter vos données avant.'
          : 'Cette action est définitive. Votre compte MyWeli Pro sera '
                'supprimé.',
      confirmLabel: 'Supprimer définitivement',
      icon: Icons.warning_amber_rounded,
      // A6 closes the ladder's asymmetry: the CONSUMER account delete has
      // asked you to type SUPPRIMER since it shipped, while the PRO salon
      // delete — the same irreversible + high-value rung, and a whole salon —
      // asked for one tap. §15 says both get type-to-confirm.
      confirmWord: 'SUPPRIMER',
    );
    if (!confirmed || !context.mounted) return;

    final res = await serviceLocator.proService.deleteProviderAccount();
    if (!res.success) {
      AppSnackBar.showOn(
        messenger,
        // Keyed on the CODE, never on the service's message: the sentence
        // must be the same whichever backend answered.
        switch (res.code) {
          'future_bookings' =>
            'Terminez ou annulez vos rendez-vous à venir avant de '
                'supprimer votre compte.',
          'demo_account_locked' => demoAccountLockedMessage,
          _ => res.error ?? 'La suppression a échoué.',
        },
        kind: SnackKind.error,
      );
      return;
    }
    await authProvider.logout();
    router.go('/pro/login');
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

/// The owner's card — the ACTING salon (R6), read from `salonFacts`: the
/// `GET /me/provider` salon payload, else the copy the session kept of it, so
/// an offline cold start still shows the salon (product-questions-batch8.md
/// §2.3, B8.3). Never the account's `businessName` & co.: those are a copy
/// made at sign-up, of the default salon, and never updated
/// (docs/design/r6-salon-fact-reads.md §2.1).
class _SalonCard extends StatefulWidget {
  const _SalonCard();

  @override
  State<_SalonCard> createState() => _SalonCardState();
}

class _SalonCardState extends State<_SalonCard> {
  /// « Réessayer » in flight — `refreshMembership` raises no `isLoading`
  /// (only the cold start and a switch do), so the card keeps its own.
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await context.read<ProAuthProvider>().refreshMembership();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
    // Live, or the kept copy — for the acting salon only (B8.3).
    final salon = auth.salonFacts;
    final category = salon == null ? null : salonCategoryLabel(salon.category);
    final rows = <Widget>[
      // The membership's name is cached in the session: known before the
      // salon payload lands, and offline.
      _fact(
        'Nom du salon',
        salonNameOr(
          salon?.name,
          salonNameOr(auth.knownSalonName, kUnnamedSalon),
        ),
      ),
      if (salon != null) ...[
        if (category != null) _fact('Catégorie', category),
        if (salon.address.trim().isNotEmpty) _fact('Adresse', salon.address),
        if (salon.phoneNumber.trim().isNotEmpty)
          _fact('Téléphone', Formatters.formatPhoneNumber(salon.phoneNumber)),
      ] else if (auth.isLoading || _retrying)
        _skeleton()
      else
        _unavailable(),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) const SizedBox(height: AppTheme.spacingM),
              row,
            ],
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
      ),
      const SizedBox(height: AppTheme.spacingS),
      Text(
        value,
        style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
      ),
    ],
  );

  /// The rows' shape while the salon payload is on its way (§12: the shape is
  /// known, so a skeleton, not a spinner). One label for screen readers. The
  /// idiom the shared skeletons were cut from (B9.8).
  Widget _skeleton() => AppSkeleton(
    label: 'Chargement des informations du salon',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, width) in const [0.45, 0.7, 0.5].indexed) ...[
          if (i > 0) const SizedBox(height: AppTheme.spacingM),
          const SkeletonBar(widthFactor: 0.3),
          const SizedBox(height: AppTheme.spacingS),
          SkeletonBar(widthFactor: width),
        ],
      ],
    ),
  );

  /// Offline cold start with no copy kept (a session from before B8.3, or
  /// one that never loaded this salon), or the probe failed: say so, and
  /// offer the retry — one that can succeed once the network is back (§12).
  Widget _unavailable() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Les informations du salon n’ont pas pu être chargées. '
        'Vérifiez votre connexion.',
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppTheme.spacingS),
      AppButton(
        text: 'Réessayer',
        type: AppButtonType.text,
        isFullWidth: false,
        onPressed: _retry,
      ),
    ],
  );
}
