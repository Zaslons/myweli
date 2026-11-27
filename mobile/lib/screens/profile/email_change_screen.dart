import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/open_sign_in.dart';
import '../../core/auth/reload_on_sign_in.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/failure_messages.dart';
import '../../core/forms/field_errors.dart';
import '../../core/forms/sign_in_refusal.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/inline_feedback.dart';
import '../../widgets/common/screen_title.dart';

/// « Changer d’adresse e-mail » (B16.3b — docs/design/account-email-change.md
/// §5.4, decisions 260–265). The address an account signs in with changes
/// only once the new one is proven, by a code sent to it — and, when the
/// current proven address is the account's only way in, by a second code sent
/// there (decision 265). Two steps, as the sign-in's e-mail: the address, then
/// the code(s). The words and parts are the sign-in's (`login_screen.dart`,
/// `sign_in_refusal.dart`).
///
/// [verifyCurrent] (« Vérifier », `?verifier=1`): the account's own unproven
/// address, filled in and its code sent at once — straight to the code.
class EmailChangeScreen extends StatefulWidget {
  const EmailChangeScreen({super.key, this.verifyCurrent = false});

  final bool verifyCurrent;

  @override
  State<EmailChangeScreen> createState() => _EmailChangeScreenState();
}

enum _Step { address, code }

