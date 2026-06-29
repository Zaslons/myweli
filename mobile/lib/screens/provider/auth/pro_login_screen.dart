import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/phone_number_field.dart';

class ProLoginScreen extends StatefulWidget {
  final String? returnTo;

  const ProLoginScreen({super.key, this.returnTo});

  @override
  State<ProLoginScreen> createState() => _ProLoginScreenState();
}

class _ProLoginScreenState extends State<ProLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String _phoneNumber = '';
  bool _isLoading = false;

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final phoneNumber = _phoneNumber;
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);

    final success = await authProvider.sendOtp(phoneNumber);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      final returnToParam = widget.returnTo != null
          ? '&returnTo=${Uri.encodeComponent(widget.returnTo!)}'
          : '';
      unawaited(context.push(
          '/pro/verify-otp?phone=${Uri.encodeComponent(phoneNumber)}$returnToParam'));
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
        title: const Text('Connexion Pro'),
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
                  Icons.business,
                  size: 120,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 32),
                Text(
                  'Bienvenue sur Myweli Pro',
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connectez-vous pour gérer votre entreprise',
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
                const SizedBox(height: 16),
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
                      onPressed: () => context.push('/pro/register'),
                      child: const Text('S\'inscrire'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
