import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/helpers.dart';
import '../../../widgets/common/app_button.dart';

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

  void _onOtpChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  Future<void> _handleVerify() async {
    final otp = _controllers.map((c) => c.text).join();
    if (otp.length != 6) {
      Helpers.showSnackBar(context, 'Veuillez entrer le code complet', isError: true);
      return;
    }

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
      Helpers.showSnackBar(
        context,
        authProvider.error ?? 'Code invalide',
        isError: true,
      );
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
      Helpers.showSnackBar(context, 'Code renvoyé avec succès');
      _startCooldown();
    } else {
      Helpers.showSnackBar(
        context,
        authProvider.error ?? 'Erreur lors de l\'envoi',
        isError: true,
      );
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
              const SizedBox(height: 32),
              const Icon(
                Icons.lock_outline,
                size: 80,
                color: AppColors.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Code de vérification',
                style: AppTextStyles.headlineMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Entrez le code envoyé au\n${Helpers.maskPhoneNumber(widget.phoneNumber)}',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  return Container(
                    width: 50,
                    height: 64,
                    margin: EdgeInsets.only(
                      left: index == 0 ? 0 : 4,
                      right: index == 5 ? 0 : 4,
                    ),
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      textAlignVertical: TextAlignVertical.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      obscureText: false,
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.textPrimary,
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
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        isDense: false,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 2.5,
                          ),
                        ),
                        filled: true,
                        fillColor: AppColors.secondary,
                      ),
                      onChanged: (value) => _onOtpChanged(index, value),
                      onTap: () {
                        if (_controllers[index].text.isEmpty) {
                          _controllers[index].selection = const TextSelection.collapsed(
                            offset: 0,
                          );
                        }
                      },
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: _resendCooldown > 0 ? null : _handleResend,
                child: Text(
                  _resendCooldown > 0
                      ? 'Renvoyer dans 0:${_resendCooldown.toString().padLeft(2, '0')}'
                      : 'Renvoyer le code',
                ),
              ),
              const SizedBox(height: 32),
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
