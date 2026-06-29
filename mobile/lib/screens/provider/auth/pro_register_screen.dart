import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/provider_user.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/phone_number_field.dart';

class ProRegisterScreen extends StatefulWidget {
  const ProRegisterScreen({super.key});

  @override
  State<ProRegisterScreen> createState() => _ProRegisterScreenState();
}

class _ProRegisterScreenState extends State<ProRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  String _phoneNumber = '';
  final _addressController = TextEditingController();
  BusinessType? _selectedBusinessType;
  bool _isLoading = false;

  @override
  void dispose() {
    _businessNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBusinessType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un type d\'entreprise'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final phoneNumber = _phoneNumber;
    final businessName = _businessNameController.text.trim();
    final address = _addressController.text.trim();
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);

    final success = await authProvider.register(
      phoneNumber: phoneNumber,
      businessName: businessName,
      businessType: _selectedBusinessType!,
      address: address,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      unawaited(context
          .push('/pro/verify-otp?phone=${Uri.encodeComponent(phoneNumber)}'));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.error ?? 'Erreur lors de l\'inscription'),
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
                const SizedBox(height: 32),
                const Icon(
                  Icons.business_center,
                  size: 100,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Créez votre compte professionnel',
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Rejoignez Myweli Pro et gérez votre entreprise',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
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
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                PhoneNumberField(
                  onChanged: (e164) => _phoneNumber = e164,
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 24),
                AppButton(
                  text: 'S\'inscrire',
                  onPressed: _isLoading ? null : _handleRegister,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 16),
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
