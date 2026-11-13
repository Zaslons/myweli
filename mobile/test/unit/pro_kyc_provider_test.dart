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
        const KycStatus(status: VerificationStatus.pending),
      ),
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
        const KycStatus(status: VerificationStatus.pending),
      ),
    );

    final p = ProKycProvider();
    await p.load('p1');
    await p.addDocument(KycDocumentType.idCard, 'a.jpg', 'image/jpeg');
    await p.addDocument(KycDocumentType.selfie, 'b.jpg', 'image/jpeg');

    expect(await p.submit('p1'), isTrue);
  });

  // docs/design/upload-resave-stale-pending.md — the documents the server
  // STORED become the provider's, never the ones it sent. A new document goes
  // up under `pending/…`; the submit moves it and deletes that object, so a
  // second submit in the same screen visit (replace one document, submit
  // again) re-sent a dead key and was refused with `upload_not_found`.
  group('after a submit, the documents are the server\'s', () {
    KycDocument doc(KycDocumentType type, String key) => KycDocument(
      type: type,
      fileName: '$key.jpg',
      key: key,
      submittedAt: DateTime(2026, 11, 13),
    );

    test(
      'a second submit sends the STORED keys, not the pending ones',
      () async {
        var uploads = 0;
        when(
          () => service.uploadDocument(
            source: any(named: 'source'),
            contentType: any(named: 'contentType'),
          ),
        ).thenAnswer(
          (_) async => ApiResponse.success('pending/kyc/acc1/d${++uploads}'),
        );
        final sent = <List<String>>[];
        when(
          () => service.submitKyc(
            providerUserId: any(named: 'providerUserId'),
            documents: any(named: 'documents'),
          ),
        ).thenAnswer((inv) async {
          final docs = inv.namedArguments[#documents] as List<KycDocument>;
          sent.add([for (final d in docs) d.key]);
          // As the API answers: every pending key promoted.
          return ApiResponse.success(
            KycStatus(
              status: VerificationStatus.pending,
              documents: [
                for (final d in docs)
                  doc(d.type, d.key.replaceFirst('pending/', '')),
              ],
            ),
          );
        });

        final p = ProKycProvider();
        await p.load('p1');
        await p.addDocument(KycDocumentType.idCard, 'a.jpg', 'image/jpeg');
        await p.addDocument(KycDocumentType.selfie, 'b.jpg', 'image/jpeg');
        expect(await p.submit('p1'), isTrue);
        expect(p.documentFor(KycDocumentType.idCard)?.key, 'kyc/acc1/d1');

        // Replace the selfie — what the rejection banner invites — and submit.
        await p.addDocument(KycDocumentType.selfie, 'c.jpg', 'image/jpeg');
        expect(await p.submit('p1'), isTrue);
        expect(sent.last, containsAll(['kyc/acc1/d1', 'pending/kyc/acc1/d3']));
        expect(sent.last, isNot(contains('pending/kyc/acc1/d1')));
      },
    );

    test('an answer without documents reads the status back', () async {
      when(
        () => service.submitKyc(
          providerUserId: any(named: 'providerUserId'),
          documents: any(named: 'documents'),
        ),
      ).thenAnswer(
        (_) async => ApiResponse.success(
          const KycStatus(status: VerificationStatus.pending),
        ),
      );
      final p = ProKycProvider();
      await p.load('p1');
      await p.addDocument(KycDocumentType.idCard, 'a.jpg', 'image/jpeg');
      await p.addDocument(KycDocumentType.selfie, 'b.jpg', 'image/jpeg');

      when(() => service.getKycStatus(any())).thenAnswer(
        (_) async => ApiResponse.success(
          KycStatus(
            status: VerificationStatus.pending,
            documents: [
              doc(KycDocumentType.idCard, 'kyc/acc1/id'),
              doc(KycDocumentType.selfie, 'kyc/acc1/selfie'),
            ],
          ),
        ),
      );
      expect(await p.submit('p1'), isTrue);
      verify(() => service.getKycStatus('p1')).called(2);
      expect(p.documentFor(KycDocumentType.idCard)?.key, 'kyc/acc1/id');
    });
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
