import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/unnamed_salon.dart';
import '../../../core/forms/field_errors.dart';
import '../../../core/forms/sign_in_refusal.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/external_link.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/apple_logo.dart';
import '../../../widgets/common/auth_switch_prompt.dart';
import '../../../widgets/common/google_g_logo.dart';
import '../../../widgets/common/inline_feedback.dart';
import '../../../widgets/common/session_ended_notice.dart';
import '../../../widgets/team/invitation_card.dart';
import '../../../widgets/team/revoked_access_banner.dart';

/// Salon sign-in — Google + Apple (flag-hidden) + email OTP, replacing the
/// phone-OTP login (pro auth overhaul P4). LOGIN-ONLY, and nothing else: the
/// app no longer signs a business up (App Store 3.1.1 — Apple refused 0.0.1
/// for it). `provider_not_found` says so in one sentence, with the invitation
/// hint — UNLESS the verified email holds pending team invitations (module
/// `access` R3): the « Invitations » step lets the invitee join. A salon
/// signs up on the web: « S’inscrire sur myweli.com » opens it in the
/// browser (the owner's call). Designs: docs/design/pro-app-login-only.md ·
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

  /// The server ended the session (pro-account-scope.md §2.3, Q2 = a) —
  /// consumed once, like the revoked notice.
  bool _sessionEnded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<ProAuthProvider>();
      final notice = auth.consumeRevokedNotice();
      final ended = auth.consumeSessionEndedNotice();
      if ((notice != null || ended) && mounted) {
        setState(() {
          _revokedSalon = notice;
          _sessionEnded = ended;
        });
      }
    });
  }

  // A7/§14 — the third copy of the loose e-mail regex, gone.
  late final _errors = FieldErrors({
    'email': Validators.email,
    'code': Validators.otp,
  });
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  late final _focusNodes = {'email': _emailFocus, 'code': _codeFocus};

  bool get _showApple =>
      FeatureFlags.appleSignIn && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _finish() {
    final auth = context.read<ProAuthProvider>();
    // A former member re-invited: signed in, no salon — the session waits on
    // its invitations (docs/design/pro-rejoin-gate.md §2). Checked FIRST: the
    // session is live, so everything below would open a salon it has lost.
    if (auth.rejoinPending) {
      context.go('/pro/invitations');
      return;
    }
    // A Collaborateur lands on their shell; returnTo may point at owner
    // surfaces they can't use (access R4b).
    context.go(
      auth.isStaff ? '/pro/staff' : (widget.returnTo ?? '/pro/dashboard'),
    );
  }

  /// Where a sign-in lands. Signed in → [_finish]; the 202 bridge → the
  /// « Invitations » step; otherwise, a revocation that ended the session
  /// with nothing pending (S11) left its one-shot notice — shown HERE, in
  /// place. This State outlives the sign-out's `go('/pro/login')` (the same
  /// page), so its initState never reads that notice; the screen used to
  /// route the signed-out user on to the dashboard's « Veuillez vous
  /// connecter » instead.
  void _land(bool ok) {
    final auth = context.read<ProAuthProvider>();
    if (ok) {
      _finish();
    } else if (auth.hasPendingInvitations) {
      setState(() => _step = _Step.invitations);
    } else {
      final notice = auth.consumeRevokedNotice();
      if (notice != null) {
        // Back on the options: an e-mail code was spent by the sign-in.
        setState(() {
          _revokedSalon = notice;
          _step = _Step.options;
        });
      }
    }
  }

  Future<void> _handleGoogle() async {
    final auth = context.read<ProAuthProvider>();
    final ok = await auth.signInWithGoogle();
    if (mounted) _land(ok);
  }

  Future<void> _handleApple() async {
    final auth = context.read<ProAuthProvider>();
    final ok = await auth.signInWithApple();
    if (mounted) _land(ok);
  }

  /// « Rejoindre » — accepts under the login-proven identity; the account
  /// (bare member if new) and session come back ready.
  Future<void> _acceptInvitation(String invitationId, String salonName) async {
    final auth = context.read<ProAuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await auth.acceptPendingInvitation(invitationId);
    if (!mounted) return;
    if (ok) {
      AppSnackBar.showOn(
        messenger,
        'Bienvenue dans l’équipe de $salonName !',
        kind: SnackKind.success,
      );
      _finish();
    } else {
      _land(false);
    }
  }

  Future<void> _declineInvitation(String invitationId) async {
    final auth = context.read<ProAuthProvider>();
    await auth.declinePendingInvitation(invitationId);
    if (!mounted) return;
    if (!auth.hasPendingInvitations) {
      // Every invitation handled — fall back to the classic options step,
      // where provider_not_found's sentence says there is no account.
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
    // §14 rule 5: the button is never disabled for validity, so it answers.
    if (!_errors.validate({'email': _emailController.text})) {
      setState(() {});
      focusFirstError(_errors, _focusNodes);
      return;
    }
    final auth = context.read<ProAuthProvider>();
    final ok = await auth.requestEmailOtp(_emailController.text.trim());
    if (!mounted) return;
    if (ok) {
      setState(() {
        _codeController.clear();
        // A new code: the last one's fault is not this one's.
        _errors.set('code', null);
        _step = _Step.code;
      });
      _startCooldown();
      return;
    }
    // The e-mail's fault under the e-mail — when it is on screen; « Renvoyer
    // le code » is on the code step, where it is the form's.
    final fault = emailFieldFault(auth.errorCode);
    if (fault != null && _step == _Step.options) {
      setState(() => _errors.set('email', fault));
      focusFirstError(_errors, _focusNodes);
    }
  }

  /// What the form says under itself: the refusal, unless it belongs to a
  /// field on screen (sign_in_refusal.dart — the web's table).
  String? _formFault(ProAuthProvider auth) {
    final code = auth.errorCode;
    if (_step == _Step.code && codeFieldFault(code) != null) return null;
    if (_step == _Step.options && emailFieldFault(code) != null) return null;
    return auth.error;
  }

  Future<void> _verifyCode() async {
    if (!_errors.validate({'code': _codeController.text})) {
      setState(() {});
      focusFirstError(_errors, _focusNodes);
      return;
    }
    final auth = context.read<ProAuthProvider>();
    final ok = await auth.verifyEmailOtp(
      _emailController.text.trim(),
      _codeController.text.trim(),
    );
    if (!mounted) return;
    // « Code incorrect. » is the code's: under the code (SYSTEM §14 rule 1).
    final fault = ok ? null : codeFieldFault(auth.errorCode);
    if (fault != null) {
      setState(() => _errors.set('code', fault));
      focusFirstError(_errors, _focusNodes);
    }
    _land(ok);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
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
                const SizedBox(height: AppTheme.spacingM),
                RevokedAccessBanner(salonName: _revokedSalon!),
              ],
              if (_sessionEnded) ...[
                const SizedBox(height: AppTheme.spacingM),
                const InlineFeedback(
                  kSessionEndedMessage,
                  kind: SnackKind.info,
                ),
              ],
              const SizedBox(height: AppTheme.spacingL),
              SvgPicture.asset(
                'assets/brand/myweli_lockup_vertical_black.svg',
                height: 100,
                semanticsLabel: 'MyWeli Pro',
              ),
              const SizedBox(height: AppTheme.spacingL),
              if (_step == _Step.options) ...[
                Text(
                  'Espace Pro',
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingS),
                Text(
                  'Connectez-vous à votre espace salon.',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingXL),
                AppButton(
                  text: 'Continuer avec Google',
                  type: AppButtonType.secondary,
                  leading: const GoogleGLogo(),
                  onPressed: auth.isLoading ? null : _handleGoogle,
                ),
                if (_showApple) ...[
                  const SizedBox(height: AppTheme.spacingSM),
                  AppButton(
                    text: 'Continuer avec Apple',
                    leading: const AppleLogo(),
                    onPressed: auth.isLoading ? null : _handleApple,
                  ),
                ],
                const SizedBox(height: AppTheme.spacingL),
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
                const SizedBox(height: AppTheme.spacingL),
                AppTextField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  label: 'Votre e-mail',
                  hint: 'exemple@email.com',
                  keyboardType: TextInputType.emailAddress,
                  errorText: _errors['email'],
                  onChanged: (v) =>
                      setState(() => _errors.revalidate('email', v)),
                ),
                const SizedBox(height: AppTheme.spacingM),
                AppButton(
                  text: 'Continuer avec e-mail',
                  // §14 rule 5: disabled ONLY while submitting.
                  onPressed: auth.isLoading ? null : _sendCode,
                  isLoading: auth.isLoading,
                ),
              ] else if (_step == _Step.invitations) ...[
                Text(
                  'Vous êtes invité(e)',
                  style: AppTextStyles.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingS),
                Text(
                  'Rejoignez l’équipe — aucun salon à créer.',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingL),
                for (final invitation in auth.pendingInvitations) ...[
                  InvitationCard(
                    invitation: invitation,
                    busy: auth.isLoading,
                    onAccept: () => _acceptInvitation(
                      invitation.id,
                      salonNameOr(
                        invitation.salonName,
                        kUnnamedSalonInSentence,
                      ),
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
                const SizedBox(height: AppTheme.spacingL),
                AppTextField(
                  controller: _codeController,
                  focusNode: _codeFocus,
                  label: 'Code à 6 chiffres',
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  errorText: _errors['code'],
                  onChanged: (v) =>
                      setState(() => _errors.revalidate('code', v)),
                ),
                if (auth.emailDevCode != null) ...[
                  const SizedBox(height: AppTheme.spacingXS),
                  Text(
                    'Code (dev) : ${auth.emailDevCode}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppTheme.spacingM),
                AppButton(
                  text: 'Se connecter',
                  // The gate said 4 on a « Code à 6 chiffres » field with
                  // maxLength 6. Rule 5: disabled only while submitting.
                  onPressed: auth.isLoading ? null : _verifyCode,
                  isLoading: auth.isLoading,
                ),
                const SizedBox(height: AppTheme.spacingSM),
                AppButton(
                  text: _resendCooldown > 0
                      ? 'Renvoyer le code (${_resendCooldown}s)'
                      : 'Renvoyer le code',
                  type: AppButtonType.text,
                  onPressed: (auth.isLoading || _resendCooldown > 0)
                      ? null
                      : _sendCode,
                ),
                const SizedBox(height: AppTheme.spacingXS),
                AppButton(
                  text: 'Changer d’e-mail',
                  type: AppButtonType.text,
                  onPressed: auth.isLoading
                      ? null
                      : () => setState(() => _step = _Step.options),
                ),
              ],
              // §14 rule 3 + §15: a server OUTCOME is form-level, and
              // `InlineFeedback` is a live region — a red Text never was.
              InlineFeedback(_formFault(auth)),
              const SizedBox(height: AppTheme.spacingL),
              // The app does not sign a business up (App Store 3.1.1,
              // docs/design/pro-app-login-only.md): the web does, and this
              // says so — it opens the browser, it never pushes a route.
              AuthSwitchPrompt(
                question: 'Pas encore de compte ?',
                actionLabel: 'S’inscrire sur myweli.com',
                onPressed: () =>
                    openExternalUrl(context, AppConfig.proSignUpUrl),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
