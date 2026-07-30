// Multi-pays MP2 (docs/design/multi-pays-end-version.md §5): Mobile-Money
// operators are DATA — ids/labels/deep-link kinds come from the salon
// country's catalog (`GET /localities` → `MomoOperatorInfo`), never a client
// enum. The wire values (`wave`, `orangeMoney`, `mtnMoMo`, `moov`, …) are
// plain strings validated server-side against the catalog.

/// A provider's deposit policy: whether an acompte is required and, if so, the
/// fraction of the total charged up front.
class DepositPolicy {
  final bool depositRequired;
  final double depositPercentage;
  final int cancellationWindowHours;

  /// Mobile Money handle the deposit is sent to (client→salon directly) —
  /// an operator id from the salon country's catalog.
  final String? mobileMoneyOperator;
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
        mobileMoneyOperator: json['mobileMoneyOperator'] as String?,
        mobileMoneyNumber: json['mobileMoneyNumber'] as String?,
      );
}
