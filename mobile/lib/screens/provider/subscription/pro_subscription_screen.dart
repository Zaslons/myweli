import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/subscription_plans.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/pro_membership.dart';
import '../../../models/salon_subscription.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_subscription_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';

/// « Mon abonnement » — the offer picker + billing states (pricing pivot,
/// team access R3). Setup (no offer) → the 3-card picker with « 3 mois
/// offerts »; then trial/paid/grace/expired states, the seats bar and the
/// manual-payment contact path (« Nous contacter », no custody).
/// Design: docs/design/team-access-r3-app.md §2.4.
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

  Future<void> _contact([String? message]) async {
    final messenger = ScaffoldMessenger.of(context);
    final number = AppConfig.supportWhatsApp;
    if (number.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Contact bientôt disponible.')),
      );
      return;
    }
    final text = message ??
        'Bonjour Myweli, je souhaite activer mon offre pour mon salon.';
    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(text)}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir WhatsApp.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _choose(String providerId, SalonTier tier) async {
    final provider = context.read<ProSubscriptionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final wasSetup = provider.isSetup;
    final ok = await provider.choose(providerId, tier);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            wasSetup
                ? 'Offre ${salonTierLabel(tier)} choisie — '
                    '${SubscriptionPlans.trialMonths} mois offerts !'
                : 'Vous êtes maintenant sur l\'offre '
                    '${salonTierLabel(tier)}.',
          ),
        ),
      );
    } else if (provider.chooseErrorCode != 'trial_used') {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.chooseError ?? 'Choix impossible.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
              description: 'L\'offre du salon est gérée par son propriétaire.',
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

                return _Body(
                  provider: provider,
                  onChoose: (tier) => _choose(providerId, tier),
                  onContact: _contact,
                );
              },
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.provider,
    required this.onChoose,
    required this.onContact,
  });

  final ProSubscriptionProvider provider;
  final ValueChanged<SalonTier> onChoose;
  final Future<void> Function([String? message]) onContact;

  @override
  Widget build(BuildContext context) {
    final salon = provider.salon;
    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        if (provider.isSetup) ...[
          Text(
            'Choisissez votre offre — '
            '${SubscriptionPlans.trialMonths} mois offerts',
            style: AppTextStyles.headlineSmall,
          ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Votre salon reste gratuit pendant la configuration, mais une '
            'offre est nécessaire pour le publier.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
        ] else if (salon != null) ...[
          _StatusBanner(salon: salon, onContact: onContact),
          const SizedBox(height: AppTheme.spacingM),
          _SeatsBar(seats: salon.seats),
          const SizedBox(height: AppTheme.spacingM),
          // R6 multi-salons: a LIVE Réseau offer opens « Ajouter un salon »
          // (each new salon = its own setup, offer, trial & publish gate).
          if (salon.tier == SalonTier.reseau && salon.isLive) ...[
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.add_business_outlined,
                  color: AppColors.textPrimary,
                ),
                title: const Text('Ajouter un salon'),
                subtitle: const Text(
                  'Chaque salon a sa propre offre et son propre essai.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/pro/salons/nouveau'),
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
          ],
        ],
        if (provider.chooseErrorCode == 'trial_used') ...[
          _TrialUsedNotice(onContact: onContact),
          const SizedBox(height: AppTheme.spacingM),
        ],
        for (final tier in SalonTier.values) ...[
          _OfferCard(
            tier: tier,
            current: salon?.tier == tier && !provider.isSetup,
            isSetup: provider.isSetup,
            busy: provider.isChoosing,
            onChoose: () => onChoose(tier),
          ),
          const SizedBox(height: AppTheme.spacingM),
        ],
        if (!provider.isSetup && salon != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
            child: Text(
              'Le changement d\'offre conserve votre période d\'essai.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline,
                size: 18, color: AppColors.textTertiary),
            const SizedBox(width: AppTheme.spacingS),
            Expanded(
              child: Text(
                'Le paiement se fait manuellement — contactez-nous à la fin '
                'de votre période d\'essai. Vos données ne sont jamais '
                'bloquées.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingM),
        AppButton(
          text: 'Nous contacter',
          type: AppButtonType.secondary,
          onPressed: () => onContact(),
        ),
      ],
    );
  }
}

