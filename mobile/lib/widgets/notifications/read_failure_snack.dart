import 'package:flutter/material.dart';

import '../common/app_snack_bar.dart';

/// The « marquer comme lu » failure on screen, if any — shared by a row's
/// touch and « Tout marquer comme lu », so the NEXT attempt takes it down
/// (docs/design/app-failure-messages.md §2.3, B3.3). Before, a retry that
/// worked stayed under the failure's 6 s, which said the opposite.
class ReadFailureSnack {
  ReadFailureSnack._();

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _shown;

  /// Where it was shown. A screen that went (a sign-out rebuilds the app)
  /// disposes its messenger, and closing a snackbar there throws — so [hide]
  /// only closes it while that messenger is still mounted.
  static ScaffoldMessengerState? _on;

  static void show(ScaffoldMessengerState messenger, String message) {
    final controller = AppSnackBar.showOn(
      messenger,
      message,
      kind: SnackKind.error,
    );
    _shown = controller;
    _on = messenger;
    // Forgotten as soon as it goes — on its own, or replaced by another
    // message (`showOn` removes the current one first) — so [hide] never
    // closes a snackbar that is not this one.
    controller.closed.then((_) {
      if (identical(_shown, controller)) _shown = null;
    });
  }

  /// A new attempt starts: the last failure is no longer the news.
  static void hide() {
    final shown = _shown;
    final on = _on;
    _shown = null;
    _on = null;
    if (shown != null && on != null && on.mounted) shown.close();
  }
}
