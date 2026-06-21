/// The deposit consequence of cancelling an appointment at a given moment.
class CancellationOutcome {
  /// True when cancelling now falls inside the provider's cancellation window
  /// (i.e. a late cancellation).
  final bool isLate;

  /// True when the deposit would be forfeited (a late cancellation with a
  /// deposit actually paid).
  final bool depositForfeited;

  const CancellationOutcome({
    required this.isLate,
    required this.depositForfeited,
  });
}

/// Whether cancelling [appointmentDate] at [now] is within the
/// [windowHours]-hour cancellation window, and what that implies for a paid
/// [depositAmount]. Cancelling exactly at or after the cutoff counts as late.
CancellationOutcome cancellationOutcome({
  required DateTime appointmentDate,
  required DateTime now,
  required int windowHours,
  required double depositAmount,
}) {
  final cutoff = appointmentDate.subtract(Duration(hours: windowHours));
  final isLate = !now.isBefore(cutoff);
  return CancellationOutcome(
    isLate: isLate,
    depositForfeited: isLate && depositAmount > 0,
  );
}
