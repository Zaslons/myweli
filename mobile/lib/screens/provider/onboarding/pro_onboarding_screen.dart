import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/failure_messages.dart';
import '../../../core/constants/salon_validation_copy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/onboarding.dart';
import '../../../core/utils/salon_id.dart';
import '../../../core/utils/team_error_messages.dart';
import '../../../models/provider_user.dart';
import '../../../providers/locality_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_onboarding_provider.dart';
import '../../../widgets/common/app_async_view.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/common/app_skeleton.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/screen_title.dart';

class ProOnboardingScreen extends StatefulWidget {
  const ProOnboardingScreen({super.key});

  @override
  State<ProOnboardingScreen> createState() => _ProOnboardingScreenState();
}

class _ProOnboardingScreenState extends State<ProOnboardingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<ProAuthProvider>();
      final pro = auth.provider;
      if (pro != null) _load(pro, auth.activeSalonId);
    });
  }

  /// The checklist's six reads, and — beside them, on its own clock —
  /// MyWeli's area tree for R8 (a commune typed by hand that names none of
  /// its areas). The tree is a nullable lookup: absent from the widget tree,
  /// unread or failed, the profile step keeps today's three-field rule and
  /// the server decides (docs/design/salon-go-live-approval.md §6.3).
  void _load(ProviderUser pro, SalonId? salonId) {
    final areas = context.read<LocalityProvider?>();
    if (areas != null) unawaited(areas.ensureLoaded());
    context.read<ProOnboardingProvider>().load(
      pro,
      salonId: salonId,
      areas: areas,
    );
  }

  Future<void> _goLive() async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<ProAuthProvider>();
    final providerId = auth.activeSalonId ?? SalonId.none;
    final onboarding = context.read<ProOnboardingProvider>();
    // The provider re-reads the session's copies of the state (the home
    // card, « Mes salons ») after the answer — the one place it is done.
    final outcome = await onboarding.publish(providerId, session: auth);
    if (!mounted) return;
    if (outcome != null) {
      // « 🎉 » for a 200 only: a 202 is a request, the salon still a draft
      // (B0.18 §6.1). And a 202 MyWeli refused at that very moment, or whose
      // request vanished, says nothing — the screen shows the state
      // (decision 136 item 7).
      final said = outcome.isLive
          ? SalonValidationCopy.wentLive
          : outcome.saysRequestSent
          ? SalonValidationCopy.requestSent
          : null;
      if (said != null) {
        AppSnackBar.showOn(messenger, said, kind: SnackKind.success);
      }
      return;
    }
    // A salon with no offer row is never refused for it (its trial starts
    // when MyWeli validates it), so `offer_required` means the salon's offer
    // EXPIRED. The bar states that and carries NO action: it used to open the
    // offer picker (« Choisir »), which the Pro app no longer has (App Store
    // 3.1.1 — docs/design/pro-companion-path.md §2.2). Any other refusal —
    // the demo account's lock, a final refusal's « Mise en ligne refusée »
    // (decision 136 item 2) included — shows the service's sentence.
    final offerInactive = onboarding.publishErrorCode == 'offer_required';
    AppSnackBar.showOn(
      messenger,
      offerInactive
          ? publishOfferInactiveMessage
          : (onboarding.error ?? 'La mise en ligne a échoué'),
      kind: SnackKind.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // The BAR names the screen; the two rows that open it keep the verb
      // phrase — a `SettingsTile` has the width to say « Configurer mon
      // profil » and a 280dp bar does not (A15, §13.3). Same move as
      // « Préférences » / « Préférences de notification ».
      appBar: AppBar(title: const ScreenTitle('Configuration')),
      body: Consumer2<ProAuthProvider, ProOnboardingProvider>(
        builder: (context, auth, onboarding, _) {
          final pro = auth.provider;
          if (pro == null) {
            return const Center(child: Text('Veuillez vous connecter'));
          }
          return AppAsyncView<ProOnboardingProvider>(
            isLoading: onboarding.isLoading,
            error: onboarding.loadFailed
                ? onboarding.error ?? kGenericErrorMessage
                : null,
            // Only a settled read: its actions change what it shows.
            data:
                onboarding.loaded &&
                    !onboarding.isLoading &&
                    !onboarding.loadFailed
                ? onboarding
                : null,
            isEmpty: (_) => false,
            loading: const SkeletonTileList(count: 7),
            empty: const SizedBox.shrink(),
            onRetry: () => _load(pro, auth.activeSalonId),
            builder: (context, o) => _buildList(o),
          );
        },
      ),
    );
  }

  Widget _buildList(ProOnboardingProvider onboarding) {
    final progress = onboarding.progress;
    final ratio = progress.total == 0 ? 0.0 : progress.done / progress.total;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        Text(
          '${Formatters.count(progress.done, 'étape', 'étapes')} sur '
          '${progress.total} '
          '${Formatters.plural(progress.done, 'terminée', 'terminées')}',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingS),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: AppColors.surface,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        const SizedBox(height: AppTheme.spacingL),
        for (final step in onboarding.steps)
          _StepRow(
            step: step,
            communeFromList:
                step.key == OnboardingStepKey.profile &&
                onboarding.communeNotInList,
          ),
        const SizedBox(height: AppTheme.spacingL),
        // See the salon exactly as a client will, before going live (B5).
        OutlinedButton(
          onPressed: () => context.push('/pro/apercu'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.borderStrong),
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingM),
          ),
          child: const Text('Aperçu de ma page'),
        ),
        const SizedBox(height: AppTheme.spacingS),
        AppButton(
          text: 'Mettre mon profil en ligne',
          isLoading: onboarding.isPublishing,
          onPressed: onboarding.readyToGoLive ? _goLive : null,
        ),
        if (!onboarding.readyToGoLive) ...[
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Complétez les étapes essentielles pour mettre votre profil en ligne.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final OnboardingStep step;

  /// R8 (decision 136 item 4): the profile is filled, and its commune is
  /// the one thing the server would refuse.
  final bool communeFromList;

  const _StepRow({required this.step, this.communeFromList = false});

  @override
  Widget build(BuildContext context) {
    final route = _route(step.key);
    final sublabel = _sublabel(step);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(
            _statusIcon(step.status),
            color: _statusColor(step.status),
          ),
          title: Text(_label(step.key)),
          subtitle: sublabel == null ? null : Text(sublabel),
          trailing: route != null
              ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
              : Text(
                  _statusText(step.status),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: _statusColor(step.status),
                  ),
                ),
          onTap: route == null ? null : () => context.push(route),
        ),
      ),
    );
  }

  String _label(OnboardingStepKey key) {
    switch (key) {
      case OnboardingStepKey.profile:
        return 'Profil de l’entreprise';
      case OnboardingStepKey.location:
        return 'Position sur la carte';
      case OnboardingStepKey.services:
        return 'Services (3 minimum)';
      case OnboardingStepKey.staff:
        return 'Équipe';
      case OnboardingStepKey.availability:
        return 'Disponibilités';
      case OnboardingStepKey.deposit:
        return 'Acompte & annulation';
      case OnboardingStepKey.verification:
        return 'Vérification (KYC)';
      case OnboardingStepKey.photos:
        return 'Photos (3 minimum)';
    }
  }

  String? _route(OnboardingStepKey key) {
    switch (key) {
      case OnboardingStepKey.profile:
        return '/pro/salon-profile';
      case OnboardingStepKey.location:
        return '/pro/salon-profile';
      case OnboardingStepKey.services:
        return '/pro/services';
      case OnboardingStepKey.staff:
        return '/pro/artists';
      case OnboardingStepKey.availability:
        return '/pro/availability';
      case OnboardingStepKey.deposit:
        return '/pro/deposit-settings';
      case OnboardingStepKey.verification:
        return '/pro/verification';
      case OnboardingStepKey.photos:
        return '/pro/photos';
    }
  }

  String? _sublabel(OnboardingStep step) {
    if (communeFromList) return SalonValidationCopy.communeFromList;
    if (step.key == OnboardingStepKey.staff &&
        step.status == OnboardingStepStatus.optional) {
      return 'Optionnel pour les indépendants';
    }
    if (step.key == OnboardingStepKey.photos) {
      return 'Ajouter des photos du salon';
    }
    // B7.7 — until a choice is saved (docs/design/pro-app-batch7.md §2.7).
    if (step.key == OnboardingStepKey.deposit &&
        step.status == OnboardingStepStatus.optional) {
      return 'Facultatif';
    }
    if (step.status == OnboardingStepStatus.inProgress) {
      return 'En cours';
    }
    return null;
  }

  String _statusText(OnboardingStepStatus status) {
    switch (status) {
      case OnboardingStepStatus.done:
        return 'Fait';
      case OnboardingStepStatus.inProgress:
        return 'En cours';
      case OnboardingStepStatus.optional:
        return 'À venir';
      case OnboardingStepStatus.todo:
        return 'À faire';
    }
  }

  IconData _statusIcon(OnboardingStepStatus status) {
    switch (status) {
      case OnboardingStepStatus.done:
        return Icons.check_circle;
      case OnboardingStepStatus.inProgress:
        return Icons.schedule;
      case OnboardingStepStatus.optional:
      case OnboardingStepStatus.todo:
        return Icons.circle_outlined;
    }
  }

  Color _statusColor(OnboardingStepStatus status) {
    switch (status) {
      case OnboardingStepStatus.done:
        return AppColors.success;
      case OnboardingStepStatus.inProgress:
        return AppColors.warning;
      case OnboardingStepStatus.optional:
      case OnboardingStepStatus.todo:
        return AppColors.textTertiary;
    }
  }
}
