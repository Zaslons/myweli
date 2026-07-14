import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../utils/logger.dart';

/// Brings up the default Firebase app so push can work.
///
/// Returns whether push is live — and NEVER throws. Push is off (and the app
/// is completely unaffected) when:
///  - we're in demo mode (`USE_API_BACKEND` unset — there's no backend to
///    register a device with, and every `flutter test` run lands here), or
///  - we're on the web (no push by design — the install banner is the web's
///    substitute), or
///  - the platform config is missing or broken (a clone without
///    `google-services.json`, a misconfigured project). The app still runs;
///    it simply never receives a push.
///
/// Called from `main()` BEFORE `setupDependencyInjection()`, because the DI
/// wiring builds the FCM adapter (lazily) and `PushRegistration` subscribes to
/// its token stream.
///
/// Design: docs/design/push-notifications-app.md.
Future<bool> initFirebaseForPush() async {
  if (kIsWeb || !AppConfig.useApiBackend) return false;
  try {
    // No `options:` — Android reads the flavor's google-services.json and iOS
    // its GoogleService-Info.plist. That native config is what lets the OS
    // deliver a notification while the app is KILLED (no Dart runs then), so
    // it is the single source of truth; see the spec's "config strategy".
    await Firebase.initializeApp();
    return true;
  } catch (e, s) {
    AppLogger.error(
      'Firebase init failed — push disabled for this run',
      error: e,
      stackTrace: s,
    );
    return false;
  }
}
