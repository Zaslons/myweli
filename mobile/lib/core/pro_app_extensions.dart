import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// What one Pro app adds to the shared one (docs/design/pro-android-signup.md
/// §5.1, §5.2): the Android app's sign-up, which the iOS app must not carry.
///
/// **Shapes only.** No French text, no path literal: those live behind the
/// fence in `lib/screens/provider/android/`, which only
/// `lib/main_pro_android.dart` imports (`pro_android_fence_test.dart`). The
/// iOS app runs with none — `runProApp()` — and is today's app exactly.
class ProAppExtensions {
  const ProAppExtensions({this.routes = const [], this.login});

  /// Added to the router's own (`ProRouter.build`).
  final List<RouteBase> routes;

  /// The sign-in's block; null shows the sign-in as it is on iOS.
  final ProLoginExtras? login;
}

/// The sign-in screen's one block, at its bottom (§2.2), supplied by the
/// Android code.
///
/// - [noAccount]: a sign-in just answered `provider_not_found` (E2, E3). The
///   block then says that sentence, and the sign-in's own red feedback does
///   not repeat it.
/// - [email] and [code]: on the code step, the pair the refused verify used
///   (E3) — not the field, which stays editable.
/// - [onReturned]: the sign-in's reset, called when the page the block pushed
///   comes back (the options step, its feedback cleared).
typedef ProLoginBlockBuilder =
    Widget Function(
      BuildContext context, {
      required bool noAccount,
      String? email,
      String? code,
      required VoidCallback onReturned,
    });

class ProLoginExtras {
  const ProLoginExtras({required this.block});

  final ProLoginBlockBuilder block;
}
