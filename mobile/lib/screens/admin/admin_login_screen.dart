import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/admin/admin_auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Admin console login (email + password — seeded super-admin; no self-signup).
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(AdminAuthProvider auth) async {
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
                Text('Myweli — Admin', style: AppTextStyles.headlineMedium),
                const SizedBox(height: AppTheme.spacingXS),
                Text(
                  'Console interne. Accès réservé à l’équipe.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                ),
                const SizedBox(height: AppTheme.spacingL),
                AppTextField(
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppTheme.spacingM),
                AppTextField(
                  label: 'Mot de passe',
                  controller: _password,
                  obscureText: true,
                ),
                if (auth.error != null) ...[
                  const SizedBox(height: AppTheme.spacingS),
                  Text(
                    auth.error!,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.error),
                  ),
                ],
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
