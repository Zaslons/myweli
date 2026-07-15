import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/feature_flags.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/google_g_logo.dart';
import '../../widgets/common/phone_number_field.dart';

/// Consumer sign-in — Google + Apple (flag-hidden) + email OTP, replacing the
/// phone-OTP login (auth overhaul P3; mirrors the web flow). After ANY
/// successful login where the account has no phone, a **mandatory contact
/// phone step** blocks until saved — the salon needs a number to reach the
/// client. Design: docs/design/app-auth-social.md.
class LoginScreen extends StatefulWidget {
  final String? returnTo;

  const LoginScreen({super.key, this.returnTo});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _LoginStep { options, code, phone }

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  _LoginStep _step = _LoginStep.options;
  String _phoneNumber = '';

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

  /// Post-login: block on the contact phone when the account has none.
  void _afterLogin(AuthProvider auth) {
    final user = auth.user;
    if (user != null &&
        (user.phoneNumber == null || user.phoneNumber!.isEmpty)) {
      setState(() => _step = _LoginStep.phone);
      return;
    }
    _finish();
  }

  void _finish() => context.go(widget.returnTo ?? '/home');

  Future<void> _handleGoogle() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithGoogle();
    if (!mounted) return;
    if (ok) _afterLogin(auth);
  }

  Future<void> _handleApple() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithApple();
    if (!mounted) return;
    if (ok) _afterLogin(auth);
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

  Future<void> _sendEmailCode() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.requestEmailOtp(_emailController.text.trim());
    if (!mounted) return;
    if (ok) {
      setState(() {
        _codeController.clear();
        _step = _LoginStep.code;
      });
      _startCooldown();
    }
  }

  Future<void> _verifyEmailCode() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyEmailOtp(
      _emailController.text.trim(),
      _codeController.text.trim(),
    );
    if (!mounted) return;
    if (ok) _afterLogin(auth);
  }

  Future<void> _savePhone() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateUser(phone: _phoneNumber);
    if (!mounted) return;
    if (ok) _finish();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Connexion')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppTheme.spacingL),
              // Brand lockup (mark + MyWeli wordmark) — black on the light bg.
              SvgPicture.asset(
                'assets/brand/myweli_lockup_vertical_black.svg',
                height: 110,
                semanticsLabel: 'MyWeli',
              ),
              const SizedBox(height: AppTheme.spacingL),
              ..._buildStep(auth),
              const SizedBox(height: AppTheme.spacingL),
              if (_step != _LoginStep.phone)
                Text(
                  'En continuant, vous acceptez nos conditions d\'utilisation',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStep(AuthProvider auth) {
    switch (_step) {
      case _LoginStep.options:
        return _optionsStep(auth);
      case _LoginStep.code:
        return _codeStep(auth);
      case _LoginStep.phone:
        return _phoneStep(auth);
    }
  }

  List<Widget> _optionsStep(AuthProvider auth) => [
        Text(
          'Bienvenue',
          style: AppTextStyles.headlineLarge.copyWith(
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.spacingS),
        Text(
          'Connectez-vous pour réserver en quelques secondes.',
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
          label: 'Votre e-mail',
          hint: 'exemple@email.com',
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppTheme.spacingM),
        AppButton(
          text: 'Continuer avec e-mail',
          onPressed: (auth.isLoading || !_emailValid) ? null : _sendEmailCode,
          isLoading: auth.isLoading,
        ),
        if (auth.error != null) ...[
          const SizedBox(height: AppTheme.spacingSM),
          Text(
            auth.error!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
        ],
      ];

  List<Widget> _codeStep(AuthProvider auth) => [
        Text(
          'Entrez le code reçu par e-mail à ${_emailController.text.trim()}.',
          style: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.spacingL),
        AppTextField(
          controller: _codeController,
          label: 'Code à 6 chiffres',
          keyboardType: TextInputType.number,
          maxLength: 6,
          onChanged: (_) => setState(() {}),
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
          onPressed: (auth.isLoading || _codeController.text.trim().length < 4)
              ? null
              : _verifyEmailCode,
          isLoading: auth.isLoading,
        ),
        const SizedBox(height: AppTheme.spacingSM),
        AppButton(
          text: _resendCooldown > 0
              ? 'Renvoyer le code (${_resendCooldown}s)'
              : 'Renvoyer le code',
          type: AppButtonType.text,
          onPressed:
              (auth.isLoading || _resendCooldown > 0) ? null : _sendEmailCode,
        ),
        const SizedBox(height: AppTheme.spacingXS),
        AppButton(
          text: 'Changer d\'e-mail',
          type: AppButtonType.text,
          onPressed: auth.isLoading
              ? null
              : () => setState(() => _step = _LoginStep.options),
        ),
        if (auth.error != null) ...[
          const SizedBox(height: AppTheme.spacingSM),
          Text(
            auth.error!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
        ],
      ];

  List<Widget> _phoneStep(AuthProvider auth) => [
        Text(
          'Votre numéro de téléphone',
          style: AppTextStyles.headlineMedium.copyWith(
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.spacingS),
        Text(
          'Le salon l\'utilise pour vous contacter au sujet de vos rendez-vous.',
          style: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.spacingL),
        PhoneNumberField(
          onChanged: (e164) => setState(() => _phoneNumber = e164),
        ),
        const SizedBox(height: AppTheme.spacingM),
        AppButton(
          text: 'Continuer',
          onPressed:
              (auth.isLoading || _phoneNumber.isEmpty) ? null : _savePhone,
          isLoading: auth.isLoading,
        ),
        if (auth.error != null) ...[
          const SizedBox(height: AppTheme.spacingSM),
          Text(
            auth.error!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
        ],
      ];
}
