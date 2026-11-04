import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/failure_messages.dart';
import '../../core/utils/booking_error_cta.dart';
import 'app_async_view.dart';
import 'empty_state.dart';

/// The §12 error state for a screen whose whole subject is one salon.
///
/// **Three screens rendered three different things for the same failure**
/// before PR1d: the salon detail hand-rolled a `Center`/`Column` with a red
/// `error_outline` and a « Retour » that popped to nothing on a deep link; the
/// booking hub rendered a bare centred grey sentence with no icon and no way
/// out at all; and the booking CONFIRMATION — the screen immediately before
/// payment — had no error branch whatsoever and spun forever.
///
/// Decision C is what makes that reachable: `GET /providers/{id}` now 404s a
/// salon that is `draft` or `suspended`, so « the salon this screen is about is
/// gone » stops being a theoretical state.
///
/// **Why the sentence is the title and there is no description.** §17 forbids
/// minting « Salon indisponible » purely to have a heading; the sentence is 41
/// characters and says the whole thing.
class SalonUnavailableView extends StatelessWidget {
  const SalonUnavailableView({
    super.key,
    this.errorCode,
    this.message,
    this.onRetry,
  });

  /// From `ProviderProvider.errorCode` — `not_found` · `network` ·
  /// `server_error`. Anything but `not_found` is a load that failed, and
  /// falls to the shared error, which retries: the safe default, since an
  /// unrecognised failure is not proof that retrying is futile.
  final String? errorCode;

  /// The failure's own sentence (`ProviderProvider.error`) — « Pas de
  /// connexion » only when nothing answered.
  final String? message;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final gone = salonLoadFailure(errorCode);
    if (gone == null) {
      return AppErrorView(
        message: message ?? kGenericErrorMessage,
        onRetry: onRetry,
      );
    }
    return EmptyState(
      icon: gone.icon,
      title: gone.message,
      actionText: gone.cta.label,
      onAction: () => context.go(gone.cta.href),
    );
  }
}
