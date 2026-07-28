import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/forms/field_errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/helpers.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/inline_feedback.dart';
import '../../../widgets/common/otp_code_row.dart';

class ProOtpVerifyScreen extends StatefulWidget {
  final String phoneNumber;
  final String? returnTo;

  const ProOtpVerifyScreen({
    super.key,
    required this.phoneNumber,
    this.returnTo,
  });

  @override
  State<ProOtpVerifyScreen> createState() => _ProOtpVerifyScreenState();
}

class _ProOtpVerifyScreenState extends State<ProOtpVerifyScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  bool _isLoading = false;

  // A7/§14 — the six-digit rule is the shared one, and its verdict renders
  // beside the boxes instead of in a bar that outlives the screen.
  late final _errors = FieldErrors({'code': Validators.otp});
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _startCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendCooldown = AppConstants.otpResendCooldownSeconds;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  /// The row hands back the whole code after every edit.
  ///
  /// A11 C3: focus advance used to be the only thing this did. Autofill, paste
  /// distribution and backspace now arrive with [OtpCodeRow] — this screen had
  /// none of the three — and with them the sixth digit can submit on its own,
  /// the way the consumer screen has always done.
  void _onCodeChanged(String code) {
    // §14 rule 2 — the review found the fault surviving a full retype and even
    // a « Renvoyer », so the screen kept accusing a code the user had replaced.
    if (_inlineError != null) setState(() => _inlineError = null);

    if (code.length == 6 && !_isLoading) _handleVerify();
  }

  Future<void> _handleVerify() async {
    final otp = _controllers.map((c) => c.text).join();
    // A7/§14 rule 3: an incomplete code is a FIELD fault. It used to be a
    // snackbar — a message about these six boxes, floating at the bottom of the
    // screen on a timer.
    if (!_errors.validate({'code': otp})) {
      setState(() => _inlineError = _errors['code']);
      return;
    }
    setState(() => _inlineError = null);

    setState(() => _isLoading = true);

    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    final success = await authProvider.verifyOtp(widget.phoneNumber, otp);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      if (widget.returnTo != null && widget.returnTo!.isNotEmpty) {
        context.go(Uri.decodeComponent(widget.returnTo!));
      } else {
        context.go('/pro/dashboard');
      }
    } else {
      // The server's verdict on the code belongs to the code, too (rule 1).
      setState(() => _inlineError = authProvider.error ?? 'Code invalide');
      for (var controller in _controllers) {
        controller.clear();
      }
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _handleResend() async {
    if (_resendCooldown > 0) return;

    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    final success = await authProvider.sendOtp(widget.phoneNumber);

    if (!mounted) return;

    if (success) {
      AppSnackBar.show(context, 'Code renvoyé avec succès',
          kind: SnackKind.success);
      _startCooldown();
    } else {
      AppSnackBar.show(context, authProvider.error ?? 'Erreur lors de l’envoi',
          kind: SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Vérification'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          // spacingM, not spacingL, and it is load-bearing rather than
          // cosmetic: the six flexed boxes are `(W − 2×pad − 40)/6`, so at
          // spacingL they come out **45.33dp at 360 — under §13.2's 48 floor,
          // and silently**, because nothing overflows. At spacingM they are
          // exactly 48.0. The padding is what buys the tap target.
          padding: const EdgeInsets.all(AppTheme.spacingM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppTheme.spacingXL),
              const Icon(
                Icons.lock_outline,
                size: AppTheme.iconXL,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppTheme.spacingL),
              Text(
                'Code de vérification',
                style: AppTextStyles.headlineMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacingS),
              Text(
                'Entrez le code envoyé au\n${Helpers.maskPhoneNumber(widget.phoneNumber)}',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacingXL),
              OtpCodeRow(
                controllers: _controllers,
                focusNodes: _focusNodes,
                onChanged: _onCodeChanged,
              ),
              // §14 rule 1, as close to "under the field" as six boxes allow:
              // the message sits with the thing it is about, and stays until
              // the code is fixed. `InlineFeedback` is a live region, so a
              // screen reader hears it — the snackbar it replaces was pruned
              // the moment this screen sat under anything modal (§15/A6).
              InlineFeedback(_inlineError),
              const SizedBox(height: AppTheme.spacingL),
              TextButton(
                // A rate limit, not validation — §14 rule 5's stated
                // exception, and the label says when it reopens.
                onPressed: _resendCooldown > 0 ? null : _handleResend,
                child: Text(
                  _resendCooldown > 0
                      ? 'Renvoyer dans 0:${_resendCooldown.toString().padLeft(2, '0')}'
                      : 'Renvoyer le code',
                ),
              ),
              const SizedBox(height: AppTheme.spacingXL),
              AppButton(
                text: 'Vérifier',
                onPressed: _isLoading ? null : _handleVerify,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
