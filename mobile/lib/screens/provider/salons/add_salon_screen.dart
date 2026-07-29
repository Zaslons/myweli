import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/forms/field_errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../models/provider_user.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/commune_picker_sheet.dart';

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
  // A7/§14 — the form's faults, in the form's reading order.
  late final _errors = FieldErrors({
    'name': Validators.requiredField('le nom du salon'),
    'type': Validators.requiredField('le type d’entreprise'),
    'phone': Validators.phoneNumber,
  });
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  late final _focusNodes = {'name': _nameFocus, 'phone': _phoneFocus};
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  BusinessType? _businessType = BusinessType.salon;
  bool _submitting = false;

  /// Multi-pays MP2: the optional locality pick at creation — the server
  /// derives the salon's commune/city/timezone/currency from it (T57).
  String? _areaId;
  String _communeName = '';

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
    _nameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

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

  Future<void> _submit() async {
    // §14 rule 5: the button is never disabled for validity, so it answers.
    final ok = _errors.validate({
      'name': _nameController.text,
      'type': _businessType?.name ?? '',
      'phone': _phoneController.text,
    });
    setState(() {});
    if (!ok) {
      focusFirstError(_errors, _focusNodes);
      return;
    }
    setState(() => _submitting = true);
    final auth = context.read<ProAuthProvider>();
    final created = await auth.addSalon(
      businessName: _nameController.text.trim(),
      businessType: _businessType ?? BusinessType.salon,
      phoneNumber: _phoneController.text.trim(),
      address: _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim(),
      areaId: _areaId,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (created == null) {
      AppSnackBar.show(context, auth.error ?? 'Création du salon impossible.',
          kind: SnackKind.error);
      return;
    }
    // Switched to the new draft — its setup checklist is the next step.
    AppSnackBar.show(context, '« ${created.salonName} » créé.',
        kind: SnackKind.success);
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
                'période d’essai.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppTheme.spacingL),
              AppTextField(
                label: 'Nom du salon',
                hint: 'Ex: Salon Excellence Yopougon',
                controller: _nameController,
                focusNode: _nameFocus,
                prefixIcon: const Icon(Icons.store),
                errorText: _errors['name'],
                onChanged: (v) => setState(() => _errors.revalidate('name', v)),
              ),
              const SizedBox(height: AppTheme.spacingM),
              DropdownButtonFormField<BusinessType>(
                // A11 C8 — see pro_register_screen.dart. Same field, same
                // items, same overflow.
                isExpanded: true,
                // A12: `itemHeight` defaults to `kMinInteractiveDimension`
                // (48), a FIXED height around text — so at 200% « Salon de
                // beauté » wraps to two lines, needs 96dp and is clipped to 48
                // the moment the menu opens. A11 C8 fixed the BUTTON with
                // `isExpanded`; the items it lists were still frozen one level
                // down, and nothing could see it until `expectNoVerticalClip`.
                // `null` lets each item take its intrinsic height (§13.3).
                itemHeight: null,
                initialValue: _businessType,
                decoration: InputDecoration(
                  labelText: 'Type d’entreprise',
                  prefixIcon: const Icon(Icons.category),
                  errorText: _errors['type'],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
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
                onChanged: (value) => setState(() {
                  _businessType = value;
                  _errors.revalidate('type', value?.name ?? '');
                }),
              ),
              const SizedBox(height: AppTheme.spacingM),
              AppTextField(
                label: 'Téléphone du salon',
                hint: '+225 XX XX XX XX XX',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                focusNode: _phoneFocus,
                prefixIcon: const Icon(Icons.phone),
                // A7: this was a bare "required" — the hint has always shown
                // a full number and nothing ever checked the shape.
                errorText: _errors['phone'],
                onChanged: (v) =>
                    setState(() => _errors.revalidate('phone', v)),
              ),
              const SizedBox(height: AppTheme.spacingM),
              AppTextField(
                label: 'Adresse (optionnel)',
                hint: 'Rue, repère…',
                controller: _addressController,
                prefixIcon: const Icon(Icons.location_on_outlined),
              ),
              const SizedBox(height: AppTheme.spacingM),
              InkWell(
                onTap: _pickCommune,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Commune (optionnel)',
                  ),
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
                      const Icon(
                        Icons.expand_more,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
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
                    size: AppTheme.iconS,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: AppTheme.spacingS),
                  Expanded(
                    child: Text(
                      'Réservé à l’offre Réseau. Le badge « Vérifié » de '
                      'votre compte s’applique automatiquement au nouveau '
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
