import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/kyc_document.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_kyc_provider.dart';
import 'package:myweli/services/interfaces/pro_kyc_service_interface.dart';

class _MockProKycService extends Mock implements ProKycServiceInterface {}

void main() {
  late _MockProKycService service;

  setUpAll(() {
    service = _MockProKycService();
    serviceLocator.proKycService = service;
    registerFallbackValue(<KycDocument>[]);
  });

  setUp(() {
    reset(service);
    when(() => service.getKycStatus(any())).thenAnswer(
      (_) async => ApiResponse.success(
          const KycStatus(status: VerificationStatus.pending)),
    );
    when(
      () => service.uploadDocument(
        source: any(named: 'source'),
        contentType: any(named: 'contentType'),
      ),
    ).thenAnswer((_) async => ApiResponse.success('kyc/acc1/x.jpg'));
  });

  test('load populates status, reason and documents', () async {
    when(() => service.getKycStatus(any())).thenAnswer(
      (_) async => ApiResponse.success(
        KycStatus(
          status: VerificationStatus.rejected,
          rejectionReason: 'flou',
          documents: [
            KycDocument(
              type: KycDocumentType.idCard,
              fileName: 'cni.jpg',
              submittedAt: DateTime(2026),
            ),
          ],
        ),
      ),
    );

    final p = ProKycProvider();
    await p.load('p1');

    expect(p.status, VerificationStatus.rejected);
    expect(p.rejectionReason, 'flou');
    expect(p.documentFor(KycDocumentType.idCard), isNotNull);
  });

  test('required documents gate canSubmit by business type', () async {
    final p = ProKycProvider();
    await p.load('p1');

    expect(p.canSubmit(BusinessType.salon), isFalse);
    await p.addDocument(KycDocumentType.idCard, 'a.jpg', 'image/jpeg');
    await p.addDocument(KycDocumentType.selfie, 'b.jpg', 'image/jpeg');

    // Freelancer (other) is good with ID + selfie; a salon still needs RCCM.
    expect(p.canSubmit(BusinessType.other), isTrue);
    expect(p.canSubmit(BusinessType.salon), isFalse);

    await p.addDocument(
      KycDocumentType.businessRegistration,
      'c.jpg',
      'image/jpeg',
    );
    expect(p.canSubmit(BusinessType.salon), isTrue);

    p.removeDocument(KycDocumentType.idCard);
    expect(p.canSubmit(BusinessType.salon), isFalse);
  });

  test('submit returns true on success', () async {
    when(
      () => service.submitKyc(
        providerUserId: any(named: 'providerUserId'),
        documents: any(named: 'documents'),
      ),
    ).thenAnswer(
      (_) async => ApiResponse.success(
          const KycStatus(status: VerificationStatus.pending)),
    );

    final p = ProKycProvider();
    await p.load('p1');
    await p.addDocument(KycDocumentType.idCard, 'a.jpg', 'image/jpeg');
    await p.addDocument(KycDocumentType.selfie, 'b.jpg', 'image/jpeg');

    expect(await p.submit('p1'), isTrue);
  });

  test('submit returns false and surfaces the error on failure', () async {
    when(
      () => service.submitKyc(
        providerUserId: any(named: 'providerUserId'),
        documents: any(named: 'documents'),
      ),
    ).thenAnswer((_) async => ApiResponse.error('boom'));

    final p = ProKycProvider();
    await p.load('p1');

    final ok = await p.submit('p1');
    expect(ok, isFalse);
    expect(p.error, 'boom');
  });
}
