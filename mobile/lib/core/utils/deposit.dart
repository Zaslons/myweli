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
