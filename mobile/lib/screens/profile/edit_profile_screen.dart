import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';

import '../../core/forms/field_errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/phone_number_field.dart';
import '../../widgets/common/timed_cached_image.dart';
import '../../widgets/provider/mock_image_picker_sheet.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // A7/§14: the form's faults live here, not in a FormState. Declaration order
  // is the form's reading order — `firstErroredKey` walks it for the focus move.
  late final _errors = FieldErrors({
    'name': Validators.name,
    'email': Validators.optionalEmail,
    // Optional, as it always was here — A7's first pass made it required by
    // accident, which would have blocked a consumer with no number on file
    // from saving an unrelated edit.
    'phone': _optionalPhone,
  });
  static String? _optionalPhone(String value) =>
      value.trim().isEmpty ? null : Validators.phoneNumber(value);

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  late final _focusNodes = {'name': _nameFocus, 'email': _emailFocus};

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  // Contact phone (auth overhaul: unverified contact data, not the login).
  String _phone = '';
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null && !_prefilled) {
      _prefilled = true;
      _nameController.text = user.name ?? '';
      _emailController.text = user.email ?? '';
      _phone = user.phoneNumber ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(AuthProvider authProvider) async {
    final source = await showMockImagePicker(context);
    if (source == null || !mounted) return;
    final ok = await authProvider.uploadAvatar(source);
    if (!mounted) return;
    if (!ok) {
      AppSnackBar.show(context, authProvider.error ?? 'Échec de l’envoi',
          kind: SnackKind.error);
    }
  }

  Future<void> _submit() async {
    // §14 rule 5: the button was never disabled, so pressing it has to answer.
    final ok = _errors.validate({
      'name': _nameController.text,
      'email': _emailController.text,
      'phone': _phone,
    });
    setState(() {});
    if (!ok) {
      focusFirstError(_errors, _focusNodes);
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.updateUser(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phone,
    );

    if (!mounted) return;

    if (success) {
      context.pop();
      AppSnackBar.show(context, 'Profil mis à jour', kind: SnackKind.success);
    } else {
      AppSnackBar.show(
          context, authProvider.error ?? 'Erreur lors de la mise à jour',
          kind: SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Modifier le profil'),
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          final user = authProvider.user;

          if (user == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Connectez-vous pour modifier votre profil',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  AppButton(
                    text: 'Se connecter',
                    onPressed: () => context.go(
                        '/login?returnTo=${Uri.encodeComponent('/profile/edit')}'),
                    isFullWidth: false,
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppTheme.spacingM),
                Center(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: AppColors.surface,
                            child: user.avatarUrl == null
                                ? const Icon(Icons.person_outline,
                                    size: AppTheme.iconL,
                                    color: AppColors.textSecondary)
                                : ClipOval(
                                    child: TimedCachedImage(
                                      imageUrl: user.avatarUrl!,
                                      width: 88,
                                      height: 88,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                          ),
                          if (authProvider.isUploadingAvatar)
                            const Positioned.fill(
                              child: CircleAvatar(
                                radius: 44,
                                backgroundColor: Colors.black45,
                                child: SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: BrandLoader(
                                      size: AppTheme.iconS,
                                      fast: true,
                                      onDark: true),
                                ),
                              ),
                            ),
                        ],
                      ),
                      TextButton(
                        onPressed: authProvider.isUploadingAvatar
                            ? null
                            : () => _pickAvatar(authProvider),
                        child: Text(user.avatarUrl == null
                            ? 'Ajouter une photo'
                            : 'Changer la photo'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.spacingS),
                AppTextField(
                  label: 'Nom',
                  hint: 'Votre nom',
                  controller: _nameController,
                  focusNode: _nameFocus,
                  errorText: _errors['name'],
                  // Rule 2: silent until it has errored once, live after.
                  onChanged: (v) =>
                      setState(() => _errors.revalidate('name', v)),
                ),
                const SizedBox(height: AppTheme.spacingM),
                AppTextField(
                  label: 'Email',
                  hint: 'email@exemple.com (optionnel)',
                  controller: _emailController,
                  focusNode: _emailFocus,
                  errorText: _errors['email'],
                  onChanged: (v) =>
                      setState(() => _errors.revalidate('email', v)),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppTheme.spacingM),
                Text(
                  'Téléphone',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingS),
                // Contact phone — editable since the auth overhaul (the
                // salon uses it to reach the client; verified later via SMS).
                PhoneNumberField(
                  initialValue: user.phoneNumber,
                  errorText: _errors['phone'],
                  onChanged: (e164) {
                    _phone = e164;
                    setState(() => _errors.revalidate('phone', e164));
                  },
                ),
                if (user.phoneNumber != null && !user.phoneVerified) ...[
                  const SizedBox(height: AppTheme.spacingS),
                  Text(
                    'Non vérifié',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
                const SizedBox(height: AppTheme.spacingXL),
                AppButton(
                  text: 'Enregistrer',
                  onPressed: authProvider.isLoading ? null : _submit,
                  isLoading: authProvider.isLoading,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
