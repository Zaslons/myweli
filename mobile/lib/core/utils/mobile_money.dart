import '../../models/payment.dart';

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

/// Whether the chosen operator supports a pre-filled deep link in V1 (only Wave
/// today; the others are copy-number + open-app-manually).
bool operatorHasDeepLink(MobileMoneyOperator? operator) =>
    operator == MobileMoneyOperator.wave;
