import 'package:equatable/equatable.dart';

import 'kyc_document.dart';

enum BusinessType {
  salon,
  barber,
  spa,
  nailSalon,
  massage,
  other,
}

enum VerificationStatus {
  pending,
  verified,
  rejected,
}

class ProviderUser extends Equatable {
  final String id;
  final String phoneNumber;
  final String? name;
  final String businessName;
  final BusinessType businessType;
  final String? email;
  final String? address;
  final VerificationStatus verificationStatus;

  /// Reason supplied when [verificationStatus] is rejected.
  final String? rejectionReason;

  /// Submitted KYC documents (references only — no file bytes on device).
  final List<KycDocument> kycDocs;
  final DateTime createdAt;
  final String? providerId; // Consumer Provider id (e.g. provider1)

  const ProviderUser({
    required this.id,
    required this.phoneNumber,
    this.name,
    required this.businessName,
    required this.businessType,
    this.email,
    this.address,
    this.verificationStatus = VerificationStatus.pending,
    this.rejectionReason,
    this.kycDocs = const [],
    required this.createdAt,
    this.providerId,
  });

  @override
  List<Object?> get props => [
        id,
        phoneNumber,
        name,
        businessName,
        businessType,
        email,
        address,
        verificationStatus,
        rejectionReason,
        kycDocs,
        createdAt,
        providerId,
      ];

  ProviderUser copyWith({
    String? id,
    String? phoneNumber,
    String? name,
    String? businessName,
    BusinessType? businessType,
    String? email,
    String? address,
    VerificationStatus? verificationStatus,
    String? rejectionReason,
    List<KycDocument>? kycDocs,
    DateTime? createdAt,
    String? providerId,
  }) {
    return ProviderUser(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      name: name ?? this.name,
      businessName: businessName ?? this.businessName,
      businessType: businessType ?? this.businessType,
      email: email ?? this.email,
      address: address ?? this.address,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      kycDocs: kycDocs ?? this.kycDocs,
      createdAt: createdAt ?? this.createdAt,
      providerId: providerId ?? this.providerId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'name': name,
      'businessName': businessName,
      'businessType': businessType.name,
      'email': email,
      'address': address,
      'verificationStatus': verificationStatus.name,
      'rejectionReason': rejectionReason,
      'kycDocs': kycDocs.map((d) => d.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'providerId': providerId,
    };
  }

  factory ProviderUser.fromJson(Map<String, dynamic> json) {
    return ProviderUser(
      id: json['id'] as String,
      phoneNumber: json['phoneNumber'] as String,
      name: json['name'] as String?,
      businessName: json['businessName'] as String,
      businessType: BusinessType.values.firstWhere(
        (e) => e.name == json['businessType'],
        orElse: () => BusinessType.other,
      ),
      email: json['email'] as String?,
      address: json['address'] as String?,
      verificationStatus: VerificationStatus.values.firstWhere(
        (e) => e.name == json['verificationStatus'],
        orElse: () => VerificationStatus.pending,
      ),
      rejectionReason: json['rejectionReason'] as String?,
      kycDocs: json['kycDocs'] != null
          ? (json['kycDocs'] as List)
              .map((d) => KycDocument.fromJson(d as Map<String, dynamic>))
              .toList()
          : const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      providerId: json['providerId'] as String?,
    );
  }
}
