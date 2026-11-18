import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/pro_app_extensions.dart';
import '../../../providers/pro_auth_provider.dart';
import 'pro_sign_up_entry.dart';
import 'pro_sign_up_screen.dart';

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
/// On Android: the sign-up's route, and the sign-in's block that pushes it.
ProAppExtensions? proAndroidExtensionsFor(TargetPlatform platform) {
  if (platform != TargetPlatform.android) return null;
  return ProAppExtensions(
    routes: [
      GoRoute(
        path: kProSignUpPath,
        // S15: a stale push or a `returnTo` while signed in.
        redirect: (context, state) =>
            context.read<ProAuthProvider>().isAuthenticated
            ? '/pro/dashboard'
            : null,
        builder: (context, state) => ProSignUpScreen(
          carried: switch (state.extra) {
            final ProSignUpCarry carried => carried,
            _ => null,
          },
        ),
      ),
    ],
    login: ProLoginExtras(
      block:
          (
            context, {
            required bool noAccount,
            String? email,
            String? code,
            required VoidCallback onReturned,
          }) => ProSignUpEntry(
            noAccount: noAccount,
            email: email,
            code: code,
            onReturned: onReturned,
          ),
    ),
  );
}
