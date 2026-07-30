import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/forms/field_errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/legal_consent_text.dart';
import '../../widgets/common/phone_number_field.dart';

class PhoneLoginScreen extends StatefulWidget {
  final String? returnTo;

  const PhoneLoginScreen({super.key, this.returnTo});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  // A7/§14 — the last Flutter form key in the app. Converted even though
  // this screen is unrouted: leaving one screen on the old mechanism leaves a
  // second, divergent idiom in the tree for the next person to copy.
  late final _errors = FieldErrors({'phone': Validators.phoneNumber});
  String _phoneNumber = '';
  bool _isLoading = false;

  Future<void> _handleContinue() async {
    if (!_errors.validate({'phone': _phoneNumber})) {
      setState(() {});
      return;
    }

    setState(() => _isLoading = true);

    final phoneNumber = _phoneNumber;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final success = await authProvider.sendOtp(phoneNumber);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      final returnToParam = widget.returnTo != null
          ? '&returnTo=${Uri.encodeComponent(widget.returnTo!)}'
          : '';
      unawaited(context.push(
          '/verify-otp?phone=${Uri.encodeComponent(phoneNumber)}$returnToParam'));
    } else {
      AppSnackBar.show(
          context, authProvider.error ?? 'Erreur lors de l’envoi du code',
          kind: SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Connexion'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppTheme.spacingXL),
              // Brand lockup (mark + MyWeli wordmark) — black on the light bg.
              SvgPicture.asset(
                'assets/brand/myweli_lockup_vertical_black.svg',
                height: 120,
                semanticsLabel: 'MyWeli',
              ),
              const SizedBox(height: AppTheme.spacingXL),
              Text(
                'Bienvenue',
                style: AppTextStyles.headlineLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacingS),
              Text(
                'Connectez-vous avec votre numéro',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacingXL),
              PhoneNumberField(
                errorText: _errors['phone'],
                onChanged: (e164) => setState(() {
                  _phoneNumber = e164;
                  _errors.revalidate('phone', e164);
                }),
              ),
              const SizedBox(height: AppTheme.spacingL),
              AppButton(
                text: 'Continuer',
                onPressed: _isLoading ? null : _handleContinue,
                isLoading: _isLoading,
              ),
              const SizedBox(height: AppTheme.spacingL),
              const LegalConsentText(),
            ],
          ),
        ),
      ),
    );
  }
}
