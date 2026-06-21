import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/kyc_document.dart';
import 'package:myweli/models/provider_user.dart';

void main() {
  test('KycDocument round-trips through JSON', () {
    final doc = KycDocument(
      type: KycDocumentType.idCard,
      fileName: 'cni.jpg',
      submittedAt: DateTime(2026, 6, 22),
    );
    final back = KycDocument.fromJson(doc.toJson());
    expect(back.type, KycDocumentType.idCard);
    expect(back.fileName, 'cni.jpg');
    expect(back.submittedAt, DateTime(2026, 6, 22));
  });

  test('a salon must also provide the business registration', () {
    final req = requiredKycDocuments(BusinessType.salon);
    expect(
      req,
      containsAll([
        KycDocumentType.idCard,
        KycDocumentType.selfie,
        KycDocumentType.businessRegistration,
      ]),
    );
    expect(req, isNot(contains(KycDocumentType.addressProof)));
  });

  test('a freelancer (other) does not need the business registration', () {
    expect(
      requiredKycDocuments(BusinessType.other),
      [KycDocumentType.idCard, KycDocumentType.selfie],
    );
    expect(
      isKycDocumentRequired(
          KycDocumentType.businessRegistration, BusinessType.other),
      isFalse,
    );
  });

  test('ProviderUser round-trips its kycDocs and rejectionReason', () {
    final user = ProviderUser(
      id: 'p1',
      phoneNumber: '+2250700000000',
      businessName: 'Salon X',
      businessType: BusinessType.salon,
      verificationStatus: VerificationStatus.rejected,
      rejectionReason: 'Document illisible',
      kycDocs: [
        KycDocument(
          type: KycDocumentType.idCard,
          fileName: 'cni.jpg',
          submittedAt: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
    );
    final back = ProviderUser.fromJson(user.toJson());
    expect(back.verificationStatus, VerificationStatus.rejected);
    expect(back.rejectionReason, 'Document illisible');
    expect(back.kycDocs.single.type, KycDocumentType.idCard);
  });
}
