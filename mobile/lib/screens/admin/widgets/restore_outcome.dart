import 'package:flutter/material.dart';

import '../../../core/utils/validation_labels.dart';
import '../../../models/admin_salon_validation.dart';
import '../../../widgets/common/app_snack_bar.dart';

/// The snackbar after « Lever la suspension » (B0.18 —
/// docs/design/salon-go-live-approval.md §4.4), on the salons list and on a
/// salon's page alike.
///
/// - **Back online** — « Salon remis en ligne », a success. The server from
///   before B0.18 always answers that ([RestoreOutcome.legacy]: it writes
///   `active` unconditionally).
/// - **Lifted, still offline** — « Suspension levée — le salon reste hors
///   ligne : » and the reason's word. The lift DID succeed, so it is not an
///   error; nor is it the green of a salon back in front of clients: `info`.
/// - **Refused** (409 `not_suspended`, an unknown salon, offline): the
///   failure's own sentence, as an error.
void showRestoreOutcome(
  ScaffoldMessengerState messenger, {
  required bool ok,
  required RestoreOutcome? outcome,
  required String? error,
}) {
  if (!ok || outcome == null) {
    AppSnackBar.showOn(messenger, error ?? 'Échec', kind: SnackKind.error);
    return;
  }
  AppSnackBar.showOn(
    messenger,
    ValidationLabels.restoreMessage(outcome),
    kind: outcome.isLive ? SnackKind.success : SnackKind.info,
  );
}
