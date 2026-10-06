import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/pro_membership.dart';
import '../../../models/salon_subscription.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_subscription_provider.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';

/// « Mon abonnement » — the salon's CURRENT offer, read-only: its status
/// (trial / paid / grace / expired), its dates and its seats. Nothing else.
///
/// **The Pro app never sells** (App Store 3.1.3(f), « free stand-alone
/// companion app to a paid web based tool »): no plan choice, no other tier,
/// no price, no trial promotion, no entitlement list, and no pointer — web,
/// support, e-mail — to where an offer is obtained. This screen used to be the
/// offer picker; choosing now happens on the web, and the app never says so.
/// The salon's trial starts at its first publish, server-side, so a salon
/// never needs this screen to go live. Same on iOS and Android — there is no
/// platform branch to keep in step.
///
/// General help stays where every screen's help lives: Profil → « Aide &
/// Support ». Design: docs/design/pro-companion-path.md §2.2.
class ProSubscriptionScreen extends StatefulWidget {
  const ProSubscriptionScreen({super.key});

  @override
  State<ProSubscriptionScreen> createState() => _ProSubscriptionScreenState();
}

class _ProSubscriptionScreenState extends State<ProSubscriptionScreen> {
  /// The auth session loads asynchronously — fetch once the providerId
  /// materializes (build re-arms the request until it does).
  bool _loadRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoad());
  }

  void _maybeLoad() {
    if (_loadRequested || !mounted) return;
    final auth = context.read<ProAuthProvider>();
    final providerId = auth.activeSalonId;
    // R6: the gate is the CAPABILITY (a member has a salon id too).
    if (providerId == null || !auth.can(ProCap.subscriptionManage)) return;
    _loadRequested = true;
    context.read<ProSubscriptionProvider>().load(providerId);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
    final providerId = auth.activeSalonId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoad());
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Mon abonnement')),
      body: providerId == null || !auth.can(ProCap.subscriptionManage)
          ? const EmptyState(
              icon: Icons.workspace_premium_outlined,
              title: 'Réservé au propriétaire',
              description: 'L’offre du salon est gérée par son propriétaire.',
            )
          : Consumer<ProSubscriptionProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) return const LoadingIndicator();

                if (provider.loadFailed) {
                  return EmptyState(
                    icon: Icons.wifi_off,
                    title: 'Une erreur est survenue',
                    description: provider.error,
                    actionText: 'Réessayer',
                    onAction: () => provider.load(providerId),
                  );
                }

                // SETUP (no offer row — GET 404): a fact and when it changes,
                // nothing else. The trial starts when the salon goes live.
                if (provider.isSetup) {
                  return const EmptyState(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Pas encore d’offre active',
                    description:
                        'Votre offre démarre à la mise en ligne de votre '
                        'salon.',
                  );
                }

                final salon = provider.salon;
                // The first frame, before the post-frame load has started.
                if (salon == null) return const LoadingIndicator();
                return _Body(salon: salon);
              },
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.salon});

  final SalonSubscription salon;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        _StatusBanner(salon: salon),
        const SizedBox(height: AppTheme.spacingM),
        _SeatsBar(seats: salon.seats),
        const SizedBox(height: AppTheme.spacingM),
        // R6 multi-salons: a LIVE Réseau offer opens « Ajouter un salon ».
        // It states what the account can do with the offer it HAS — not
        // another offer, a trial or a price.
        if (salon.tier == SalonTier.reseau && salon.isLive) ...[
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.add_business_outlined,
                color: AppColors.textPrimary,
              ),
              title: const Text('Ajouter un salon'),
              subtitle: const Text('Un salon de plus dans votre compte.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/pro/salons/nouveau'),
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline,
              size: AppTheme.iconS,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: AppTheme.spacingS),
            Expanded(
              child: Text(
                'Vos données ne sont jamais bloquées.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Trial / paid / grace / expired — the salon's billing state, urgent in
/// colour when it needs to be (grace → amber, expired → red), and only ever
/// a statement: no button, no « where to pay ».
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.salon});

  final SalonSubscription salon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon, title, subtitle) = switch (salon.status) {
      SalonOfferStatus.trial => (
        AppColors.successLight.withValues(alpha: 0.12),
        AppColors.success,
        Icons.card_giftcard,
        'Essai gratuit — ${salon.trialDaysLeft} jour'
            '${salon.trialDaysLeft > 1 ? 's' : ''} restant'
            '${salon.trialDaysLeft > 1 ? 's' : ''}',
        'Offre ${salon.tierLabel} · se termine le '
            '${Formatters.formatDate(salon.trialEndsAt)}',
      ),
      // A paid row always carries `paidUntil`; without one the banner says
      // only what it knows (the old « Paiement à jour » fallback was dead).
      SalonOfferStatus.paid => (
        AppColors.successLight.withValues(alpha: 0.12),
        AppColors.success,
        Icons.verified,
        'Offre ${salon.tierLabel} active',
        salon.paidUntil == null
            ? null
            : 'Jusqu’au ${Formatters.formatDate(salon.paidUntil!)}',
      ),
      SalonOfferStatus.grace => (
        AppColors.warningLight.withValues(alpha: 0.16),
        AppColors.warning,
        Icons.warning_amber,
        'Votre offre a expiré',
        'Période de grâce jusqu’au '
            '${Formatters.formatDate(salon.graceEndsAt)}.',
      ),
      SalonOfferStatus.expired => (
        AppColors.error.withValues(alpha: 0.08),
        AppColors.error,
        Icons.error_outline,
        salon.unpublishedForBilling ? 'Salon dépublié' : 'Offre expirée',
        salon.unpublishedForBilling
            ? 'Votre salon n’est plus visible des clients. '
                  'Vos données sont intactes.'
            : 'Vos données sont intactes.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: AppTheme.spacingS),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(color: fg),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppTheme.spacingS),
            Text(
              subtitle,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeatsBar extends StatelessWidget {
  const _SeatsBar({required this.seats});

  final SalonSeats seats;

  @override
  Widget build(BuildContext context) {
    final ratio = seats.cap == 0 ? 0.0 : seats.used / seats.cap;
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.group_outlined,
                size: AppTheme.iconS,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppTheme.spacingS),
              // Expanded: at 200 % text on a 360dp phone the bare Text
              // overflowed this row by 71px (SYSTEM.md §13.3 — divide the
              // row, don't size the boxes).
              Expanded(
                child: Text(
                  '${seats.used} / ${seats.cap} places',
                  style: AppTextStyles.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingS),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
