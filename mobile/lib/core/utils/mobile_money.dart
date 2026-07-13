/// Builds a Wave deep link that pre-fills the recipient + amount, so the client
/// only has to confirm with their PIN.
///
/// NOTE: confirm the exact Wave link format against Wave's live docs before
/// launch — the copyable number + amount is the guaranteed fallback for every
/// operator, so an imperfect link never blocks payment.
Uri? waveDeepLink({required String number, required double amount}) {
  final digits = number.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  return Uri.parse(
      'https://pay.wave.com/?recipient=$digits&amount=${amount.round()}');
}

/// Whether an operator supports a pre-filled deep link — driven by the
/// catalog's CLOSED `deepLinkKind` vocabulary (multi-pays MP2, threat T56:
/// never a URL from a payload), only Wave today.
bool deepLinkKindIsWave(String? deepLinkKind) => deepLinkKind == 'wave';
