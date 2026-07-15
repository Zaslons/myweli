import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/provider_user.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/commune_picker_sheet.dart';
import '../../../widgets/common/google_g_logo.dart';
import '../../../widgets/common/phone_number_field.dart';

/// Salon registration — business fields + login identity in ONE submit
/// (pro auth overhaul P4): Google / Apple (flag-hidden) / email+code. The
/// contact phone is REQUIRED (clients + MyWeli reach the salon there).
/// Registration signs in directly → dashboard. Design:
/// docs/design/pro-auth-social.md.
class ProRegisterScreen extends StatefulWidget {
  const ProRegisterScreen({super.key});

  @override
  State<ProRegisterScreen> createState() => _ProRegisterScreenState();
}

class _ProRegisterScreenState extends State<ProRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _addressController = TextEditingController();

  /// Multi-pays MP2: the optional locality pick at creation — the server
  /// derives the salon's commune/city/timezone/currency from it (T57). The
  /// publish gate requires it before go-live; picking it here saves a step.
  String? _areaId;
  String _communeName = '';
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  String _phoneNumber = '';
  BusinessType? _selectedBusinessType;
  bool _codeSent = false;

  bool get _emailValid => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
      .hasMatch(_emailController.text.trim());

  bool get _showApple =>
      FeatureFlags.appleSignIn && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _pickCommune() async {
    final choice = await showCommunePicker(
      context,
      selected: _communeName.isEmpty ? null : _communeName,
      allowAll: false,
    );
    if (choice == null || choice.areaId == null || !mounted) return;
    setState(() {
      _areaId = choice.areaId;
      _communeName = choice.commune ?? '';
    });
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Business fields must be valid before ANY identity path fires — the
  /// backend registers identity + salon atomically in one call.
  bool _validateBusinessFields() {
    if (!_formKey.currentState!.validate()) return false;
    if (_phoneNumber.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le numéro de téléphone du salon est requis'),
          backgroundColor: AppColors.error,
        ),
      );
      return false;
    }
    return true;
  }

  void _finish() => context.go('/pro/dashboard');

  Future<void> _handleGoogle() async {
    if (!_validateBusinessFields()) return;
    final auth = context.read<ProAuthProvider>();
    final ok = await auth.registerWithGoogle(
      phoneNumber: _phoneNumber,
      businessName: _businessNameController.text.trim(),
      businessType: _selectedBusinessType!,
      address: _addressController.text.trim(),
      areaId: _areaId,
    );
    if (ok && mounted) _finish();
  }

  Future<void> _sendCode() async {
    if (!_validateBusinessFields()) return;
    final auth = context.read<ProAuthProvider>();
    final ok = await auth.requestEmailOtp(_emailController.text.trim());
    if (!mounted) return;
    if (ok) {
      setState(() {
        _codeController.clear();
        _codeSent = true;
      });
    }
  }

  Future<void> _handleEmailRegister() async {
    if (!_validateBusinessFields()) return;
    final auth = context.read<ProAuthProvider>();
    final ok = await auth.registerWithEmail(
      email: _emailController.text.trim(),
      code: _codeController.text.trim(),
      phoneNumber: _phoneNumber,
      businessName: _businessNameController.text.trim(),
      businessType: _selectedBusinessType!,
      address: _addressController.text.trim(),
      areaId: _areaId,
    );
    if (ok && mounted) _finish();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Inscription Pro'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingL),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppTheme.spacingL),
                Text(
                  'Créez votre compte professionnel',
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingS),
                Text(
                  'Rejoignez MyWeli Pro et gérez votre salon',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingXL),
                AppTextField(
                  label: 'Nom de l\'entreprise',
                  hint: 'Ex: Salon de Beauté Marie',
                  controller: _businessNameController,
                  prefixIcon: const Icon(Icons.store),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Le nom de l\'entreprise est requis';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.spacingM),
                DropdownButtonFormField<BusinessType>(
                  initialValue: _selectedBusinessType,
                  decoration: InputDecoration(
                    labelText: 'Type d\'entreprise',
                    prefixIcon: const Icon(Icons.category),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                  ),
                  items: BusinessType.values.map((type) {
                    String label;
                    switch (type) {
                      case BusinessType.salon:
                        label = 'Salon de beauté';
                        break;
                      case BusinessType.barber:
                        label = 'Barbier';
                        break;
                      case BusinessType.spa:
                        label = 'Spa';
                        break;
                      case BusinessType.nailSalon:
                        label = 'Institut de manucure';
                        break;
                      case BusinessType.massage:
                        label = 'Massage';
                        break;
                      case BusinessType.other:
                        label = 'Autre';
                        break;
                    }
                    return DropdownMenuItem(
                      value: type,
                      child: Text(label),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedBusinessType = value);
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Veuillez sélectionner un type';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.spacingM),
                PhoneNumberField(
                  label: 'Téléphone du salon',
                  onChanged: (e164) => _phoneNumber = e164,
                ),
                const SizedBox(height: AppTheme.spacingM),
                AppTextField(
                  label: 'Adresse',
                  hint: 'Adresse de l\'entreprise',
                  controller: _addressController,
                  prefixIcon: const Icon(Icons.location_on),
                  maxLines: 2,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'L\'adresse est requise';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.spacingS),
                InkWell(
                  onTap: _pickCommune,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: InputDecorator(
                    decoration:
                        const InputDecoration(labelText: 'Commune (optionnel)'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _communeName.isEmpty
                                ? 'Choisir une commune'
                                : _communeName,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: _communeName.isEmpty
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const Icon(Icons.expand_more,
                            color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingXL),
                Text(
                  'Votre identité de connexion',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingXS),
                Text(
                  'Elle vous servira à vous connecter à votre espace pro.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingM),
                AppButton(
                  text: 'S\'inscrire avec Google',
                  type: AppButtonType.secondary,
                  leading: const GoogleGLogo(),
                  onPressed: auth.isLoading ? null : _handleGoogle,
                ),
                if (_showApple) ...[
                  const SizedBox(height: AppTheme.spacingSM),
                  AppButton(
                    text: 'S\'inscrire avec Apple',
                    type: AppButtonType.secondary,
                    onPressed: auth.isLoading ? null : () {},
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
                        'ou par e-mail',
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
                if (!_codeSent) ...[
                  const SizedBox(height: AppTheme.spacingM),
                  AppButton(
                    text: 'Recevoir un code',
                    onPressed:
                        (auth.isLoading || !_emailValid) ? null : _sendCode,
                    isLoading: auth.isLoading,
                  ),
                ] else ...[
                  const SizedBox(height: AppTheme.spacingM),
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
                    ),
                  ],
                  const SizedBox(height: AppTheme.spacingM),
                  AppButton(
                    text: 'S\'inscrire',
                    onPressed: (auth.isLoading ||
                            _codeController.text.trim().length < 4)
                        ? null
                        : _handleEmailRegister,
                    isLoading: auth.isLoading,
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  AppButton(
                    text: 'Renvoyer le code',
                    type: AppButtonType.text,
                    onPressed: auth.isLoading ? null : _sendCode,
                  ),
                ],
                if (auth.error != null) ...[
                  const SizedBox(height: AppTheme.spacingSM),
                  Text(
                    auth.error!,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppTheme.spacingM),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Déjà un compte ? ',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('Se connecter'),
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
