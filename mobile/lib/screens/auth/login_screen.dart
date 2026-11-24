import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/open_sign_in.dart';
import '../../core/config/feature_flags.dart';
import '../../core/constants/app_constants.dart';
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
import '../../widgets/common/apple_logo.dart';
import '../../widgets/common/google_g_logo.dart';
import '../../widgets/common/inline_feedback.dart';
import '../../widgets/common/legal_consent_text.dart';
import '../../widgets/common/phone_number_field.dart';
import '../../widgets/common/screen_title.dart';

/// Consumer sign-in — Google + Apple (flag-hidden) + email OTP, replacing the
/// phone-OTP login (auth overhaul P3; mirrors the web flow). After ANY
/// successful login where the account has no phone, a **mandatory contact
/// phone step** blocks until saved — the salon needs a number to reach the
/// client. Design: docs/design/app-auth-social.md.
///
/// **A detour the person can leave** (consumer-signin-push.md §2.1–§2.2): it
/// is pushed OVER the screen they were on (`openSignIn`), « Fermer » takes
/// them back there, and its opener hears whether they came back signed in
/// (`SignInGate`). With nothing beneath it, « Fermer » goes to Accueil and
/// success to [returnTo].
class LoginScreen extends StatefulWidget {
  /// Where success goes when nothing is beneath — an in-app path only
  /// (`safeReturnTo`).
  final String? returnTo;

  /// Why it opened: the line under « Bienvenue ».
  final SignInReason reason;

  const LoginScreen({
    super.key,
    this.returnTo,
    this.reason = SignInReason.none,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _LoginStep { options, code, phone }

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  _LoginStep _step = _LoginStep.options;
  String _phoneNumber = '';

  // A7/§14 — one e-mail rule, product-wide. This screen carried its own loose
  // copy (`[^@\s]+@[^@\s]+\.[^@\s]+`), one of four, which accepted a
  // single-character TLD the strict rule rejects.
  late final _errors = FieldErrors({
    'email': Validators.email,
    'code': Validators.otp,
    'phone': Validators.phoneNumber,
  });
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  late final _focusNodes = {'email': _emailFocus, 'code': _codeFocus};

  bool get _showApple =>
      FeatureFlags.appleSignIn && defaultTargetPlatform == TargetPlatform.iOS;

  /// Kept for [dispose], where `context.read` no longer works: whatever
  /// removed this screen, its opener hears whether the person is signed in.
  AuthProvider? _auth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auth = context.read<AuthProvider>();
  }

  @override
  void dispose() {
    SignInGate.answer(_auth?.isAuthenticated ?? false);
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// Post-login: block on the contact phone when the account has none.
  void _afterLogin(AuthProvider auth) {
    final user = auth.user;
    if (user != null &&
        (user.phoneNumber == null || user.phoneNumber!.isEmpty)) {
      setState(() => _step = _LoginStep.phone);
      return;
    }
    _finish();
  }

  void _finish() => _leave(signedIn: true);

  /// Leaves the sign-in. Pushed over a screen (the rule, §2.1): back to it,
  /// and the opener hears the answer AFTER the pop, so what it does next
  /// lands on that screen, not on this one. Nothing beneath: Accueil, or
  /// [LoginScreen.returnTo] once signed in.
  void _leave({required bool signedIn}) {
    if (context.canPop()) {
      context.pop(signedIn);
      SignInGate.answer(signedIn);
      return;
    }
    context.go(signedIn ? safeReturnTo(widget.returnTo) : '/home');
  }

  /// « Fermer », and the system back where it means the same (§2.2).
  Future<void> _close() async {
    if (context.read<AuthProvider>().isLoading) return;
    if (_step == _LoginStep.phone) {
      await _cancelPhoneStep();
      return;
    }
    _leave(signedIn: false);
  }

  /// The number is required for an account in the app (decision of
  /// 2026-07-02; decision 206): leaving this step cancels the sign-in. Said
  /// on the step before anyone taps; « Connexion annulée. » only once the
  /// sign-out really happened — a failed one leaves the person here, signed
  /// in, with its own sentence under the form.
  Future<void> _cancelPhoneStep() async {
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await auth.logout();
    if (!mounted || auth.isAuthenticated) return;
    _leave(signedIn: false);
    AppSnackBar.showOn(messenger, 'Connexion annulée.');
  }

  /// System back and the iOS swipe (§2.2). On the options step, with a
  /// screen beneath, they simply close it — the route pops itself, and
  /// [dispose] answers. On the code step, back returns to the e-mail; on the
  /// phone step it is « Fermer »; while a request runs it is ignored.
  void _onPop(bool didPop) {
    if (didPop) return;
    if (context.read<AuthProvider>().isLoading) return;
    switch (_step) {
      case _LoginStep.options:
        _leave(signedIn: false);
      case _LoginStep.code:
        setState(() => _step = _LoginStep.options);
      case _LoginStep.phone:
        _cancelPhoneStep();
    }
  }

  Future<void> _handleGoogle() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithGoogle();
    if (!mounted) return;
    if (ok) _afterLogin(auth);
  }

  Future<void> _handleApple() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithApple();
    if (!mounted) return;
    if (ok) _afterLogin(auth);
  }

