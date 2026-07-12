import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/onboarding.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/kyc_document.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_onboarding_provider.dart';
import 'package:myweli/services/interfaces/pro_kyc_service_interface.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';

class _MockProKycService extends Mock implements ProKycServiceInterface {}

class _MockProService extends Mock implements ProServiceInterface {}

void main() {
  late _MockProKycService kyc;
  late _MockProService pro;

  setUpAll(() {
    kyc = _MockProKycService();
    serviceLocator.proKycService = kyc;
    pro = _MockProService();
    serviceLocator.proService = pro;
  });

  setUp(() {
    reset(kyc);
    reset(pro);
  });

  ProviderUser newPro() => ProviderUser(
        id: 'pu1',
        phoneNumber: '+2250700000000',
        businessName: 'Salon X',
        businessType: BusinessType.salon,
        createdAt: DateTime(2026),
        // No public listing yet — provider-listing services aren't called.
        providerId: null,
      );

  OnboardingStepStatus statusOf(
          ProOnboardingProvider p, OnboardingStepKey key) =>
      p.steps.firstWhere((s) => s.key == key).status;

  test('a brand-new pro (no listing) still has the essentials to do', () async {
    when(() => kyc.getKycStatus(any())).thenAnswer(
      (_) async => ApiResponse.success(
          const KycStatus(status: VerificationStatus.pending)),
    );

    final p = ProOnboardingProvider();
    await p.load(newPro());

    expect(statusOf(p, OnboardingStepKey.services), OnboardingStepStatus.todo);
    expect(
        statusOf(p, OnboardingStepKey.verification), OnboardingStepStatus.todo);
    expect(p.readyToGoLive, isFalse);
  });

  test('a submitted KYC shows verification in progress', () async {
    when(() => kyc.getKycStatus(any())).thenAnswer(
      (_) async => ApiResponse.success(
        KycStatus(
          status: VerificationStatus.pending,
          documents: [
            KycDocument(
              type: KycDocumentType.idCard,
              fileName: 'a.jpg',
              submittedAt: DateTime(2026),
            ),
          ],
        ),
      ),
    );

    final p = ProOnboardingProvider();
    await p.load(newPro());

    expect(statusOf(p, OnboardingStepKey.verification),
        OnboardingStepStatus.inProgress);
  });

  group('publish (pro-salon-lifecycle B3)', () {
    test('success → true, no error, loading toggles', () async {
      when(() => pro.publishSalon('p1')).thenAnswer(
        (_) async => ApiResponse.success(true, message: 'ok'),
      );
      final p = ProOnboardingProvider();
      final ok = await p.publish('p1');
      expect(ok, isTrue);
      expect(p.error, isNull);
      expect(p.isPublishing, isFalse);
      verify(() => pro.publishSalon('p1')).called(1);
    });

    test('incomplete → false + the server message surfaces', () async {
      when(() => pro.publishSalon('p1')).thenAnswer(
        (_) async => ApiResponse.error(
          'Complétez les étapes requises avant la mise en ligne.',
          code: 'incomplete',
        ),
      );
      final p = ProOnboardingProvider();
      expect(await p.publish('p1'), isFalse);
      expect(p.error, contains('Complétez les étapes'));
    });

    test(
        'offer_required (pricing pivot) exposes the machine code so the '
        'screen can CTA to the offer picker', () async {
      when(() => pro.publishSalon('p1')).thenAnswer(
        (_) async => ApiResponse.error(
          'Choisissez votre offre avant la mise en ligne.',
          code: 'offer_required',
        ),
      );
      final p = ProOnboardingProvider();
      expect(await p.publish('p1'), isFalse);
      expect(p.publishErrorCode, 'offer_required');
    });
  });
}
