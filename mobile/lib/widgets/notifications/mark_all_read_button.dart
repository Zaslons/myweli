import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/notifications_provider.dart';
import '../common/app_snack_bar.dart';

/// « Tout marquer comme lu » — the app-bar action of BOTH notification centres
/// (the consumer's `/notifications`, the pro's `/pro/notifications`), which
/// used to carry a copy each. It lives beside [NotificationsList], the feed
/// they already share, so a fix cannot reach one screen and miss the other.
///
/// Shown only while something is unread. The gesture is optimistic: the rows
/// turn read and the action disappears at once. If the server does not take
/// it, the rows THIS gesture marked are unread again, the action is back, and
/// a snackbar says why — while the feed is still the screen on top.
/// Design: docs/design/app-notifications-read-revert.md §3.2 ②.
class MarkAllReadButton extends StatefulWidget {
  const MarkAllReadButton({super.key});

  @override
  State<MarkAllReadButton> createState() => _MarkAllReadButtonState();
}

class _MarkAllReadButtonState extends State<MarkAllReadButton> {
  // Owned here, not by the IconButton: the button unmounts while the write is
  // out, and this node is how the focus finds it again when it comes back.
  final FocusNode _focus = FocusNode(debugLabel: 'Tout marquer comme lu');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _markAll(NotificationsProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    // A finger never focuses a Material button; a keyboard activation does.
    final hadFocus = _focus.hasPrimaryFocus;
    final failure = await provider.markAllRead();
    if (failure == null || !mounted) return;
    if (ModalRoute.isCurrentOf(context) ?? true) {
      AppSnackBar.showOn(messenger, failure, kind: SnackKind.error);
    }
    // The focus fell with the button. It comes back with it — only if it is
    // still nowhere in particular: never stolen from what was focused since.
    if (hadFocus && FocusManager.instance.primaryFocus is FocusScopeNode) {
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationsProvider>(
      builder: (context, provider, _) {
        if (provider.unreadCount == 0) return const SizedBox.shrink();
        // A15 (§21 row 79) — an icon, not a label. An action's text is
        // scaled by the FULL system scaler while the title is clamped to
        // 1.34× (`app_bar.dart:1092`), so a `TextButton` here costs
        // ~137dp at 2× and leaves the title under 176. Measured in
        // `primitives_test.dart`: with a text action, « Avis » — four
        // characters — cannot fit. The tooltip is also free to be
        // CLEARER than the label was, because it has the whole screen.
        return IconButton(
          focusNode: _focus,
          onPressed: () => _markAll(provider),
          icon: const Icon(Icons.done_all),
          tooltip: 'Tout marquer comme lu',
        );
      },
    );
  }
}