  // Resend cooldown (module 11 — the dormant OTP screen's pattern).
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

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

  Future<void> _sendEmailCode() async {
    // §14 rule 5: the button is never disabled for validity, so it answers.
    if (!_errors.validate({'email': _emailController.text})) {
      setState(() {});
      focusFirstError(_errors, _focusNodes);
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.requestEmailOtp(_emailController.text.trim());
    if (!mounted) return;
    if (ok) {
      setState(() {
        _codeController.clear();
        // A new code: the last one's fault is not this one's.
        _errors.set('code', null);
        _step = _LoginStep.code;
      });
      _startCooldown();
      return;
    }
    // The e-mail's fault under the e-mail — when it is on screen; « Renvoyer
    // le code » is on the code step, where it is the form's.
    final fault = emailFieldFault(auth.otpErrorCode);
    if (fault != null && _step == _LoginStep.options) {
      setState(() => _errors.set('email', fault));
      focusFirstError(_errors, _focusNodes);
    }
  }

  /// What the form says under itself: the refusal, unless it belongs to a
  /// field on screen (sign_in_refusal.dart — the web's table).
  String? _formFault(AuthProvider auth) {
    final code = auth.otpErrorCode;
    if (_step == _LoginStep.code && codeFieldFault(code) != null) return null;
    if (_step == _LoginStep.options && emailFieldFault(code) != null) {
      return null;
    }
    return auth.error;
  }

  Future<void> _verifyEmailCode() async {
    if (!_errors.validate({'code': _codeController.text})) {
      setState(() {});
      focusFirstError(_errors, _focusNodes);
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyEmailOtp(
      _emailController.text.trim(),
      _codeController.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      _afterLogin(auth);
      return;
    }
    // « Code incorrect. » is the code's: under the code (SYSTEM §14 rule 1).
    final fault = codeFieldFault(auth.otpErrorCode);
    if (fault != null) {
      setState(() => _errors.set('code', fault));
      focusFirstError(_errors, _focusNodes);
    }
  }

  Future<void> _savePhone() async {
    // §14 rule 5 cuts both ways: A7 removed the `_phoneNumber.isEmpty` gate
    // that used to hold this step, and — the review's finding — put nothing
    // behind it. `'phone'` was declared and bound to an errorText that could
    // never populate, so one tap saved an EMPTY phone (the backend documents
    // `''` as "clear it", 200) and landed on /home. This is the app's only
    // enforcement of the mandatory contact number.
    if (!_errors.validate({'phone': _phoneNumber})) {
      setState(() {});
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateUser(phone: _phoneNumber);
    if (!mounted) return;
    if (ok) {
      _finish();
      return;
    }
    // The server is still the authority on the number (BACKEND.md §3.4). Its
    // `invalid_phone` used to land in the form-level slot as « Numéro ou code
    // invalide. » — on a screen with no code on it. It is the field's fault,
    // so it goes under the field (§14 rule 1).
    if (auth.updateErrorCode == 'invalid_phone') {
      setState(
        () => _errors.set('phone', 'Saisissez un numéro de téléphone valide.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return PopScope(
      // Only the options step, idle, with a screen beneath, lets the route
      // pop itself (and the iOS swipe with it). Every other case is decided
      // in [_onPop] — on the code and phone steps that turns the swipe off,
      // which is Flutter's rule for `canPop: false` (§2.2).
      canPop:
          !auth.isLoading && _step == _LoginStep.options && context.canPop(),
      onPopInvokedWithResult: (didPop, _) => _onPop(didPop),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          // A close, not a back arrow: the sign-in is a detour the person did
          // not ask for, and closing it cancels the detour (§2.2). Disabled
          // while a request runs: a sign-in that lands after the screen has
          // gone would leave them signed in while they believe they cancelled.
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Fermer',
            onPressed: auth.isLoading ? null : _close,
          ),
          title: const ScreenTitle('Connexion'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppTheme.spacingL),
                // Brand lockup (mark + MyWeli wordmark) — black on the light bg.
                SvgPicture.asset(
                  'assets/brand/myweli_lockup_vertical_black.svg',
                  height: 110,
                  semanticsLabel: 'MyWeli',
                ),
                const SizedBox(height: AppTheme.spacingL),
                ..._buildStep(auth),
                const SizedBox(height: AppTheme.spacingL),
                if (_step != _LoginStep.phone) const LegalConsentText(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStep(AuthProvider auth) {
    switch (_step) {
      case _LoginStep.options:
        return _optionsStep(auth);
      case _LoginStep.code:
        return _codeStep(auth);
      case _LoginStep.phone:
        return _phoneStep(auth);
    }
  }

  List<Widget> _optionsStep(AuthProvider auth) => [
    Text(
      'Bienvenue',
      style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimary),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: AppTheme.spacingS),
    Text(
      // Why it opened (§2.2) — « Connectez-vous pour réserver en quelques
      // secondes. » when nothing in particular.
      widget.reason.line,
      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: AppTheme.spacingXL),
    AppButton(
      text: 'Continuer avec Google',
      type: AppButtonType.secondary,
      leading: const GoogleGLogo(),
      onPressed: auth.isLoading ? null : _handleGoogle,
    ),
    if (_showApple) ...[
      const SizedBox(height: AppTheme.spacingSM),
      AppButton(
        text: 'Continuer avec Apple',
        leading: const AppleLogo(),
        onPressed: auth.isLoading ? null : _handleApple,
      ),
    ],
    const SizedBox(height: AppTheme.spacingL),
    Row(
      children: [
        const Expanded(child: Divider(color: AppColors.divider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
          child: Text(
            'ou',
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
      focusNode: _emailFocus,
      label: 'Votre e-mail',
      hint: 'exemple@email.com',
      keyboardType: TextInputType.emailAddress,
      errorText: _errors['email'],
      onChanged: (v) => setState(() => _errors.revalidate('email', v)),
    ),
    const SizedBox(height: AppTheme.spacingM),
    AppButton(
      text: 'Continuer avec e-mail',
      // §14 rule 5: disabled ONLY while submitting.
      onPressed: auth.isLoading ? null : _sendEmailCode,
      isLoading: auth.isLoading,
    ),
    // §14 rule 3 + §15: a server OUTCOME is form-level, not a field fault
    // — and `InlineFeedback` is a live region, which a hand-rolled red Text
    // never was.
    InlineFeedback(_formFault(auth)),
  ];

  List<Widget> _codeStep(AuthProvider auth) => [
    Text(
      'Entrez le code reçu par e-mail à ${_emailController.text.trim()}.',
      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: AppTheme.spacingL),
    AppTextField(
      controller: _codeController,
      focusNode: _codeFocus,
      label: 'Code à 6 chiffres',
      keyboardType: TextInputType.number,
      maxLength: 6,
      errorText: _errors['code'],
      onChanged: (v) => setState(() => _errors.revalidate('code', v)),
    ),
    if (auth.emailDevCode != null) ...[
      const SizedBox(height: AppTheme.spacingXS),
      Text(
        'Code (dev) : ${auth.emailDevCode}',
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
        textAlign: TextAlign.center,
      ),
    ],
    const SizedBox(height: AppTheme.spacingM),
    AppButton(
      text: 'Se connecter',
      // The gate said 4 on a field labelled « Code à 6 chiffres » with
      // maxLength 6 — a four-digit code walked through. Rule 5: disabled
      // only while submitting; the code's own rule answers under the field.
      onPressed: auth.isLoading ? null : _verifyEmailCode,
      isLoading: auth.isLoading,
    ),
    const SizedBox(height: AppTheme.spacingSM),
    AppButton(
      text: _resendCooldown > 0
          ? 'Renvoyer le code (${_resendCooldown}s)'
          : 'Renvoyer le code',
      type: AppButtonType.text,
      onPressed: (auth.isLoading || _resendCooldown > 0)
          ? null
          : _sendEmailCode,
    ),
    const SizedBox(height: AppTheme.spacingXS),
    AppButton(
      text: 'Changer d’e-mail',
      type: AppButtonType.text,
      onPressed: auth.isLoading
          ? null
          : () => setState(() => _step = _LoginStep.options),
    ),
    // §14 rule 3 + §15: a server OUTCOME is form-level, not a field fault
    // — and `InlineFeedback` is a live region, which a hand-rolled red Text
    // never was.
    InlineFeedback(_formFault(auth)),
  ];

  List<Widget> _phoneStep(AuthProvider auth) => [
    Text(
      'Votre numéro de téléphone',
      style: AppTextStyles.headlineMedium.copyWith(
        color: AppColors.textPrimary,
      ),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: AppTheme.spacingS),
    Text(
      'Le salon l’utilise pour vous contacter au sujet de vos rendez-vous.',
      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: AppTheme.spacingS),
    // Said before anyone taps « Fermer » (decision 206).
    Text(
      'Sans numéro, la connexion est annulée.',
      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: AppTheme.spacingL),
    PhoneNumberField(
      // A7 said this field sat outside any Form so the package's check
      // "could never run here". That was measured FALSE: IntlPhoneField
      // defaults to onUserInteraction and needs no Form, so it WAS judging
      // from the first keystroke and overwriting our message. It is
      // silenced at the widget now; FieldErrors is the only rule.
      errorText: _errors['phone'],
      // Normalized by the field: '' when nothing is typed, else E.164 with
      // no separator — what is checked here is what `PATCH /me` receives.
      onChanged: (e164) => setState(() {
        _phoneNumber = e164;
        _errors.revalidate('phone', e164);
      }),
    ),
    const SizedBox(height: AppTheme.spacingM),
    AppButton(
      text: 'Continuer',
      onPressed: auth.isLoading ? null : _savePhone,
      isLoading: auth.isLoading,
    ),
    // §14 rule 3 + §15: a server OUTCOME is form-level, not a field fault
    // — and `InlineFeedback` is a live region, which a hand-rolled red Text
    // never was. A refused NUMBER is a field fault: it is under the field
    // (`_savePhone`), not here as well.
    InlineFeedback(auth.updateErrorCode == 'invalid_phone' ? null : auth.error),
  ];
}
