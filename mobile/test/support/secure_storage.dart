import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

/// Makes the session store answer "no session" instead of throwing.
///
/// The store is `flutter_secure_storage` — a platform channel with no
/// implementation in a test process. A real `read()` throws
/// `MissingPluginException`, `AuthProvider` catches it into `error`, and the
/// login screen dutifully renders that string **in red, on the screen**. The
/// other 34 widget tests never noticed, because they assert on finders; a golden
/// photographs everything, including the things nobody was looking at.
///
/// Stubbing it makes a signed-out session read as what it actually is: nothing.
///
/// **Why this file exists separately from `golden.dart` (A11).** It is not
/// optional for anyone calling `setupDependencyInjection()`: that wires
/// `MockAuthService(sessionStore: SecureSessionStore())`
/// (`core/di/dependency_injection.dart:101`), so the channel is reached whether
/// or not the test is a golden. `test/a11y/` needs it and is deliberately
/// **platform-agnostic**, while `golden.dart` imports `dart:io` for the platform
/// check and the SDK font cache. Same argument that moved `pinSurface` here one
/// commit ago: the shared body lives in `support/`, and `golden.dart` re-exports
/// so its twelve call sites do not move.
void stubSecureStorage() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'readAll':
            return <String, String>{};
          case 'containsKey':
            return false;
          default:
            return null; // read / write / delete
        }
      });
}
