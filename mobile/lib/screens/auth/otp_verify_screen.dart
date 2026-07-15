import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/helpers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../services/mock/mock_auth_service.dart';
import '../../widgets/common/app_button.dart';

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
  bool get _canVerify => _otp.length == 6 && !_entryDisabled && !_isLoading;

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

  void _onOtpChanged(int index, String value) {
    // Paste / autofill of multiple digits: distribute across the boxes.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i + index < 6 && i < digits.length; i++) {
        _controllers[index + i].text = digits[i];
      }
      final next = (index + digits.length).clamp(0, 5);
      _focusNodes[next].requestFocus();
    } else if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }

    // Typing clears a prior error so the boxes/message reset as the user fixes.
    if (_hasError || _inlineError != null) {
      _hasError = false;
      _inlineError = null;
    }
    setState(() {});

    if (_otp.length == 6 && !_isLoading && !_entryDisabled) {
      _handleVerify();
    }
  }

  KeyEventResult _onBoxKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _handleVerify() async {
    if (_otp.length != 6 || _entryDisabled) return;

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
      Helpers.showSnackBar(context, 'Code renvoyé avec succès');
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
        _inlineError = authProvider.error ?? 'Erreur lors de l\'envoi';
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
                size: 80,
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
              AutofillGroup(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, _buildOtpBox),
                ),
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
                      size: 16,
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

  Widget _buildOtpBox(int index) {
    final borderColor = _hasError ? AppColors.error : AppColors.borderStrong;
    return Container(
      width: 50,
      height: 64,
      margin: EdgeInsets.only(
        left: index == 0 ? 0 : AppTheme.spacingXS,
        right: index == 5 ? 0 : AppTheme.spacingXS,
      ),
      child: Focus(
        onKeyEvent: (node, event) => _onBoxKey(index, event),
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          enabled: !_entryDisabled,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          keyboardType: TextInputType.number,
          maxLength: index == 0 ? 6 : 1,
          // The OS delivers the SMS code to the first box; paste-distribution
          // (in _onOtpChanged) then fills the rest and auto-submits.
          autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
          style: AppTextStyles.headlineMedium.copyWith(
            color: _hasError ? AppColors.error : AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: 0,
            height: 1.2,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            counterText: '',
            contentPadding:
                const EdgeInsets.symmetric(vertical: AppTheme.spacingM),
            isDense: false,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              borderSide: BorderSide(color: borderColor, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              borderSide: BorderSide(color: borderColor, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              borderSide: const BorderSide(color: AppColors.border, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              borderSide: BorderSide(
                color: _hasError ? AppColors.error : AppColors.primary,
                width: 2.5,
              ),
            ),
            filled: true,
            fillColor: _entryDisabled ? AppColors.surface : AppColors.secondary,
          ),
          onChanged: (value) => _onOtpChanged(index, value),
        ),
      ),
    );
  }
}
