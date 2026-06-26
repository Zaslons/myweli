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

  /// The wire name (matches the backend enum), e.g. `orangeMoney`.
  String get apiName => name;

  /// Parse a wire name (e.g. `wave`) back to an operator, or null.
  static MobileMoneyOperator? fromApi(String? name) {
    if (name == null) return null;
    for (final op in MobileMoneyOperator.values) {
      if (op.name == name) return op;
    }
    return null;
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

  factory DepositPolicy.fromJson(Map<String, dynamic> json) => DepositPolicy(
        depositRequired: json['depositRequired'] as bool? ?? false,
        depositPercentage: (json['depositPercentage'] as num?)?.toDouble() ?? 0,
        cancellationWindowHours:
            (json['cancellationWindowHours'] as num?)?.toInt() ?? 24,
        mobileMoneyOperator: MobileMoneyOperatorX.fromApi(
          json['mobileMoneyOperator'] as String?,
        ),
        mobileMoneyNumber: json['mobileMoneyNumber'] as String?,
      );
}
