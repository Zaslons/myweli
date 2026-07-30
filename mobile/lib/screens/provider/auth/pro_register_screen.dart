import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/forms/field_errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../models/provider_user.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/auth_switch_prompt.dart';
import '../../../widgets/common/commune_picker_sheet.dart';
import '../../../widgets/common/google_g_logo.dart';
import '../../../widgets/common/legal_consent_text.dart';
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
  // A7/§14 — declaration order IS the form's reading order, and the funnel
  // validates one step at a time (that is what `validate`'s subset scoping is
  // for: the identity step must not fail business fields, or vice versa).
  late final _errors = FieldErrors({
    'businessName': Validators.requiredField('le nom de l’entreprise'),
    'businessType': Validators.requiredField('le type d’entreprise'),
    'phone': Validators.phoneNumber,
    'address': Validators.requiredField('l’adresse de l’entreprise'),
    'email': Validators.email,
    'code': Validators.otp,
  });
  final _businessNameFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  // `businessType` and `phone` have no text field of their own to focus, so
  // they are absent by design — `focusFirstError` no-ops for them and the
  // message still renders in place. Named here so the gap is a decision, not
  // an oversight (the review flagged it as one).
  late final _focusNodes = {
    'businessName': _businessNameFocus,
    'address': _addressFocus,
    'email': _emailFocus,
    'code': _codeFocus,
  };
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
    _businessNameFocus.dispose();
    _addressFocus.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// Business fields must be valid before ANY identity path fires — the
  /// backend registers identity + salon atomically in one call.
  /// The review found `email` and `code` declared as rules and **never
  /// validated** — A7 deleted both old gates (`!_emailValid`, `length < 4`)
  /// and put nothing behind them, so « Recevoir un code » and « S'inscrire »
  /// fired on anything.
  Future<void> _sendCodeChecked() async {
    if (!_errors.validate({'email': _emailController.text})) {
      setState(() {});
      focusFirstError(_errors, _focusNodes);
      return;
    }
    await _sendCode();
  }

  Future<void> _handleEmailRegisterChecked() async {
    if (!_errors.validate({'code': _codeController.text})) {
      setState(() {});
      focusFirstError(_errors, _focusNodes);
      return;
    }
    await _handleEmailRegister();
  }

  bool _validateBusinessFields() {
    // The phone used to be checked imperatively and answered with a BAR — a
    // field fault in a snackbar, which is exactly what §14 rule 3 forbids. It
    // is a field in this map now, like the other three.
    final ok = _errors.validate({
      'businessName': _businessNameController.text,
      'businessType': _selectedBusinessType?.name ?? '',
      'phone': _phoneNumber,
      'address': _addressController.text,
    });
    setState(() {});
    if (!ok) focusFirstError(_errors, _focusNodes);
    return ok;
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
      appBar: AppBar(title: const Text('Inscription Pro')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingL),
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
                label: 'Nom de l’entreprise',
                hint: 'Ex: Salon de Beauté Marie',
                controller: _businessNameController,
                focusNode: _businessNameFocus,
                prefixIcon: const Icon(Icons.store),
                errorText: _errors['businessName'],
                onChanged: (v) =>
                    setState(() => _errors.revalidate('businessName', v)),
              ),
              const SizedBox(height: AppTheme.spacingM),
              DropdownButtonFormField<BusinessType>(
                // A11 C8: without this the button sizes to its WIDEST item's
                // intrinsic width — « Institut de manucure » — and overflows
                // its field by 79px at 360dp × 200% text.
                isExpanded: true,
                // A12: `itemHeight` defaults to `kMinInteractiveDimension`
                // (48), a FIXED height around text — so at 200% « Salon de
                // beauté » wraps to two lines, needs 96dp and is clipped to 48
                // the moment the menu opens. A11 C8 fixed the BUTTON with
                // `isExpanded`; the items it lists were still frozen one level
                // down, and nothing could see it until `expectNoVerticalClip`.
                // `null` lets each item take its intrinsic height (§13.3).
                itemHeight: null,
                initialValue: _selectedBusinessType,
                decoration: InputDecoration(
                  labelText: 'Type d’entreprise',
                  prefixIcon: const Icon(Icons.category),
                  // The review: this fault was computed, blocked the submit,
                  // and rendered NOWHERE — a press that did literally nothing,
                  // which is worse than the disabled button rule 5 removed.
                  errorText: _errors['businessType'],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
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
                  return DropdownMenuItem(value: type, child: Text(label));
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedBusinessType = value;
                    _errors.revalidate('businessType', value?.name ?? '');
                  });
                },
              ),
              const SizedBox(height: AppTheme.spacingM),
              PhoneNumberField(
                label: 'Téléphone du salon',
                errorText: _errors['phone'],
                onChanged: (e164) {
                  _phoneNumber = e164;
                  setState(() => _errors.revalidate('phone', e164));
                },
              ),
              const SizedBox(height: AppTheme.spacingM),
              AppTextField(
                label: 'Adresse',
                hint: 'Adresse de l’entreprise',
                controller: _addressController,
                focusNode: _addressFocus,
                prefixIcon: const Icon(Icons.location_on),
                maxLines: 2,
                errorText: _errors['address'],
                onChanged: (v) =>
                    setState(() => _errors.revalidate('address', v)),
              ),
              const SizedBox(height: AppTheme.spacingS),
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
                text: 'S’inscrire avec Google',
                type: AppButtonType.secondary,
                leading: const GoogleGLogo(),
                onPressed: auth.isLoading ? null : _handleGoogle,
              ),
              if (_showApple) ...[
                const SizedBox(height: AppTheme.spacingSM),
                AppButton(
                  text: 'S’inscrire avec Apple',
                  type: AppButtonType.secondary,
                  onPressed: auth.isLoading ? null : () {},
                ),
              ],
              const SizedBox(height: AppTheme.spacingM),
              // L1 — **this funnel had no consent copy at all**, and it is the
              // one that precedes a KYC identity upload and a public business
              // listing. Placed ABOVE the « ou par e-mail » divider so it
              // governs both paths and is visible before any scroll: the Google
              // button above creates an account in one tap.
              const LegalConsentText(
                lead: 'En créant votre compte professionnel',
              ),
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
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                errorText: _errors['email'],
                onChanged: (v) =>
                    setState(() => _errors.revalidate('email', v)),
              ),
              if (!_codeSent) ...[
                const SizedBox(height: AppTheme.spacingM),
                AppButton(
                  text: 'Recevoir un code',
                  // §14 rule 5: disabled ONLY while submitting.
                  onPressed: auth.isLoading ? null : _sendCodeChecked,
                  isLoading: auth.isLoading,
                ),
              ] else ...[
                const SizedBox(height: AppTheme.spacingM),
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
                  ),
                ],
                const SizedBox(height: AppTheme.spacingM),
                AppButton(
                  text: 'S’inscrire',
                  // The gate said 4 on a field labelled « Code à 6 chiffres »
                  // with maxLength 6 — a four-digit code walked through.
                  // Rule 5: disabled only while submitting; the code's own
                  // rule now answers with a message under the field.
                  onPressed: auth.isLoading
                      ? null
                      : _handleEmailRegisterChecked,
                  isLoading: auth.isLoading,
                ),
                const SizedBox(height: AppTheme.spacingS),
                AppButton(
                  text: 'Renvoyer le code',
                  type: AppButtonType.text,
                  // The SAME defect, one button over — found writing the gate.
                  // The e-mail field stays editable on the code step, so this
                  // re-sent to whatever it now holds, unchecked.
                  onPressed: auth.isLoading ? null : _sendCodeChecked,
                ),
              ],
              if (auth.error != null) ...[
                const SizedBox(height: AppTheme.spacingSM),
                Text(
                  auth.error!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppTheme.spacingM),
              AuthSwitchPrompt(
                question: 'Déjà un compte ?',
                actionLabel: 'Se connecter',
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
