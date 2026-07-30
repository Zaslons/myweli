import 'package:flutter_test/flutter_test.dart';

/// Advances past the mocks' latency WITHOUT `pumpAndSettle`.
///
/// The mocks sleep `AppConstants.mockDelay` (300ms) and the loading state is an
/// infinitely-repeating Lottie (`BrandLoader`) — so `pumpAndSettle()` never
/// returns while a screen is loading. Both OTP screens make it worse still: a
/// `Timer.periodic(1s)` resend cooldown that runs for a full minute. 16 widget
/// test files already hand-roll this; it is the house idiom, named at last.
/// [rounds] = the number of SEQUENTIAL mock calls the screen chains before it
/// settles.
///
/// **Why this sits in `support/` rather than in `golden.dart` (A11).** It is a
/// pump idiom, not a photography one — the a11y suite needs it to pump a screen
/// at 360dp, and every one of the 16 hand-rolled copies predates goldens
/// entirely. `golden.dart` imports `dart:io` and carries the Linux-only
/// authority rule; `test/a11y/` deliberately runs the same assertions
/// everywhere, so it must not import that file. Same argument that moved
/// `pinSurface` and `stubSecureStorage` here; `golden.dart` re-exports, so no
/// existing call site moves.
Future<void> settleMocks(WidgetTester tester, {int rounds = 1}) async {
  await tester.pump();
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pump();
}
