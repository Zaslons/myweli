import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/onboarding.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/kyc_document.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/models/pro_membership.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_onboarding_provider.dart';
import 'package:myweli/services/interfaces/pro_artist_service_interface.dart';
import 'package:myweli/services/interfaces/pro_kyc_service_interface.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';

class _MockProKycService extends Mock implements ProKycServiceInterface {}

class _MockProService extends Mock implements ProServiceInterface {}

class _MockProArtistService extends Mock implements ProArtistServiceInterface {}

void main() {
  late _MockProKycService kyc;
  late _MockProService pro;
  late _MockProArtistService artists;

  // `serviceLocator.subscriptionService` is deliberately NEVER assigned in
  // this file: it is `late final`, so a read throws — and `load` would turn
  // that into `loadFailed`. The offer-free test below relies on it.
  setUpAll(() {
    kyc = _MockProKycService();
    serviceLocator.proKycService = kyc;
    pro = _MockProService();
    serviceLocator.proService = pro;
    artists = _MockProArtistService();
    serviceLocator.proArtistService = artists;
  });

  setUp(() {
    reset(kyc);
    reset(pro);
    reset(artists);
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
    ProOnboardingProvider p,
    OnboardingStepKey key,
  ) => p.steps.firstWhere((s) => s.key == key).status;

  test('a brand-new pro (no listing) still has the essentials to do', () async {
    when(() => kyc.getKycStatus(any())).thenAnswer(
      (_) async => ApiResponse.success(
        const KycStatus(status: VerificationStatus.pending),
      ),
    );

    final p = ProOnboardingProvider();
    await p.load(newPro());

    expect(statusOf(p, OnboardingStepKey.services), OnboardingStepStatus.todo);
    expect(
      statusOf(p, OnboardingStepKey.verification),
      OnboardingStepStatus.todo,
    );
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

    expect(
      statusOf(p, OnboardingStepKey.verification),
      OnboardingStepStatus.inProgress,
    );
  });

  test('every publish gate met → ready to go live WITHOUT an offer — the '
      'checklist never reads one (pro-companion-path §2.2)', () async {
    // The server starts the trial at the first publish, so the client gate
    // has no offer key and no offer read. A salon with no offer row used to
    // stay stuck behind « Choisissez votre offre ».
    final salon = MockData.providers.first.copyWith(
      imageUrls: const ['a.jpg', 'b.jpg', 'c.jpg'],
    );
    when(() => pro.getProviderServices('p1')).thenAnswer(
      (_) async =>
          ApiResponse.success(MockData.getServicesForProvider('provider1')),
    );
    when(() => artists.getArtists('p1')).thenAnswer(
      (_) async =>
          ApiResponse.success(MockData.getArtistsForProvider('provider1')),
    );
    when(
      () => pro.getProviderAvailability('p1'),
    ).thenAnswer((_) async => ApiResponse.success(salon.availability));
    when(() => pro.getDepositPolicy('p1')).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(depositRequired: false, depositPercentage: 0),
      ),
    );
    when(() => pro.getMyProvider()).thenAnswer(
      (_) async => ApiResponse.success(
        MyProviderInfo(
          salon: salon,
          membership: ProMembership(
            role: TeamRole.owner,
            capabilities: presetCapabilitiesFor(TeamRole.owner),
            salonId: 'p1',
            salonName: salon.name,
          ),
        ),
      ),
    );
    when(() => kyc.getKycStatus(any())).thenAnswer(
      (_) async => ApiResponse.success(
        const KycStatus(status: VerificationStatus.verified),
      ),
    );

    final p = ProOnboardingProvider();
    await p.load(
      ProviderUser(
        id: 'pu1',
        phoneNumber: '+2250700000000',
        businessName: 'Salon X',
        businessType: BusinessType.salon,
        createdAt: DateTime(2026),
        providerId: 'p1',
      ),
    );

    expect(
      p.loadFailed,
      isFalse,
      reason:
          'the checklist read something it should not (the offer?): '
          '${p.error}',
    );
    expect(p.steps.map((s) => s.key.name), isNot(contains('offer')));
    expect(p.readyToGoLive, isTrue);
  });

  group('publish (pro-salon-lifecycle B3)', () {
    test('success → true, no error, loading toggles', () async {
      when(
        () => pro.publishSalon('p1'),
      ).thenAnswer((_) async => ApiResponse.success(true, message: 'ok'));
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

    test('offer_required (an EXPIRED offer) exposes the machine code so the '
        'screen can show its neutral sentence', () async {
      when(() => pro.publishSalon('p1')).thenAnswer(
        (_) async => ApiResponse.error(
          'La mise en ligne est indisponible : l’offre de votre salon n’est '
          'plus active.',
          code: 'offer_required',
        ),
      );
      final p = ProOnboardingProvider();
      expect(await p.publish('p1'), isFalse);
      expect(p.publishErrorCode, 'offer_required');
    });
  });
}
