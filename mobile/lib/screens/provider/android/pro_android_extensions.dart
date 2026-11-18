import 'package:flutter/foundation.dart';

import '../../../core/pro_app_extensions.dart';

/// What the Android Pro app adds to the shared one
/// (docs/design/pro-android-signup.md §5.1, §5.3).
///
/// **The fence.** This folder, `lib/screens/provider/android/`, is reached
/// from `lib/main_pro_android.dart` only: the iOS entry `lib/main_pro.dart`
/// never imports it, so nothing here is in the iOS binary Apple reads
/// (App Store 3.1.1 refused 0.0.1 for signing salons up in the app).
/// `test/infra/pro_android_fence_test.dart` is the guard.
///
/// **Null unless [platform] is Android** (§5.1, « Defence in depth »): an iOS
/// build made from the wrong entry by hand shows nothing.
///
/// **B0.17 PR A: null on every platform.** PR A builds the fence with nothing
/// behind it — no behaviour changes on either app. PR B returns, for Android,
/// the `/pro/register` route and the sign-in's block (§5.3).
ProAppExtensions? proAndroidExtensionsFor(TargetPlatform platform) {
  if (platform != TargetPlatform.android) return null;
  return null;
}
