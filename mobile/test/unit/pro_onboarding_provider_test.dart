import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/onboarding.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/kyc_document.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_onboarding_provider.dart';
import 'package:myweli/services/interfaces/pro_kyc_service_interface.dart';

class _MockProKycService extends Mock implements ProKycServiceInterface {}

void main() {
  late _MockProKycService kyc;

  setUpAll(() {
    kyc = _MockProKycService();
    serviceLocator.proKycService = kyc;
  });

  setUp(() => reset(kyc));

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
}
