import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/google_g_logo.dart';

/// Salon sign-in — Google + Apple (flag-hidden) + email OTP, replacing the
/// phone-OTP login (pro auth overhaul P4). LOGIN-ONLY: `provider_not_found`
/// offers « Créer un compte » → the register screen (identity + business
/// fields in one submit). Design: docs/design/pro-auth-social.md.
class ProLoginScreen extends StatefulWidget {
  const ProLoginScreen({super.key, this.returnTo});

  /// Auth-continuity: where to land after sign-in (defaults to the dashboard).
  final String? returnTo;

  @override
  State<ProLoginScreen> createState() => _ProLoginScreenState();
}

enum _Step { options, code }

class _ProLoginScreenState extends State<ProLoginScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  _Step _step = _Step.options;

  bool get _emailValid => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
      .hasMatch(_emailController.text.trim());

  bool get _showApple =>
      FeatureFlags.appleSignIn && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _finish() => context.go(widget.returnTo ?? '/pro/dashboard');

  Future<void> _handleGoogle() async {
    final auth = context.read<ProAuthProvider>();
    if (await auth.signInWithGoogle() && mounted) _finish();
  }

  Future<void> _handleApple() async {
    final auth = context.read<ProAuthProvider>();
    if (await auth.signInWithApple() && mounted) _finish();
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
    }
  }

  Future<void> _verifyCode() async {
    final auth = context.read<ProAuthProvider>();
    final ok = await auth.verifyEmailOtp(
      _emailController.text.trim(),
      _codeController.text.trim(),
    );
    if (ok && mounted) _finish();
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
