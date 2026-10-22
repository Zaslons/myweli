/// The deposit percentage a form proposes when none has been chosen yet — a
/// stored 0 (docs/design/acompte-off-parity.md §2). Pinned to the web's
/// DEFAULT_DEPOSIT_PERCENT by web/tests.
const double kDefaultDepositPercentage = 0.30;

/// Whether the salon has CHOSEN its deposit policy (B7.7, decision 24): the
/// server answers every salon with defaults — deposits off, a stored 0 % — so
/// an answer is not a choice. A saved form always sends its percentage (the
/// default above when none was picked), so a choice is deposits on, or a
/// stored percentage above 0. docs/design/pro-app-batch7.md §2.7.
bool depositChosen({
  required bool depositRequired,
  required double percentage,
}) => depositRequired || percentage > 0;

/// Computes the acompte (deposit) due for a booking, honoring the provider's
/// policy. Returns 0 when the provider doesn't require a deposit. FCFA has no
/// minor unit, so the result is rounded to a whole franc.
double computeDeposit({
  required double total,
  required bool depositRequired,
  required double percentage,
}) {
  if (!depositRequired || total <= 0) return 0;
  return (total * percentage).roundToDouble();
}
