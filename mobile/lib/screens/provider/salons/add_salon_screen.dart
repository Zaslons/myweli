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

/// « Ajouter un salon » (module `access` R6 — docs/design/
/// team-access-r6-multi-salons.md §6): the second-salon form, reached from
/// the Réseau offer card or the « Mes salons » switcher. Réseau-gated
/// SERVER-side (403 `reseau_required` / 409 `salon_limit` — the codes render
/// through the shared French table). Success switches to the new DRAFT
/// salon and lands on its onboarding checklist — the same setup arc as the
/// first salon.
class AddSalonScreen extends StatefulWidget {
  const AddSalonScreen({super.key});

  @override
  State<AddSalonScreen> createState() => _AddSalonScreenState();
}

class _AddSalonScreenState extends State<AddSalonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  BusinessType? _businessType = BusinessType.salon;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // The account's contact number is the sensible default (editable —
    // a second salon often has its own line).
    _phoneController.text =
        context.read<ProAuthProvider>().provider?.phoneNumber ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final auth = context.read<ProAuthProvider>();
    final created = await auth.addSalon(
      businessName: _nameController.text.trim(),
      businessType: _businessType ?? BusinessType.salon,
      phoneNumber: _phoneController.text.trim(),
      address: _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (created == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Création du salon impossible.'),
        ),
      );
      return;
    }
    // Switched to the new draft — its setup checklist is the next step.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('« ${created.salonName} » créé.')),
    );
    context.go('/pro/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Ajouter un salon')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Un salon de plus dans votre compte',
                  style: AppTextStyles.headlineSmall,
                ),
                const SizedBox(height: AppTheme.spacingS),
                Text(
                  'Le nouveau salon démarre en brouillon avec sa propre '
                  'configuration : fiche, catalogue, équipe, offre et '
                  'période d\'essai.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingL),
                AppTextField(
                  label: 'Nom du salon',
                  hint: 'Ex: Salon Excellence Yopougon',
                  controller: _nameController,
                  prefixIcon: const Icon(Icons.store),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Le nom du salon est requis';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.spacingM),
                DropdownButtonFormField<BusinessType>(
                  initialValue: _businessType,
                  decoration: InputDecoration(
                    labelText: 'Type d\'entreprise',
                    prefixIcon: const Icon(Icons.category),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                  ),
                  items: BusinessType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(_typeLabel(type)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _businessType = value),
                  validator: (value) =>
                      value == null ? 'Veuillez sélectionner un type' : null,
                ),
                const SizedBox(height: AppTheme.spacingM),
                AppTextField(
                  label: 'Téléphone du salon',
                  hint: '+225 XX XX XX XX XX',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: const Icon(Icons.phone),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Le téléphone du salon est requis';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.spacingM),
                AppTextField(
                  label: 'Adresse (optionnel)',
                  hint: 'Quartier, commune…',
                  controller: _addressController,
                  prefixIcon: const Icon(Icons.location_on_outlined),
                ),
                const SizedBox(height: AppTheme.spacingL),
                Consumer<ProAuthProvider>(
                  builder: (context, auth, _) => AppButton(
                    text: 'Créer le salon',
                    isLoading: _submitting || auth.isLoading,
                    onPressed: _submit,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingM),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: AppTheme.spacingS),
                    Expanded(
                      child: Text(
                        'Réservé à l\'offre Réseau. Le badge « Vérifié » de '
                        'votre compte s\'applique automatiquement au nouveau '
                        'salon.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
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

  String _typeLabel(BusinessType type) => switch (type) {
        BusinessType.salon => 'Salon de beauté',
        BusinessType.barber => 'Barbier',
        BusinessType.spa => 'Spa',
        BusinessType.nailSalon => 'Institut de manucure',
        BusinessType.massage => 'Massage',
        BusinessType.other => 'Autre',
      };
}
