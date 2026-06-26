import 'package:equatable/equatable.dart';

import 'provider_user.dart';

enum KycDocumentType { idCard, selfie, businessRegistration, addressProof }

/// A submitted KYC document. [fileName] is only a reference to the uploaded
/// file — the real bytes live in access-controlled, encrypted server storage,
/// never on the device or in logs (PRD NFR-SEC-002).
class KycDocument extends Equatable {
  final KycDocumentType type;
  final String fileName;

  /// Private storage object key (from `/uploads/sign?purpose=kyc`). Empty for
  /// legacy/mock docs.
  final String key;
  final DateTime submittedAt;

  const KycDocument({
    required this.type,
    required this.fileName,
    this.key = '',
    required this.submittedAt,
  });

  @override
  List<Object?> get props => [type, fileName, key, submittedAt];

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'fileName': fileName,
        'key': key,
        'submittedAt': submittedAt.toIso8601String(),
      };

  factory KycDocument.fromJson(Map<String, dynamic> json) => KycDocument(
        type: KycDocumentType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => KycDocumentType.idCard,
        ),
        fileName: json['fileName'] as String? ?? '',
        key: json['key'] as String? ?? '',
        submittedAt: json['submittedAt'] != null
            ? DateTime.parse(json['submittedAt'] as String)
            : DateTime.now(),
      );
}

/// The provider's KYC state as returned by the service.
class KycStatus extends Equatable {
  final VerificationStatus status;
  final List<KycDocument> documents;
  final String? rejectionReason;

  const KycStatus({
    required this.status,
    this.documents = const [],
    this.rejectionReason,
  });

  @override
  List<Object?> get props => [status, documents, rejectionReason];

  factory KycStatus.fromJson(Map<String, dynamic> json) => KycStatus(
        status: VerificationStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => VerificationStatus.pending,
        ),
        documents: ((json['documents'] as List?) ?? const [])
            .map((e) => KycDocument.fromJson(e as Map<String, dynamic>))
            .toList(),
        rejectionReason: json['rejectionReason'] as String?,
      );
}

/// Whether a document type is required for a given business type. ID + selfie
/// are always required; the business registration (RCCM) is required for
/// establishments but optional for `other` (freelancers à domicile); the
/// address proof is always optional.
bool isKycDocumentRequired(KycDocumentType type, BusinessType businessType) {
  switch (type) {
    case KycDocumentType.idCard:
    case KycDocumentType.selfie:
      return true;
    case KycDocumentType.businessRegistration:
      return businessType != BusinessType.other;
    case KycDocumentType.addressProof:
      return false;
  }
}

/// The document types a provider must supply, given their business type.
List<KycDocumentType> requiredKycDocuments(BusinessType businessType) =>
    KycDocumentType.values
        .where((t) => isKycDocumentRequired(t, businessType))
        .toList();
