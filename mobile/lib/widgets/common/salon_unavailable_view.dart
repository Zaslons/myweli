import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/booking_error_cta.dart';
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
  const SalonUnavailableView({super.key, this.errorCode, this.onRetry});

  /// From `ProviderProvider.errorCode` — `not_found` · `network` ·
  /// `server_error`. Null falls to the retryable arm, which is the safe
  /// default: an unrecognised failure is not proof that retrying is futile.
  final String? errorCode;

  /// Offered only when [salonLoadFailure] says retrying can succeed.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = salonLoadFailure(errorCode);
    final cta = failure.cta;
    return EmptyState(
      icon: failure.icon,
      title: failure.message,
      actionText: cta?.label ?? (onRetry == null ? null : 'Réessayer'),
      onAction: cta != null ? () => context.go(cta.href) : onRetry,
    );
  }
}
