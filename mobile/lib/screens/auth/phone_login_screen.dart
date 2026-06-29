import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/phone_number_field.dart';

class PhoneLoginScreen extends StatefulWidget {
  final String? returnTo;

  const PhoneLoginScreen({super.key, this.returnTo});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String _phoneNumber = '';
  bool _isLoading = false;

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(authProvider.error ?? 'Erreur lors de l\'envoi du code'),
          backgroundColor: AppColors.error,
        ),
      );
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                // Icon
                const Icon(
                  Icons.phone_android,
                  size: 120,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 32),
                Text(
                  'Bienvenue sur Myweli',
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connectez-vous avec votre numéro',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                PhoneNumberField(
                  onChanged: (e164) => _phoneNumber = e164,
                ),
                const SizedBox(height: 24),
                AppButton(
                  text: 'Continuer',
                  onPressed: _isLoading ? null : _handleContinue,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 24),
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
      ),
    );
  }
}
