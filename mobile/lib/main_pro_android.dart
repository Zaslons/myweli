import 'package:flutter/foundation.dart';

import 'main_pro.dart' show runProApp;
import 'screens/provider/android/pro_android_extensions.dart';

/// The Android Pro app (docs/design/pro-android-signup.md §5.1): the iOS
/// app's own wiring — `runProApp` — with what only Android has, from behind
/// the fence in `lib/screens/provider/android/`.
///
/// This is the ONE file outside the fence that imports it
/// (`pro_android_fence_test.dart`). `tool/release_build.sh` builds
/// `android pro` from here and `ios pro` from `main_pro.dart`; a dev run
/// with sign-up is `flutter run --flavor pro -t lib/main_pro_android.dart`.
void main() =>
    runProApp(extensions: proAndroidExtensionsFor(defaultTargetPlatform));
