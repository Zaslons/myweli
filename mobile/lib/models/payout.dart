import 'package:equatable/equatable.dart';

import 'payment.dart';

enum PayoutStatus { pending, paid, failed }

/// A settlement of collected deposits to the provider's Mobile Money account.
/// The client never moves money — this records intent; the server settles.
class Payout extends Equatable {
  final String id;
  final double amount;
  final PayoutStatus status;
  final DateTime requestedAt;
  final MobileMoneyOperator operator;
  final String? reference;

  const Payout({
    required this.id,
    required this.amount,
    required this.status,
    required this.requestedAt,
    required this.operator,
    this.reference,
  });

  @override
  List<Object?> get props =>
      [id, amount, status, requestedAt, operator, reference];

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'status': status.name,
        'requestedAt': requestedAt.toIso8601String(),
        'operator': operator.name,
        'reference': reference,
      };

  factory Payout.fromJson(Map<String, dynamic> json) => Payout(
        id: json['id'] as String,
        amount: (json['amount'] as num).toDouble(),
        status: PayoutStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => PayoutStatus.pending,
        ),
        requestedAt: DateTime.parse(json['requestedAt'] as String),
        operator: MobileMoneyOperator.values.firstWhere(
          (e) => e.name == json['operator'],
          orElse: () => MobileMoneyOperator.wave,
        ),
        reference: json['reference'] as String?,
      );
}

/// The provider's payout balance + history (statement).
class PayoutAccount extends Equatable {
  final double availableBalance;
  final double pendingBalance;
  final List<Payout> payouts;

  const PayoutAccount({
    required this.availableBalance,
    required this.pendingBalance,
    this.payouts = const [],
  });

  @override
  List<Object?> get props => [availableBalance, pendingBalance, payouts];
}
