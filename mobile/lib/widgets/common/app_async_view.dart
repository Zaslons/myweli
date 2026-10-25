import 'package:flutter/material.dart';

import '../../core/constants/failure_messages.dart';
import 'empty_state.dart';

/// An async section's four states, so a screen cannot forget one (SYSTEM.md
/// §12, §11.3; docs/design/hygiene-batch9.md §2.7.2, B9.8).
///
/// The order is `AdminDataTable`'s, the reference §11.2 names, and the one
/// every hand-written copy in the app already followed:
///
/// 1. there is content → [builder]. **It stays** through a reload and after a
///    refresh that failed: the user keeps what they were reading.
/// 2. loading, with nothing to show → [loading]: a skeleton where the shape
///    is known, the spinner where it is not (§12).
/// 3. an error, with nothing to show → [AppErrorView], the one error.
/// 4. nothing asked yet — no data, no error, not loading: the load starts
///    after this frame → [loading], never a flash of the empty state.
/// 5. asked, and empty → [empty], with its way forward.
///
/// [loading], [empty] and [builder] are required: each is a decision a screen
/// makes, not a default it inherits.
class AppAsyncView<T> extends StatelessWidget {
  const AppAsyncView({
    super.key,
    required this.isLoading,
    required this.error,
    required this.data,
    required this.isEmpty,
    required this.loading,
    required this.empty,
    required this.builder,
    this.onRetry,
  });

  final bool isLoading;

  /// The sentence to show when the load failed — already worded
  /// (`failure_messages.dart`, or a code's own sentence).
  final String? error;

  /// Null until the first answer.
  final T? data;
  final bool Function(T data) isEmpty;
  final Widget loading;
  final Widget empty;
  final Widget Function(BuildContext context, T data) builder;

  /// Null: the error offers no « Réessayer » — a retry that cannot succeed
  /// is not a way out (SYSTEM §12).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d != null && !isEmpty(d)) return builder(context, d);
    if (isLoading) return loading;
    final e = error;
    if (e != null) return AppErrorView(message: e, onRetry: onRetry);
    if (d == null) return loading;
    return empty;
  }
}

/// The one load error (B9.8, decision Q9): « Chargement impossible », the
/// failure's own sentence under it, the wifi-off icon only when nothing
/// answered — `kNoConnectionMessage` is the single sentence for that — and
/// « Réessayer » when the screen can retry. Titles and icons varied by screen
/// (« Chargement impossible » ×11, « Une erreur est survenue » ×6, …), and
/// the icon said nothing about the failure.
class AppErrorView extends StatelessWidget {
  const AppErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: message == kNoConnectionMessage
        ? Icons.wifi_off
        : Icons.error_outline,
    title: 'Chargement impossible',
    description: message,
    actionText: onRetry == null ? null : 'Réessayer',
    onAction: onRetry,
  );
}
