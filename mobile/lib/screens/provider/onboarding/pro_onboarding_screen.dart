import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/onboarding.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_onboarding_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';

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
      final pro = context.read<ProAuthProvider>().provider;
      if (pro != null) {
        context.read<ProOnboardingProvider>().load(pro);
      }
    });
  }

  Future<void> _goLive() async {
    final messenger = ScaffoldMessenger.of(context);
    final providerId =
        context.read<ProAuthProvider>().provider?.providerId ?? '';
    final onboarding = context.read<ProOnboardingProvider>();
    final ok = await onboarding.publish(providerId);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '🎉 Votre profil est en ligne !'
              : (onboarding.error ?? 'La mise en ligne a échoué'),
        ),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Configurer mon profil')),
      body: Consumer2<ProAuthProvider, ProOnboardingProvider>(
        builder: (context, auth, onboarding, _) {
          final pro = auth.provider;
          if (pro == null) {
            return const Center(child: Text('Veuillez vous connecter'));
          }
          if (onboarding.isLoading) {
            return const LoadingIndicator();
          }
          if (onboarding.loadFailed) {
            return EmptyState(
              icon: Icons.wifi_off,
              title: 'Chargement impossible',
              description: 'Vérifiez votre connexion et réessayez.',
              actionText: 'Réessayer',
              onAction: () => onboarding.load(pro),
            );
          }
          return _buildList(onboarding);
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
          '${progress.done} étapes sur ${progress.total} terminées',
          style:
              AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: AppColors.surface,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        const SizedBox(height: AppTheme.spacingL),
        for (final step in onboarding.steps) _StepRow(step: step),
        const SizedBox(height: AppTheme.spacingL),
        // See the salon exactly as a client will, before going live (B5).
        OutlinedButton(
          onPressed: () => context.push('/pro/apercu'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(vertical: 14),
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
          const SizedBox(height: 8),
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

  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    final route = _route(step.key);
    final sublabel = _sublabel(step);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading:
            Icon(_statusIcon(step.status), color: _statusColor(step.status)),
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
    );
  }

  String _label(OnboardingStepKey key) {
    switch (key) {
      case OnboardingStepKey.profile:
        return 'Profil de l\'entreprise';
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
    if (step.key == OnboardingStepKey.staff &&
        step.status == OnboardingStepStatus.optional) {
      return 'Optionnel pour les indépendants';
    }
    if (step.key == OnboardingStepKey.photos) {
      return 'Ajouter des photos du salon';
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