class _EmailChangeScreenState extends State<EmailChangeScreen>
    with ReloadOnSignIn<EmailChangeScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _currentCodeController = TextEditingController();

  // §14: the faults live here. Declaration order is the reading order.
  late final _errors = FieldErrors({
    'email': Validators.email,
    'code': Validators.otp,
    'currentCode': Validators.otp,
  });
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _currentCodeFocus = FocusNode();
  late final _focusNodes = {
    'email': _emailFocus,
    'code': _codeFocus,
    'currentCode': _currentCodeFocus,
  };

  _Step _step = _Step.address;

  /// The address the code step is about: what the code went to, never what
  /// the field holds now.
  String _sentTo = '';

  /// The account's address when the screen opened — a « Vérifier » that
  /// proves it says so, not « mise à jour ».
  String? _openedWith;

  /// Which request is out: its button spins, and both are disabled (§14
  /// rule 5: only while submitting).
  bool _sending = false;
  bool _confirming = false;
  bool get _busy => _sending || _confirming;

  /// The form's slot (`InlineFeedback`): a refusal no field on screen owns.
  String? _formMessage;

  /// `email_taken` was answered: « Choisir une autre adresse » shows.
  bool _taken = false;

  bool _prefilled = false;

  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final user = context.read<AuthProvider>().user;
    _openedWith = user?.email?.toLowerCase();
    final own = user?.email;
    if (widget.verifyCurrent && own != null) {
      _emailController.text = own;
      // « Straight to its code »: the person asked to verify THIS address.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send();
      });
    }
  }

  /// Another account signed in over this screen: nothing typed here is
  /// theirs.
  @override
  void reloadForSignIn() {
    _cooldownTimer?.cancel();
    setState(() {
      _step = _Step.address;
      _sentTo = '';
      _openedWith = context.read<AuthProvider>().user?.email?.toLowerCase();
      _emailController.clear();
      _codeController.clear();
      _currentCodeController.clear();
      _errors.clear();
      _formMessage = null;
      _taken = false;
      _resendCooldown = 0;
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _currentCodeController.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    _currentCodeFocus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _resendCooldown = AppConstants.otpResendCooldownSeconds;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  /// Step 1's « Recevoir un code », and step 2's « Renvoyer le code ».
  Future<void> _send() async {
    // §14 rule 5: never disabled for validity, so the press answers.
    if (!_errors.validate({'email': _emailController.text})) {
      setState(() {});
      focusFirstError(_errors, _focusNodes);
      return;
    }
    final auth = context.read<AuthProvider>();
    final account = auth.user?.id;
    final email = _emailController.text.trim();
    setState(() {
      _sending = true;
      _formMessage = null;
      _taken = false;
    });
    final ok = await auth.requestEmailChange(email);
    if (!mounted) return;
    setState(() => _sending = false);
    // Another account by now: [reloadForSignIn] has reset the screen.
    if (auth.user?.id != account) return;
    if (ok) {
      setState(() {
        _sentTo = email;
        _codeController.clear();
        _currentCodeController.clear();
        // A new code: the last one's faults are not this one's.
        _errors.set('code', null);
        _errors.set('currentCode', null);
        _step = _Step.code;
      });
      _startCooldown();
      return;
    }
    final code = auth.emailChangeErrorCode;
    // The address's fault under the address — when it is on screen.
    final fault = changeEmailFieldFault(code);
    if (fault != null && _step == _Step.address) {
      setState(() => _errors.set('email', fault));
      focusFirstError(_errors, _focusNodes);
      return;
    }
    setState(
      () => _formMessage = switch (code) {
        'otp_resend_limit' ||
        'rate_limited' => 'Trop de demandes de code. Réessayez plus tard.',
        _ => auth.error ?? kGenericErrorMessage,
      },
    );
  }

  bool _needsCurrent(AuthProvider auth) =>
      auth.emailChange?.currentCodeSent ?? false;

  /// Step 2's « Confirmer ».
  Future<void> _confirm() async {
    final auth = context.read<AuthProvider>();
    final needsCurrent = _needsCurrent(auth);
    final values = {'code': _codeController.text};
    if (needsCurrent) values['currentCode'] = _currentCodeController.text;
    if (!_errors.validate(values)) {
      setState(() {});
      focusFirstError(_errors, _focusNodes);
      return;
    }
    final account = auth.user?.id;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _confirming = true;
      _formMessage = null;
      _taken = false;
    });
    final ok = await auth.confirmEmailChange(
      _sentTo,
      _codeController.text.trim(),
      currentCode: needsCurrent ? _currentCodeController.text.trim() : null,
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (auth.user?.id != account) return;
    if (ok) {
      final proved = _sentTo.toLowerCase() == _openedWith;
      navigator.pop();
      AppSnackBar.showOn(
        messenger,
        proved
            ? 'Adresse e-mail vérifiée.'
            : 'Adresse e-mail mise à jour. Connectez-vous désormais avec '
                  'celle-ci.',
        kind: SnackKind.success,
      );
      return;
    }
    final code = auth.emailChangeErrorCode;
    if (code == 'email_taken') {
      // Said only now, to whoever holds the inbox (decision 262).
      setState(() {
        _taken = true;
        _formMessage = kEmailTakenMessage;
      });
      return;
    }
    // Each code's refusal under its own field (§14).
    final newFault = codeFieldFault(code);
    if (newFault != null) {
      setState(() => _errors.set('code', newFault));
      focusFirstError(_errors, _focusNodes);
      return;
    }
    final currentFault = currentCodeFieldFault(code);
    if (currentFault != null && needsCurrent) {
      setState(() => _errors.set('currentCode', currentFault));
      focusFirstError(_errors, _focusNodes);
      return;
    }
    setState(() => _formMessage = auth.error ?? kGenericErrorMessage);
  }

  /// « Changer d’e-mail », and back on the code step: the address, kept.
  void _backToAddress() => setState(() {
    _step = _Step.address;
    _formMessage = null;
    _taken = false;
  });

  /// « Choisir une autre adresse »: the address step, the field cleared.
  void _chooseAnother() {
    setState(() {
      _step = _Step.address;
      _emailController.clear();
      _errors.set('email', null);
      _formMessage = null;
      _taken = false;
    });
    _emailFocus.requestFocus();
  }

  void _onPop(bool didPop) {
    if (didPop || _busy) return;
    if (_step == _Step.code) _backToAddress();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    return PopScope(
      // Back on the code step returns to the address; while a request runs
      // it is ignored, as at sign-in.
      canPop: _step == _Step.address && !_busy,
      onPopInvokedWithResult: (didPop, _) => _onPop(didPop),
      child: Scaffold(
        backgroundColor: AppColors.background,
        // The implied arrow stays with `canPop: false`: it calls `maybePop`,
        // which [_onPop] turns into the address step (measured, B16.3b).
        //
        // « Adresse e-mail », not §5.4's « Changer d’adresse e-mail »: that
        // did not fit a pushed bar at 360 dp and 200 % text (a15_titles_test,
        // SYSTEM.md §13.3). The row that opens it says the same words.
        appBar: AppBar(title: const ScreenTitle('Adresse e-mail')),
        body: SafeArea(
          child: user == null
              ? _signedOut(context)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.spacingL),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _step == _Step.address
                        ? _addressStep(auth)
                        : _codeStep(auth),
                  ),
                ),
        ),
      ),
    );
  }

  /// The session ended here: as « Modifier le profil » says it.
  Widget _signedOut(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.spacingL),
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
            onPressed: () =>
                openSignIn(GoRouter.of(context), reason: SignInReason.profile),
            isFullWidth: false,
          ),
        ],
      ),
    ),
  );

  List<Widget> _addressStep(AuthProvider auth) {
    final user = auth.user!;
    // Only a PROVEN address signs anyone in: with none, or an unproven one,
    // there is no « ancienne adresse » to lose.
    final losesOld = user.email != null && user.emailVerified;
    return [
      AppTextField(
        controller: _emailController,
        focusNode: _emailFocus,
        label: 'Nouvelle adresse e-mail',
        hint: 'exemple@email.com',
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        errorText: _errors['email'],
        onChanged: (v) => setState(() => _errors.revalidate('email', v)),
      ),
      const SizedBox(height: AppTheme.spacingM),
      AppButton(
        text: 'Recevoir un code',
        onPressed: _busy ? null : _send,
        isLoading: _sending,
      ),
      InlineFeedback(_formMessage),
      if (losesOld) ...[
        const SizedBox(height: AppTheme.spacingM),
        Text(
          'Vous ne pourrez plus vous connecter par code avec votre ancienne '
          'adresse.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ];
  }

  List<Widget> _codeStep(AuthProvider auth) {
    final needsCurrent = _needsCurrent(auth);
    final current = auth.user!.email;
    final devCode = auth.emailChange?.devCode;
    final currentDevCode = auth.emailChange?.currentDevCode;
    return [
      Text(
        'Entrez le code reçu par e-mail à $_sentTo.',
        style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
      ),
      const SizedBox(height: AppTheme.spacingM),
      AppTextField(
        controller: _codeController,
        focusNode: _codeFocus,
        // Two fields need two names; one keeps the sign-in's.
        label: needsCurrent
            ? 'Code de la nouvelle adresse'
            : 'Code à 6 chiffres',
        keyboardType: TextInputType.number,
        maxLength: 6,
        errorText: _errors['code'],
        onChanged: (v) => setState(() => _errors.revalidate('code', v)),
      ),
      if (devCode != null && devCode.isNotEmpty) _devHint(devCode),
      if (needsCurrent) ...[
        const SizedBox(height: AppTheme.spacingM),
        Text(
          'Entrez le code reçu à votre adresse actuelle, ${current ?? ''}.',
          style: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        AppTextField(
          controller: _currentCodeController,
          focusNode: _currentCodeFocus,
          label: 'Code de l’adresse actuelle',
          keyboardType: TextInputType.number,
          maxLength: 6,
          errorText: _errors['currentCode'],
          onChanged: (v) =>
              setState(() => _errors.revalidate('currentCode', v)),
        ),
        if (currentDevCode != null && currentDevCode.isNotEmpty)
          _devHint(currentDevCode),
      ],
      const SizedBox(height: AppTheme.spacingM),
      AppButton(
        text: 'Confirmer',
        onPressed: _busy ? null : _confirm,
        isLoading: _confirming,
      ),
      InlineFeedback(_formMessage),
      if (_taken) ...[
        const SizedBox(height: AppTheme.spacingS),
        // `InlineFeedback` has no action slot: the way on is its own button.
        AppButton(
          text: 'Choisir une autre adresse',
          type: AppButtonType.secondary,
          onPressed: _busy ? null : _chooseAnother,
        ),
      ],
      const SizedBox(height: AppTheme.spacingSM),
      AppButton(
        text: _resendCooldown > 0
            ? 'Renvoyer le code (${_resendCooldown}s)'
            : 'Renvoyer le code',
        type: AppButtonType.text,
        onPressed: (_busy || _resendCooldown > 0) ? null : _send,
        isLoading: _sending,
      ),
      const SizedBox(height: AppTheme.spacingXS),
      AppButton(
        text: 'Changer d’e-mail',
        type: AppButtonType.text,
        onPressed: _busy ? null : _backToAddress,
      ),
    ];
  }

  Widget _devHint(String code) => Padding(
    padding: const EdgeInsets.only(top: AppTheme.spacingXS),
    child: Text(
      'Code (dev) : $code',
      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
    ),
  );
}
