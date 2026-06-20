/// Mobile Money operators available in Côte d'Ivoire.
enum MobileMoneyOperator { wave, orangeMoney, mtnMoMo, moov }

extension MobileMoneyOperatorX on MobileMoneyOperator {
  String get displayName {
    switch (this) {
      case MobileMoneyOperator.wave:
        return 'Wave';
      case MobileMoneyOperator.orangeMoney:
        return 'Orange Money';
      case MobileMoneyOperator.mtnMoMo:
        return 'MTN MoMo';
      case MobileMoneyOperator.moov:
        return 'Moov Money';
    }
  }
}

/// Outcome of a Mobile Money payment attempt.
class PaymentResult {
  final bool success;
  final String? reference;
  final String? error;

  const PaymentResult({
    required this.success,
    this.reference,
    this.error,
  });
}
