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

/// A provider's deposit policy: whether an acompte is required and, if so, the
/// fraction of the total charged up front.
class DepositPolicy {
  final bool depositRequired;
  final double depositPercentage;
  final int cancellationWindowHours;

  /// Mobile Money handle the deposit is sent to (client→salon directly).
  final MobileMoneyOperator? mobileMoneyOperator;
  final String? mobileMoneyNumber;

  const DepositPolicy({
    required this.depositRequired,
    required this.depositPercentage,
    this.cancellationWindowHours = 24,
    this.mobileMoneyOperator,
    this.mobileMoneyNumber,
  });
}