/// Trial / paid / grace / expired — the salon's billing state, urgent when
/// it needs to be (grace → amber, unpublished → red).
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.salon, required this.onContact});

  final SalonSubscription salon;
  final Future<void> Function([String? message]) onContact;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon, title, subtitle, urgent) = switch (salon.status) {
      SalonOfferStatus.trial => (
          AppColors.successLight.withValues(alpha: 0.12),
          AppColors.success,
          Icons.card_giftcard,
          'Essai gratuit — ${salon.trialDaysLeft} jour'
              '${salon.trialDaysLeft > 1 ? 's' : ''} restant'
              '${salon.trialDaysLeft > 1 ? 's' : ''}',
          'Offre ${salon.tierLabel} · se termine le '
              '${Formatters.formatDate(salon.trialEndsAt)}',
          false,
        ),
      SalonOfferStatus.paid => (
          AppColors.successLight.withValues(alpha: 0.12),
          AppColors.success,
          Icons.verified,
          'Offre ${salon.tierLabel} active',
          salon.paidUntil != null
              ? 'Jusqu\'au ${Formatters.formatDate(salon.paidUntil!)}'
              : 'Paiement à jour',
          false,
        ),
      SalonOfferStatus.grace => (
          AppColors.warningLight.withValues(alpha: 0.16),
          AppColors.warning,
          Icons.warning_amber,
          'Votre offre a expiré',
          'Jusqu\'au ${Formatters.formatDate(salon.graceEndsAt)} avant la '
              'dépublication de votre salon. Contactez-nous pour régler.',
          true,
        ),
      SalonOfferStatus.expired => (
          AppColors.error.withValues(alpha: 0.08),
          AppColors.error,
          Icons.error_outline,
          salon.unpublishedForBilling ? 'Salon dépublié' : 'Offre expirée',
          salon.unpublishedForBilling
              ? 'Votre salon n\'est plus visible des clients. '
                  'Contactez-nous pour réactiver — vos données sont '
                  'intactes.'
              : 'Contactez-nous pour réactiver votre offre.',
          true,
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
          const SizedBox(height: AppTheme.spacingS),
          Text(
            subtitle,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (urgent) ...[
            const SizedBox(height: AppTheme.spacingM),
            AppButton(
              text: 'Nous contacter',
              onPressed: () => onContact(
                'Bonjour Myweli, je souhaite régler mon offre pour '
                'réactiver mon salon.',
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
              const Icon(Icons.group_outlined,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: AppTheme.spacingS),
              Text(
                '${seats.used} / ${seats.cap} places',
                style: AppTextStyles.titleSmall,
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
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrialUsedNotice extends StatelessWidget {
  const _TrialUsedNotice({required this.onContact});

  final Future<void> Function([String? message]) onContact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.warningLight.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Votre essai gratuit a déjà été utilisé.',
            style: AppTextStyles.titleSmall.copyWith(color: AppColors.warning),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Contactez-nous pour activer votre offre.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          AppButton(
            text: 'Nous contacter',
            type: AppButtonType.secondary,
            onPressed: () => onContact(
              'Bonjour Myweli, mon essai est terminé — je souhaite activer '
              'mon offre.',
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.tier,
    required this.current,
    required this.isSetup,
    required this.busy,
    required this.onChoose,
  });

  final SalonTier tier;
  final bool current;
  final bool isSetup;
  final bool busy;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final anchor = switch (tier) {
      SalonTier.pro => SubscriptionPlans.proAnchorMonthlyFcfa,
      SalonTier.business => SubscriptionPlans.businessAnchorMonthlyFcfa,
      SalonTier.reseau => null,
    };
    final seatsLine = switch (tier) {
      SalonTier.pro => '${SubscriptionPlans.proSeats} places',
      SalonTier.business => '${SubscriptionPlans.businessSeats} places',
      SalonTier.reseau =>
        '${SubscriptionPlans.reseauSeatsPerSalon} places par salon',
    };

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        border: Border.all(
          color: current ? AppColors.primary : AppColors.border,
          width: current ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  salonTierLabel(tier),
                  style: AppTextStyles.titleLarge,
                ),
              ),
              if (current)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingS,
                    vertical: AppTheme.spacingXS,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Text(
                    'Votre offre',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingS),
          if (anchor != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  // PLATFORM billing — Myweli invoices in XOF regardless
                  // of the salon's market (multi-pays §4).
                  Formatters.formatCurrency(anchor.toDouble()),
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textTertiary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: AppTheme.spacingS),
                Text(
                  '/mois',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            )
          else
            Text('Sur devis', style: AppTextStyles.titleMedium),
          Text(
            '${SubscriptionPlans.trialMonths} mois offerts',
            style: AppTextStyles.titleSmall.copyWith(
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Row(
            children: [
              const Icon(Icons.group_outlined,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: AppTheme.spacingS),
              Text(
                seatsLine,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingM),
          for (final line in SubscriptionPlans.entitlementsFor(tier))
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, size: 16, color: AppColors.success),
                  const SizedBox(width: AppTheme.spacingS),
                  Expanded(
                    child: Text(
                      line,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (tier == SalonTier.pro) ...[
            const SizedBox(height: AppTheme.spacingS),
            Text(
              SubscriptionPlans.roiLine,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (!current) ...[
            const SizedBox(height: AppTheme.spacingM),
            AppButton(
              text: isSetup ? 'Choisir' : 'Changer d\'offre',
              type: isSetup ? AppButtonType.primary : AppButtonType.secondary,
              isLoading: busy,
              isFullWidth: true,
              onPressed: busy ? null : onChoose,
            ),
          ],
        ],
      ),
    );
  }
}
