import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/google_g_logo.dart';
import '../../../widgets/team/invitation_card.dart';

/// Salon sign-in — Google + Apple (flag-hidden) + email OTP, replacing the
/// phone-OTP login (pro auth overhaul P4). LOGIN-ONLY: `provider_not_found`
/// offers « Créer un compte » → the register screen (identity + business
/// fields in one submit) — UNLESS the verified email holds pending team
/// invitations (module `access` R3): the « Invitations » step lets the
/// invitee join WITHOUT creating a salon. Designs:
/// docs/design/pro-auth-social.md · docs/design/team-access-r3-app.md §2.2.
class ProLoginScreen extends StatefulWidget {
  const ProLoginScreen({super.key, this.returnTo});

  /// Auth-continuity: where to land after sign-in (defaults to the dashboard).
  final String? returnTo;

  @override
  State<ProLoginScreen> createState() => _ProLoginScreenState();
}

enum _Step { options, code, invitations }

class _ProLoginScreenState extends State<ProLoginScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  _Step _step = _Step.options;

  /// Revoked-mid-session notice (access R4b §5.3): consumed once from the
  /// auth provider after the global handler signed the member out.
  String? _revokedSalon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notice = context.read<ProAuthProvider>().consumeRevokedNotice();
      if (notice != null && mounted) {
        setState(() => _revokedSalon = notice);
      }
    });
  }

  bool get _emailValid => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
      .hasMatch(_emailController.text.trim());

  bool get _showApple =>
      FeatureFlags.appleSignIn && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _finish() {
    // A Collaborateur lands on their shell; returnTo may point at owner
    // surfaces they can't use (access R4b).
    final auth = context.read<ProAuthProvider>();
    context.go(
        auth.isStaff ? '/pro/staff' : (widget.returnTo ?? '/pro/dashboard'));
  }

  Future<void> _handleGoogle() async {
    final auth = context.read<ProAuthProvider>();
    final ok = await auth.signInWithGoogle();
    if (!mounted) return;
    if (ok) {
      _finish();
    } else if (auth.hasPendingInvitations) {
      setState(() => _step = _Step.invitations);
    }
  }

  Future<void> _handleApple() async {
    final auth = context.read<ProAuthProvider>();
    if (await auth.signInWithApple() && mounted) _finish();
  }

  /// « Rejoindre » — accepts under the login-proven identity; the account
  /// (bare member if new) and session come back ready.
  Future<void> _acceptInvitation(String invitationId, String salonName) async {
    final auth = context.read<ProAuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await auth.acceptPendingInvitation(invitationId);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('Bienvenue dans l\'équipe de $salonName !')),
      );
      _finish();
    }
  }

  Future<void> _declineInvitation(String invitationId) async {
    final auth = context.read<ProAuthProvider>();
    await auth.declinePendingInvitation(invitationId);
    if (!mounted) return;
    if (!auth.hasPendingInvitations) {
      // Every invitation handled — fall back to the classic options step
      // (« Créer un compte » renders from provider_not_found).
      setState(() => _step = _Step.options);
    }
  }

  // Resend cooldown (module 11 — the dormant OTP screen's pattern).
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  void _startCooldown() {
    _resendCooldown = AppConstants.otpResendCooldownSeconds;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _sendCode() async {
    final auth = context.read<ProAuthProvider>();
    final ok = await auth.requestEmailOtp(_emailController.text.trim());
    if (!mounted) return;
    if (ok) {
      setState(() {
        _codeController.clear();
        _step = _Step.code;
      });
      _startCooldown();
    }
  }

  Future<void> _verifyCode() async {
    final auth = context.read<ProAuthProvider>();
    final ok = await auth.verifyEmailOtp(
      _emailController.text.trim(),
      _codeController.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      _finish();
    } else if (auth.hasPendingInvitations) {
      setState(() => _step = _Step.invitations);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
    final notFound = auth.errorCode == 'provider_not_found';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Espace Pro')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_revokedSalon != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_off_outlined,
                          color: AppColors.error),
                      const SizedBox(width: AppTheme.spacingS),
                      Expanded(
                        child: Text(
                          _revokedSalon == 'votre salon'
                              ? 'Votre accès à ce salon a été retiré.'
                              : 'Votre accès à $_revokedSalon a été '
                                  'retiré.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SvgPicture.asset(
                'assets/brand/myweli_lockup_vertical_black.svg',
                height: 100,
                semanticsLabel: 'MyWeli Pro',
              ),
              const SizedBox(height: 24),
              if (_step == _Step.options) ...[
                Text(
                  'Espace Pro',
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connectez-vous à votre espace salon.',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                AppButton(
                  text: 'Continuer avec Google',
                  type: AppButtonType.secondary,
                  leading: const GoogleGLogo(),
                  onPressed: auth.isLoading ? null : _handleGoogle,
                ),
                if (_showApple) ...[
                  const SizedBox(height: 12),
                  AppButton(
                    text: 'Continuer avec Apple',
                    onPressed: auth.isLoading ? null : _handleApple,
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.divider)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingM,
                      ),
                      child: Text(
                        'ou',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider(color: AppColors.divider)),
                  ],
                ),
                const SizedBox(height: 20),
                AppTextField(
                  controller: _emailController,
                  label: 'Votre e-mail',
                  hint: 'exemple@email.com',
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                AppButton(
                  text: 'Continuer avec e-mail',
                  onPressed:
                      (auth.isLoading || !_emailValid) ? null : _sendCode,
                  isLoading: auth.isLoading,
                ),
              ] else if (_step == _Step.invitations) ...[
                Text(
                  'Vous êtes invité(e)',
                  style: AppTextStyles.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Rejoignez l\'équipe — aucun salon à créer.',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                for (final invitation in auth.pendingInvitations) ...[
                  InvitationCard(
                    invitation: invitation,
                    busy: auth.isLoading,
                    onAccept: () => _acceptInvitation(
                      invitation.id,
                      invitation.salonName,
                    ),
                    onDecline: () => _declineInvitation(invitation.id),
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                ],
                AppButton(
                  text: 'Retour',
                  type: AppButtonType.text,
                  onPressed: auth.isLoading
                      ? null
                      : () {
                          auth.clearPendingInvitations();
                          setState(() => _step = _Step.options);
                        },
                ),
              ] else ...[
                Text(
                  'Entrez le code reçu par e-mail à '
                  '${_emailController.text.trim()}.',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                AppTextField(
                  controller: _codeController,
                  label: 'Code à 6 chiffres',
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  onChanged: (_) => setState(() {}),
                ),
                if (auth.emailDevCode != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Code (dev) : ${auth.emailDevCode}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                AppButton(
                  text: 'Se connecter',
                  onPressed:
                      (auth.isLoading || _codeController.text.trim().length < 4)
                          ? null
                          : _verifyCode,
                  isLoading: auth.isLoading,
                ),
                const SizedBox(height: 12),
                AppButton(
                  text: _resendCooldown > 0
                      ? 'Renvoyer le code (${_resendCooldown}s)'
                      : 'Renvoyer le code',
                  type: AppButtonType.text,
                  onPressed: (auth.isLoading || _resendCooldown > 0)
                      ? null
                      : _sendCode,
                ),
                const SizedBox(height: 4),
                AppButton(
                  text: 'Changer d\'e-mail',
                  type: AppButtonType.text,
                  onPressed: auth.isLoading
                      ? null
                      : () => setState(() => _step = _Step.options),
                ),
              ],
              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  auth.error!,
                  style:
                      AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
              ],
              if (notFound) ...[
                const SizedBox(height: 8),
                AppButton(
                  text: 'Créer un compte',
                  onPressed: () => context.go('/pro/register'),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Pas encore de compte ? ',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/pro/register'),
                    child: const Text('S\'inscrire'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
