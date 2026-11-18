import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/constants/app_constants.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/pro_app_extensions.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/pro_sign_up_fields.dart';
import 'package:myweli/models/provider_login_result.dart';
import 'package:myweli/models/provider_sign_up_result.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/android/pro_android_extensions.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/widgets/common/app_text_field.dart';
import 'package:myweli/widgets/provider/pro_salon_gate.dart';
import 'package:provider/provider.dart';

import 'pump_app.dart';

/// The Android sign-up's test world (docs/design/pro-android-signup.md §8.1
/// P4, P7, P16; §8.2): the real mock, with the refusals a test scripts and
/// the calls it counts — shared by the sign-up and the Android sign-in tests.

/// The sign-in's sentence for a scripted code, as `ApiAuthService` words it.
String sentenceFor(String code) => switch (code) {
  'otp_expired' => 'Code expiré. Demandez un nouveau code.',
  'otp_none' => 'Aucun code actif. Demandez un nouveau code.',
  'otp_invalid' => 'Code incorrect.',
  'otp_resend_limit' => 'Trop de demandes de code. Réessayez plus tard.',
  'invalid_phone' || 'invalid_input' => 'Numéro ou code invalide.',
  'provider_exists' => 'Un compte existe déjà pour ce numéro. Connectez-vous.',
  'invalid_email' => 'E-mail invalide.',
  'token_rejected' => 'Connexion impossible. Réessayez.',
  'network' => kNoConnectionMessage,
  'invitation_expired' =>
    'Cette invitation a expiré. Demandez au salon de la renvoyer.',
  _ => kGenericErrorMessage,
};

class ScriptedSignUpAuth extends MockAuthService {
  /// The check answers this refusal instead (once).
  String? checkRefusal;

  /// Register answers these refusals, one per call, before it creates.
  final List<String> registerRefusals = [];

  /// The next register creates the account, and its answer is lost (S12).
  bool loseNextRegister = false;

  /// The next code request is refused with this.
  String? sendRefusal;

  /// The next accept is refused with this.
  String? acceptRefusal;

  /// The next check waits for this.
  Completer<void>? holdCheck;

  int googleChecks = 0;
  int emailChecks = 0;
  int registers = 0;
  int codeRequests = 0;

  /// The pair the last e-mail sign-up used.
  (String, String)? lastEmailSignUp;

  void reset() {
    checkRefusal = null;
    registerRefusals.clear();
    loseNextRegister = false;
    sendRefusal = null;
    acceptRefusal = null;
    holdCheck = null;
    googleChecks = emailChecks = registers = codeRequests = 0;
    lastEmailSignUp = null;
    proGoogleEmail = MockAuthService.mockProGoogleEmail;
  }

  Future<ProviderSignUpResult?> _scriptedCheck() async {
    final hold = holdCheck;
    if (hold != null) {
      holdCheck = null;
      await hold.future;
    }
    final code = checkRefusal;
    if (code == null) return null;
    checkRefusal = null;
    await Future<void>.delayed(AppConstants.mockDelay);
    return ProviderSignUpFailure(
      code == 'cancelled' ? '' : sentenceFor(code),
      code: code,
      stage: ProSignUpStage.check,
    );
  }

  @override
  Future<ProviderSignUpResult> signUpProviderWithGoogle(
    ProSignUpFields fields,
  ) async {
    googleChecks++;
    return await _scriptedCheck() ??
        await super.signUpProviderWithGoogle(fields);
  }

  @override
  Future<ProviderSignUpResult> signUpProviderWithEmail(
    String email,
    String code,
    ProSignUpFields fields,
  ) async {
    emailChecks++;
    lastEmailSignUp = (email, code);
    return await _scriptedCheck() ??
        await super.signUpProviderWithEmail(email, code, fields);
  }

  @override
  Future<ProviderSignUpResult> registerProvider(
    InvitationProof proof,
    ProSignUpFields fields,
  ) async {
    registers++;
    if (registerRefusals.isNotEmpty) {
      final code = registerRefusals.removeAt(0);
      await Future<void>.delayed(AppConstants.mockDelay);
      return ProviderSignUpFailure(
        sentenceFor(code),
        code: code,
        stage: ProSignUpStage.register,
      );
    }
    final result = await super.registerProvider(proof, fields);
    if (loseNextRegister) {
      loseNextRegister = false;
      // The account exists; its answer never arrived.
      await logoutProvider();
      return const ProviderSignUpFailure(
        kNoConnectionMessage,
        code: 'network',
        stage: ProSignUpStage.register,
      );
    }
    return result;
  }

  @override
  Future<ApiResponse<String>> requestProviderEmailOtp(String email) async {
    codeRequests++;
    final code = sendRefusal;
    if (code != null) {
      sendRefusal = null;
      await Future<void>.delayed(AppConstants.mockDelay);
      return ApiResponse.error(sentenceFor(code), code: code);
    }
    return super.requestProviderEmailOtp(email);
  }

  @override
  Future<ApiResponse<ProviderUser>> acceptProviderInvitation(
    String invitationId,
    InvitationProof proof,
  ) async {
    final code = acceptRefusal;
    if (code != null) {
      acceptRefusal = null;
      await Future<void>.delayed(AppConstants.mockDelay);
      return ApiResponse.error(sentenceFor(code), code: code);
    }
    return super.acceptProviderInvitation(invitationId, proof);
  }
}

/// The Android Pro app's sign-in and sign-up, on a small router: the real
/// extensions (`proAndroidExtensionsFor(android)`), the sign-in, and the
/// landings as markers. [gate] puts the salon gate above the router, as
/// `main_pro.dart` does (P16).
class SignUpHarness {
  late GoRouter router;
  late ProAuthProvider auth;

  Widget app({bool gate = false}) {
    final android = proAndroidExtensionsFor(TargetPlatform.android)!;
    router = GoRouter(
      initialLocation: '/pro/login',
      routes: [
        GoRoute(path: '/pro/login', builder: (_, _) => const ProLoginScreen()),
        ...android.routes,
        GoRoute(
          path: '/pro/dashboard',
          builder: (_, _) => const Scaffold(body: Text('ACCUEIL')),
        ),
        GoRoute(
          path: '/pro/staff',
          builder: (_, _) => const Scaffold(body: Text('STAFF_SHELL')),
        ),
        GoRoute(
          path: '/pro/invitations',
          builder: (_, _) => const Scaffold(body: Text('REJOIN_GATE')),
        ),
      ],
    );
    auth = ProAuthProvider(router: router);
    return wrapApp(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        Provider<ProLoginExtras?>.value(value: android.login),
      ],
      routerConfig: router,
      builder: gate
          ? (context, child) => ProSalonGate(
              router: router,
              child: child ?? const SizedBox.shrink(),
            )
          : null,
    );
  }
}

/// Past the mock latency without `pumpAndSettle` (spinners never settle).
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pump();
}

/// The text field inside the `AppTextField` labelled [label].
Finder input(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AppTextField && w.label == label),
  matching: find.byType(TextField),
);

/// A tap on what [finder] finds, scrolled into view first.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}
