import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/forms/field_errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../services/mock/mock_auth_service.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/otp_code_row.dart';

class OtpVerifyScreen extends StatefulWidget {
  final String phoneNumber;
  final String? returnTo;

  const OtpVerifyScreen({
    super.key,
    required this.phoneNumber,
    this.returnTo,
  });

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  bool _isLoading = false;

  /// Inline message shown under the boxes (null when there's none).
  String? _inlineError;

  /// Boxes turn red after a failed verification.
  bool _hasError = false;

  /// Code is locked (too many attempts) or resend-limited — must resend.
  bool _locked = false;

  /// Code expired — must resend.
  bool _expired = false;

  String get _otp => _controllers.map((c) => c.text).join();
  bool get _entryDisabled => _locked || _expired;

  /// §14 rule 5: NOT gated on the code's length. A lockout or an expired code
  /// is a rate limit, not validation — that one is a legitimate disable, and
  /// the screen says why. An incomplete code is answered, not prevented.
  bool get _canVerify => !_entryDisabled && !_isLoading;

  // A7: the six-digit rule is the shared one now. This screen used to carry
  // `_otp.length == 6` in two places and silently do nothing when it failed.
  late final _errors = FieldErrors({'code': Validators.otp});

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
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
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

  void _clearBoxes() {
    for (final c in _controllers) {
      c.clear();
    }
  }

  /// The row hands back the whole code after every edit; this decides what it
  /// means. Focus advance, paste distribution and backspace used to live here
  /// and now live in [OtpCodeRow] — the pro screen had none of the three.
  void _onCodeChanged(String code) {
    // Typing clears a prior error so the boxes/message reset as the user fixes.
    if (_hasError || _inlineError != null) {
      _hasError = false;
      _inlineError = null;
    }
    setState(() {});

    if (code.length == 6 && !_isLoading && !_entryDisabled) {
      _handleVerify();
    }
  }

  Future<void> _handleVerify() async {
    if (_entryDisabled) return;
    // It used to `return` silently on a short code — the press did nothing and
    // said nothing.
    if (!_errors.validate({'code': _otp})) {
      setState(() {
        _inlineError = _errors['code'];
        _hasError = true;
      });
      return;
    }

    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.verifyOtp(widget.phoneNumber, _otp);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      // Tell the OS the one-time code was used so it stops offering it.
      TextInput.finishAutofillContext();
      if (authProvider.user != null) {
        final favoritesProvider =
            Provider.of<FavoritesProvider>(context, listen: false);
        unawaited(favoritesProvider.loadFavorites(authProvider.user!.id));
      }
      if (widget.returnTo != null && widget.returnTo!.isNotEmpty) {
        context.go(Uri.decodeComponent(widget.returnTo!));
      } else {
        context.go('/home');
      }
      return;
    }

    final code = authProvider.otpErrorCode;
    setState(() {
      _inlineError = authProvider.error ?? 'Code invalide';
      _hasError = true;
      _locked = code == 'otp_locked' || code == 'otp_resend_limit';
      _expired = code == 'otp_expired';
    });
    _clearBoxes();
    if (!_entryDisabled) {
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _handleResend() async {
    if (_resendCooldown > 0) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.sendOtp(widget.phoneNumber);

    if (!mounted) return;

    if (success) {
      AppSnackBar.show(context, 'Code renvoyé avec succès',
          kind: SnackKind.success);
      setState(() {
        _inlineError = null;
        _hasError = false;
        _locked = false;
        _expired = false;
      });
      _clearBoxes();
      _focusNodes[0].requestFocus();
      _startCooldown();
    } else {
      final code = authProvider.otpErrorCode;
      setState(() {
        _inlineError = authProvider.error ?? 'Erreur lors de l’envoi';
        if (code == 'otp_resend_limit') _locked = true;
      });
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
          padding: const EdgeInsets.all(AppTheme.spacingL),
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
                enabled: !_entryDisabled,
                hasError: _hasError,
                onChanged: _onCodeChanged,
              ),
              if (_inlineError != null) ...[
                const SizedBox(height: AppTheme.spacingM),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _entryDisabled
                          ? Icons.shield_outlined
                          : Icons.error_outline,
                      size: AppTheme.iconXS,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: AppTheme.spacingS),
                    Flexible(
                      child: Text(
                        _inlineError!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppTheme.spacingL),
              TextButton(
                onPressed: _resendCooldown > 0 ? null : _handleResend,
                child: Text(
                  _resendCooldown > 0
                      ? 'Renvoyer dans 0:${_resendCooldown.toString().padLeft(2, '0')}'
                      : (_entryDisabled
                          ? 'Renvoyer un nouveau code'
                          : 'Renvoyer le code'),
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: AppTheme.spacingXS),
                Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppTheme.spacingS,
                      horizontal: AppTheme.spacingSM),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                  child: Text(
                    'Démo : code ${MockAuthService.demoOtp} (masqué en production)',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppTheme.spacingXL),
              AppButton(
                text: 'Vérifier',
                onPressed: _canVerify ? _handleVerify : null,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
