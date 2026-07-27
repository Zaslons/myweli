import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';

/// Signing a pro in, before a screen mounts (A11).
///
/// **Why this is shared and the provider lists are not.** The `runAsync` block
/// below existed in **seven** places — `dashboard_role_test`,
/// `pro_profile_role_test`, `staff_shell_test`, `pro_notifications_bell_test`,
/// `revoked_session_test`, `pro_screens_golden_test`, and A11's layout gate
/// would have been the eighth. §11's rule is that a third inline copy is a
/// review failure; this one reached seven because it is *fiddly* rather than
/// long, and fiddly code is what gets pasted.
///
/// The three or four `ChangeNotifierProvider` lines beside it are **not**
/// duplication — they legitimately differ per screen, and abstracting them would
/// hide which providers a screen actually needs. Only the hard part moves.
///
/// **Why `runAsync`, and why a poll.** The mock services delay for
/// `AppConstants.mockDelay`, and `flutter_test` runs inside `FakeAsync` where a
/// real `Future.delayed` never completes — so the sign-in has to happen in real
/// async, outside the pumped frames. And `ProAuthProvider`'s constructor starts
/// its own load chain, which races an explicit await (single-flight), so the
/// only reliable signal is polling until the membership lands.
///
/// The loop bound is 60 × 50 ms = 3 s. It is a *ceiling*, not a wait: the poll
/// exits on the first satisfied tick. If it ever runs out, the assertion below
/// fails loudly rather than handing back a half-loaded provider — which is how a
/// screen test ends up red somewhere unrelated, three files away.
Future<ProAuthProvider> signInPro(
  WidgetTester tester, {
  String email = 'jean@salon-excellence.test',
}) async {
  late final ProAuthProvider auth;
  await tester.runAsync(() async {
    final mockAuth = serviceLocator.authService as MockAuthService;
    await mockAuth.requestProviderEmailOtp(email);
    final res = await mockAuth.verifyProviderEmailOtp(
      email,
      MockAuthService.demoOtp,
    );
    expect(res.signedIn, isTrue, reason: 'the mock refused the OTP for $email');

    auth = ProAuthProvider();
    for (var i = 0;
        i < 60 &&
            (auth.isLoading ||
                (auth.isAuthenticated && auth.membership == null));
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  expect(
    auth.isAuthenticated,
    isTrue,
    reason: 'the pro session never landed for $email — every assertion after '
        'this would be about a signed-out screen, which is a different screen',
  );
  return auth;
}
