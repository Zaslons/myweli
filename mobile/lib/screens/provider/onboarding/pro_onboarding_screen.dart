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
import '../../../core/utils/salon_go_live.dart';
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
import '../../../widgets/common/status_banner.dart';

class ProOnboardingScreen extends StatefulWidget {
  const ProOnboardingScreen({super.key, this.salonId});

  /// The salon a notice names (`/pro/onboarding?salon={id}` — MyWeli's
  /// decision on it, B0.18 salon-go-live-approval §5.2, §6.2). Null → the
  /// acting salon.
  final SalonId? salonId;

  @override
  State<ProOnboardingScreen> createState() => _ProOnboardingScreenState();
}

class _ProOnboardingScreenState extends State<ProOnboardingScreen> {
  /// The notice's switch has been asked — ONCE for this screen, whatever it
  /// answered (web-salon-validation.md §4.5 found the loop: a server that
  /// answers the switch but keeps the old salon pulled the page back to
  /// switching again).
  bool _switchAsked = false;

  /// The notice's switch is out.
  bool _switching = false;

  /// Nothing of a salon on screen until the notice's switch has answered:
  /// the checklist's store is the app's, and may still hold the salon the
  /// owner was on — its state would show under the notice about the other.
  bool _awaitingSwitch(ProAuthProvider auth) {
    final wanted = widget.salonId;
    return _switching ||
        (wanted != null && !_switchAsked && wanted != auth.activeSalonId);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  /// A notice about another of the account's salons switches to it first
  /// (§6.2), and checks the answer — the booking detail ignores it, and is
  /// not copied: a switch that did not happen goes to « Accueil » and says
  /// why, in the salon picker's words (decision 136 item 3). Both ways in
  /// arrive here unswitched — the feed row, and a tapped push, whose handler
  /// leaves this route's switch to this screen
  /// (`ProRouter.switchesSalonItself`). Already on that salon: nothing to
  /// switch.
  Future<void> _enter() async {
    if (!mounted) return;
    final auth = context.read<ProAuthProvider>();
    final wanted = widget.salonId;
    if (wanted != null && !_switchAsked && wanted != auth.activeSalonId) {
      _switchAsked = true;
      setState(() => _switching = true);
      final messenger = ScaffoldMessenger.of(context);
      final router = GoRouter.maybeOf(context);
      final outcome = await auth.switchSalonOutcome(wanted);
      if (!mounted) return;
      // « Switched » to a salon the answer does not describe — a server that
      // kept the old one — is no switch either, and is said once.
      final landed = auth.activeSalon?.id == wanted;
      if (outcome != SalonSwitchOutcome.switched || !landed) {
        // The page leaves on its skeleton (`_switching` stays true): a
        // refused or offline switch reset nothing, so the store still holds
        // the salon the owner stayed on — never shown under this notice,
        // not for the frames of the page's way out either.
        router?.go(auth.isStaff ? '/pro/staff' : '/pro/dashboard');
        AppSnackBar.showOn(
          messenger,
          outcome == SalonSwitchOutcome.offline
              ? kNoConnectionMessage
              : salonSwitchRefusedMessage,
          kind: SnackKind.error,
        );
        return;
      }
      setState(() => _switching = false);
    }
    final pro = auth.provider;
    if (pro != null) unawaited(_load(pro, auth.activeSalonId));
  }

  /// The checklist's six reads, and — beside them, on its own clock —
  /// MyWeli's area tree for R8 (a commune typed by hand that names none of
  /// its areas). The tree is a nullable lookup: absent from the widget tree,
  /// unread or failed, the profile step keeps today's three-field rule and
  /// the server decides (docs/design/salon-go-live-approval.md §6.3).
  ///
  /// « Configuration » loading is one of §6.2's refresh points for the
  /// session's two copies of the salon's state: « Mes salons » is re-read
  /// (its rows say the state), and the home card's copy only when this
  /// screen's own GET /me/provider says something else — MyWeli decided
  /// since, or the card never knew (an offline cold start). No second
  /// /me/provider when the two agree.
  Future<void> _load(ProviderUser pro, SalonId? salonId) async {
    final auth = context.read<ProAuthProvider>();
    final onboarding = context.read<ProOnboardingProvider>();
    final areas = context.read<LocalityProvider?>();
    if (areas != null) unawaited(areas.ensureLoaded());
    unawaited(auth.loadMySalons());
    await onboarding.load(pro, salonId: salonId, areas: areas);
    if (!mounted) return;
    final read = onboarding.salonGoLiveState;
    if (read != null &&
        auth.activeSalonId == salonId &&
        read != auth.salonGoLiveState) {
      unawaited(auth.refreshMembership());
    }
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
          if (_awaitingSwitch(auth)) return const SkeletonTileList(count: 7);
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
            builder: (context, o) => _buildList(o, auth),
          );
        },
      ),
    );
  }

  Widget _buildList(ProOnboardingProvider onboarding, ProAuthProvider auth) {
    // Not read yet, no salon to read, or a server from before B0.18 (no
    // `validation` key — decision 136 item 10): today's screen and words.
    final state = onboarding.salonGoLiveState ?? GoLiveState.legacy;
    final banner = goLiveBanner(state, onboarding.validation);
    final progress = onboarding.progress;
    final ratio = progress.total == 0 ? 0.0 : progress.done / progress.total;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        // Above the steps, the KYC banner's pattern (§6.2).
        if (banner != null) _GoLiveStatusBanner(banner),
        // Suspended: the banner alone — no checklist, no button; MyWeli's
        // restore decides (decision 136 item 9, as the website).
        if (state != GoLiveState.suspended) ...[
          if (banner != null) const SizedBox(height: AppTheme.spacingL),
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
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingL),
          // Every step stays editable in every state — a request waiting
          // included: MyWeli reads the salon as it is when it decides (§6.2).
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
          ..._action(state, onboarding, auth),
        ],
      ],
    );
  }

  /// The state's action under « Aperçu de ma page » (§6.1 « Button »): the
  /// publish under the state's own name, enabled when the checklist is
  /// complete, with its hint while it is not; « Demande envoyée le … » while
  /// the request waits; « Mon abonnement » for a salon its lapsed offer took
  /// offline; nothing for a final refusal, a live salon, or a member who is
  /// not the owner.
  List<Widget> _action(
    GoLiveState state,
    ProOnboardingProvider onboarding,
    ProAuthProvider auth,
  ) {
    final label = publishButtonLabel(state);
    if (label != null) {
      final hint = onboarding.readyToGoLive ? null : publishHint(state);
      return [
        const SizedBox(height: AppTheme.spacingS),
        AppButton(
          text: label,
          isLoading: onboarding.isPublishing,
          onPressed: onboarding.readyToGoLive ? _goLive : null,
        ),
        if (hint != null) ...[
          const SizedBox(height: AppTheme.spacingS),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ];
    }
    switch (state) {
      case GoLiveState.pending:
        // The day in the salon's clock, no weekday (decision 136 item 6);
        // nothing when the request carries no time.
        final sent = requestSentLine(
          onboarding.validation?.submittedAt,
          tz: auth.salonTimezone,
        );
        if (sent == null) return const [];
        return [
          const SizedBox(height: AppTheme.spacingM),
          Text(
            sent,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ];
      case GoLiveState.offlineUnpaid:
        // A pointer to « Mon abonnement », the status screen — never a
        // choice of offer (decision 136 item 5; App Store 3.1.1).
        return [
          const SizedBox(height: AppTheme.spacingS),
          AppButton(
            text: SalonValidationCopy.billingPointer,
            type: AppButtonType.secondary,
            onPressed: () => context.push('/pro/subscription'),
          ),
        ];
      default:
        return const [];
    }
  }
}

/// The validation's banner on « Configuration » (§6.1), on the shared
/// [StatusBanner]. Tones as the website (web-salon-validation.md §4.1): a
/// request waiting is neutral, a refusal and a suspension are errors, a
/// salon no longer online a warning — each with its glyph, so the state
/// survives greyscale (SYSTEM.md §13.6) beside its title.
class _GoLiveStatusBanner extends StatelessWidget {
  const _GoLiveStatusBanner(this.banner);

  final GoLiveBanner banner;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (banner.tone) {
      GoLiveTone.neutral => (AppColors.textSecondary, Icons.schedule),
      GoLiveTone.error => (AppColors.error, Icons.error_outline),
      GoLiveTone.warning => (AppColors.warning, Icons.warning_amber),
    };
    return StatusBanner(
      color: color,
      icon: icon,
      title: banner.title,
      lines: banner.lines,
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
