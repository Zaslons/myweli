import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/design/product-questions-batch8.md §2.5 (B8.5, decision 31) — the Pro
/// phone sign-in is gone from the app. Its screen was never routed, and its
/// sign-in skipped what every other one does (the membership, « Mes
/// salons »). The server routes are removed; nothing here may call them.
void main() {
  final sources = [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ];

  test('no screen, no session method, no service method, no route', () {
    expect(
      File('lib/screens/provider/auth/pro_otp_verify_screen.dart').existsSync(),
      isFalse,
    );
    final hits = [
      for (final f in sources)
        if (RegExp(
          r'sendOtpToProvider|verifyOtpForProvider|ProOtpVerifyScreen|'
          r'/auth/provider/otp',
        ).hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(hits, isEmpty);
  });

  test('ProAuthProvider signs in by e-mail, Google or Apple only', () {
    final src = File('lib/providers/pro_auth_provider.dart').readAsStringSync();
    expect(src, isNot(contains('Future<bool> sendOtp(')));
    expect(src, isNot(contains('Future<bool> verifyOtp(')));
  });

  test('CONTROL: the client app keeps its phone sign-in', () {
    final src = File('lib/providers/auth_provider.dart').readAsStringSync();
    expect(src, contains('verifyOtp('));
  });
}
