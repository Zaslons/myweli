import 'package:equatable/equatable.dart';

import 'provider.dart';

/// What « Profil » shows of the acting salon — its name, category, address and
/// phone — kept in the persisted provider session next to the membership and
/// the market, so an offline cold start still shows them
/// (docs/design/product-questions-batch8.md §2.3, B8.3, decision 29).
///
/// Public facts of the salon's own listing, and nothing more: never the
/// account's copy made at sign-up (r6-salon-fact-reads.md). Like
/// [SalonMarket], they answer only for [salonId] — never for another salon the
/// session has since moved to.
class SalonFacts extends Equatable {
  const SalonFacts({
    required this.salonId,
    required this.name,
    this.category = '',
    this.address = '',
    this.phoneNumber = '',
  });

  factory SalonFacts.of(Provider salon) => SalonFacts(
    salonId: salon.id,
    name: salon.name,
    category: salon.category,
    address: salon.address,
    phoneNumber: salon.phoneNumber,
  );

  final String salonId;
  final String name;

  /// The machine value (`salon`, `barber`…) — `salonCategoryLabel` words it.
  final String category;
  final String address;
  final String phoneNumber;

  factory SalonFacts.fromJson(Map<String, dynamic> json) => SalonFacts(
    salonId: json['salonId'] as String,
    name: json['name'] as String? ?? '',
    category: json['category'] as String? ?? '',
    address: json['address'] as String? ?? '',
    phoneNumber: json['phoneNumber'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'salonId': salonId,
    'name': name,
    'category': category,
    'address': address,
    'phoneNumber': phoneNumber,
  };

  @override
  List<Object?> get props => [salonId, name, category, address, phoneNumber];
}
