import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/forms/field_errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/validators.dart';
import '../../providers/admin/admin_auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/inline_feedback.dart';

/// Admin console login (email + password — seeded super-admin; no self-signup).
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  // A7/§14: this screen had NO client-side validation of any kind — no Form,
  // no validator, not even an empty check. A blank submit made a round trip to
  // be told « Identifiants invalides », which is the server answering a
  // question the form could have answered itself.
  late final _errors = FieldErrors({
    'email': Validators.email,
    'password': Validators.requiredField('votre mot de passe'),
  });
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  late final _focusNodes = {'email': _emailFocus, 'password': _passwordFocus};

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit(AdminAuthProvider auth) async {
    final ok = _errors.validate({
      'email': _email.text,
      'password': _password.text,
    });
    setState(() {});
    if (!ok) {
      focusFirstError(_errors, _focusNodes);
      return;
    }
    await auth.login(_email.text, _password.text);
    // Navigation is handled by the router redirect on auth state change.
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AdminAuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingL),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('MyWeli — Admin', style: AppTextStyles.headlineMedium),
                const SizedBox(height: AppTheme.spacingXS),
                Text(
                  'Console interne. Accès réservé à l’équipe.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingL),
                AppTextField(
                  label: 'Email',
                  controller: _email,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  errorText: _errors['email'],
                  onChanged: (v) =>
                      setState(() => _errors.revalidate('email', v)),
                ),
                const SizedBox(height: AppTheme.spacingM),
                AppTextField(
                  label: 'Mot de passe',
                  controller: _password,
                  focusNode: _passwordFocus,
                  obscureText: true,
                  errorText: _errors['password'],
                  onChanged: (v) =>
                      setState(() => _errors.revalidate('password', v)),
                ),
                // §14 rule 3 + §15: « Identifiants invalides » is an OUTCOME,
                // not a field fault — and InlineFeedback is a live region,
                // which a bare red Text never was.
                InlineFeedback(auth.error),
                const SizedBox(height: AppTheme.spacingL),
                AppButton(
                  text: 'Se connecter',
                  isLoading: auth.isLoading,
                  onPressed: auth.isLoading ? null : () => _submit(auth),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
