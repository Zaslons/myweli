import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/access/salon_state_refresh.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/onboarding.dart';
import 'package:myweli/core/utils/salon_go_live.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/models/kyc_document.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/models/pro_membership.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/salon_validation.dart';
import 'package:myweli/models/service.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_onboarding_provider.dart';
import 'package:myweli/services/interfaces/pro_artist_service_interface.dart';
import 'package:myweli/services/interfaces/pro_kyc_service_interface.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';

class _MockProKycService extends Mock implements ProKycServiceInterface {}

class _MockProService extends Mock implements ProServiceInterface {}

class _MockProArtistService extends Mock implements ProArtistServiceInterface {}

/// The session's two copies of the salon's state, counted.
class _Session implements SalonStateRefresh {
  int memberships = 0;
  int salons = 0;

  @override
  Future<void> rereadMembership() async => memberships++;

  @override
  Future<void> rereadMySalons() async => salons++;
}

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
    await p.load(newPro(), salonId: null);

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
    await p.load(newPro(), salonId: null);

    expect(
      statusOf(p, OnboardingStepKey.verification),
      OnboardingStepStatus.inProgress,
    );
  });

  test('every publish gate met → ready to go live WITHOUT an offer — the '
      'checklist never reads one (pro-companion-path §2.2)', () async {
    // The server starts the trial when MyWeli validates the salon (B0.18
    // §3.6 — it was the first publish before), so the client gate has no
    // offer key and no offer read. A salon with no offer row used to stay
    // stuck behind « Choisissez votre offre ».
    final salon = MockData.providers.first.copyWith(
      imageUrls: const ['a.jpg', 'b.jpg', 'c.jpg'],
    );
    when(() => pro.getProviderServices(SalonId('p1'))).thenAnswer(
      (_) async => ApiResponse.success(
        MockData.getServicesForProvider(SalonId('provider1')),
      ),
    );
    when(() => artists.getArtists(SalonId('p1'))).thenAnswer(
      (_) async => ApiResponse.success(
        MockData.getArtistsForProvider(SalonId('provider1')),
      ),
    );
    when(
      () => pro.getProviderAvailability(SalonId('p1')),
    ).thenAnswer((_) async => ApiResponse.success(salon.availability));
    when(() => pro.getDepositPolicy(SalonId('p1'))).thenAnswer(
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
            salonId: SalonId('p1'),
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
        providerId: SalonId('p1'),
      ),
      salonId: SalonId('p1'),
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

  // docs/design/hygiene-batch9.md §14 (B9.8) — every service answers a
  // failure instead of throwing, and each read here took one for « nothing
  // done »: offline, a salon saw its whole checklist to do, and the error
  // state above it could not be reached.
  test('a read that failed is the load\'s failure, not a step to do', () async {
    final salon = MockData.providers.first;
    when(() => pro.getProviderServices(SalonId('p1'))).thenAnswer(
      (_) async => ApiResponse<List<Service>>.error(kNoConnectionMessage),
    );
    when(() => artists.getArtists(SalonId('p1'))).thenAnswer(
      (_) async => ApiResponse.success(
        MockData.getArtistsForProvider(SalonId('provider1')),
      ),
    );
    when(
      () => pro.getProviderAvailability(SalonId('p1')),
    ).thenAnswer((_) async => ApiResponse.success(salon.availability));
    when(() => pro.getDepositPolicy(SalonId('p1'))).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(depositRequired: false, depositPercentage: 0),
      ),
    );
    when(() => pro.getMyProvider()).thenAnswer(
      (_) async => ApiResponse<MyProviderInfo>.error(kGenericErrorMessage),
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
        providerId: SalonId('p1'),
      ),
      salonId: SalonId('p1'),
    );

    expect(p.loadFailed, isTrue);
    expect(p.loaded, isFalse);
    // The first failure, in its own words.
    expect(p.error, kNoConnectionMessage);
  });

  // docs/design/web-pro-golive-signup-like-app.md §4 — the app judged two
  // steps differently from the server's publish gate it mirrors: it counted
  // INACTIVE services, and wanted an `isAvailable` slot where the server takes
  // any day with hours. The checklist could say ✓ to a salon the server then
  // refused, or ✗ to one it would publish.
  group('aligned with the server’s gate', () {
    final salon = MockData.providers.first.copyWith(
      imageUrls: const ['a.jpg', 'b.jpg', 'c.jpg'],
    );

    Future<ProOnboardingProvider> load({
      required List<Service> services,
      required Availability availability,
    }) async {
      when(
        () => pro.getProviderServices(SalonId('p1')),
      ).thenAnswer((_) async => ApiResponse.success(services));
      when(() => artists.getArtists(SalonId('p1'))).thenAnswer(
        (_) async => ApiResponse.success(
          MockData.getArtistsForProvider(SalonId('provider1')),
        ),
      );
      when(
        () => pro.getProviderAvailability(SalonId('p1')),
      ).thenAnswer((_) async => ApiResponse.success(availability));
      when(() => pro.getDepositPolicy(SalonId('p1'))).thenAnswer(
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
              salonId: SalonId('p1'),
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
          providerId: SalonId('p1'),
        ),
        salonId: SalonId('p1'),
      );
      return p;
    }

    test('an inactive service does not count toward the three', () async {
      final three = MockData.getServicesForProvider(
        SalonId('provider1'),
      ).take(3).toList();
      final p = await load(
        services: [three[0], three[1], three[2].copyWith(active: false)],
        availability: salon.availability,
      );
      expect(
        statusOf(p, OnboardingStepKey.services),
        OnboardingStepStatus.todo,
      );
      expect(p.readyToGoLive, isFalse);
    });

    test(
      'a day with hours counts, whatever its slots’ flags — as the server',
      () async {
        final p = await load(
          services: MockData.getServicesForProvider(SalonId('provider1')),
          availability: salon.availability.copyWith(
            weeklySchedule: {
              0: [
                TimeSlot(
                  startTime: DateTime(2026, 1, 5, 9),
                  endTime: DateTime(2026, 1, 5, 18),
                  isAvailable: false,
                ),
              ],
            },
          ),
        );
        expect(
          statusOf(p, OnboardingStepKey.availability),
          OnboardingStepStatus.done,
        );
      },
    );
  });

  group('publish (pro-salon-lifecycle B3)', () {
    test('success → the outcome, no error, loading toggles', () async {
      when(() => pro.publishSalon(SalonId('p1'))).thenAnswer(
        (_) async => ApiResponse.success(const PublishOutcome.live()),
      );
      final p = ProOnboardingProvider();
      final outcome = await p.publish(SalonId('p1'), session: _Session());
      expect(outcome, const PublishOutcome.live());
      expect(p.error, isNull);
      expect(p.isPublishing, isFalse);
      verify(() => pro.publishSalon(SalonId('p1'))).called(1);
    });

    test('incomplete → null + the server message surfaces', () async {
      when(() => pro.publishSalon(SalonId('p1'))).thenAnswer(
        (_) async => ApiResponse.error(
          'Complétez les étapes requises avant la mise en ligne.',
          code: 'incomplete',
        ),
      );
      final p = ProOnboardingProvider();
      expect(await p.publish(SalonId('p1'), session: _Session()), isNull);
      expect(p.error, contains('Complétez les étapes'));
    });

    test('offer_required (an EXPIRED offer) exposes the machine code so the '
        'screen can show its neutral sentence', () async {
      when(() => pro.publishSalon(SalonId('p1'))).thenAnswer(
        (_) async => ApiResponse.error(
          'La mise en ligne est indisponible : l’offre de votre salon n’est '
          'plus active.',
          code: 'offer_required',
        ),
      );
      final p = ProOnboardingProvider();
      expect(await p.publish(SalonId('p1'), session: _Session()), isNull);
      expect(p.publishErrorCode, 'offer_required');
    });
  });

  // B0.18 — docs/design/salon-go-live-approval.md §6.1, §6.2, §8.3 « The
  // provider: keeps `validation`, resets it on a switch; the refresh after
  // submit »; decision 136 items 2, 7 and 10.
  group('the salon\'s go-live state (B0.18)', () {
    final pending = SalonValidation(
      state: SalonValidationState.pending,
      wentLive: false,
      submittedAt: DateTime.utc(2026, 11, 13, 9),
    );
    const refusedFinal = SalonValidation(
      state: SalonValidationState.refused,
      wentLive: false,
      refusal: SalonRefusal(code: 'outside_ci', isFinal: true),
    );

    /// /me/provider for p1 in [status], carrying [validation] when [sent].
    MyProviderInfo me({
      String? status = 'draft',
      SalonValidation? validation,
      bool sent = true,
      String id = 'p1',
    }) {
      final salon = MockData.providers.first.copyWith(
        id: SalonId(id),
        status: status,
        imageUrls: const ['a.jpg', 'b.jpg', 'c.jpg'],
      );
      return MyProviderInfo(
        salon: salon,
        membership: ProMembership(
          role: TeamRole.owner,
          capabilities: presetCapabilitiesFor(TeamRole.owner),
          salonId: SalonId(id),
          salonName: salon.name,
        ),
        validation: validation,
        validationSent: sent,
      );
    }

    /// The load's six reads, its /me/provider answering [info].
    Future<ProOnboardingProvider> loaded(MyProviderInfo info) async {
      when(() => pro.getProviderServices(SalonId('p1'))).thenAnswer(
        (_) async => ApiResponse.success(
          MockData.getServicesForProvider(SalonId('provider1')),
        ),
      );
      when(() => artists.getArtists(SalonId('p1'))).thenAnswer(
        (_) async => ApiResponse.success(
          MockData.getArtistsForProvider(SalonId('provider1')),
        ),
      );
      when(() => pro.getProviderAvailability(SalonId('p1'))).thenAnswer(
        (_) async => ApiResponse.success(MockData.providers.first.availability),
      );
      when(() => pro.getDepositPolicy(SalonId('p1'))).thenAnswer(
        (_) async => ApiResponse.success(
          const DepositPolicy(depositRequired: false, depositPercentage: 0),
        ),
      );
      when(
        () => pro.getMyProvider(),
      ).thenAnswer((_) async => ApiResponse.success(info));
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
          providerId: SalonId('p1'),
        ),
        salonId: SalonId('p1'),
      );
      expect(p.loadFailed, isFalse, reason: '${p.error}');
      return p;
    }

    void answerPublish(ApiResponse<PublishOutcome> answer) => when(
      () => pro.publishSalon(SalonId('p1')),
    ).thenAnswer((_) async => answer);

    group('the load keeps it, from its own /me/provider read', () {
      test('before any load: unknown (null), no validation', () {
        final p = ProOnboardingProvider();
        expect(p.salonGoLiveState, isNull);
        expect(p.validation, isNull);
      });

      test(
        'a pending request: the state AND the validation (its date)',
        () async {
          final p = await loaded(me(validation: pending));
          expect(p.salonGoLiveState, GoLiveState.pending);
          expect(p.validation, pending);
          verify(() => pro.getMyProvider()).called(1);
        },
      );

      test('a key sent null on a draft: never asked', () async {
        final p = await loaded(me());
        expect(p.salonGoLiveState, GoLiveState.neverAsked);
      });

      test('no key (a server from before B0.18): legacy — today\'s screen '
          '(decision 136 item 10)', () async {
        final p = await loaded(me(sent: false));
        expect(p.salonGoLiveState, GoLiveState.legacy);
      });

      test('a pro with no salon yet reads nothing: unknown', () async {
        when(() => kyc.getKycStatus(any())).thenAnswer(
          (_) async => ApiResponse.success(
            const KycStatus(status: VerificationStatus.pending),
          ),
        );
        final p = ProOnboardingProvider();
        await p.load(newPro(), salonId: null);
        expect(p.loaded, isTrue);
        expect(p.salonGoLiveState, isNull);
      });

      test('a failed load writes no state', () async {
        when(() => pro.getProviderServices(SalonId('p1'))).thenAnswer(
          (_) async => ApiResponse<List<Service>>.error(kNoConnectionMessage),
        );
        when(() => artists.getArtists(SalonId('p1'))).thenAnswer(
          (_) async => ApiResponse.success(
            MockData.getArtistsForProvider(SalonId('provider1')),
          ),
        );
        when(() => pro.getProviderAvailability(SalonId('p1'))).thenAnswer(
          (_) async =>
              ApiResponse.success(MockData.providers.first.availability),
        );
        when(() => pro.getDepositPolicy(SalonId('p1'))).thenAnswer(
          (_) async => ApiResponse.success(
            const DepositPolicy(depositRequired: false, depositPercentage: 0),
          ),
        );
        when(
          () => pro.getMyProvider(),
        ).thenAnswer((_) async => ApiResponse.success(me(validation: pending)));
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
            providerId: SalonId('p1'),
          ),
          salonId: SalonId('p1'),
        );
        expect(p.loadFailed, isTrue);
        expect(p.salonGoLiveState, isNull);
      });

      test('a salon switch drops it — the next salon never shows this '
          'one\'s state', () async {
        final p = await loaded(me(validation: pending));
        expect(p.salonGoLiveState, GoLiveState.pending);

        p.resetForSalonSwitch();

        expect(p.salonGoLiveState, isNull);
        expect(p.validation, isNull);
      });
    });

    group('publish takes the answer, then the session re-reads (§6.2)', () {
      test('200 → live at once; the card and « Mes salons » re-read; no '
          'read of its own', () async {
        final p = await loaded(me());
        answerPublish(ApiResponse.success(const PublishOutcome.live()));
        final session = _Session();

        final outcome = await p.publish(SalonId('p1'), session: session);
        await p.publishSettled;

        expect(outcome?.isLive, isTrue);
        expect(p.salonGoLiveState, GoLiveState.live);
        expect(session.memberships, 1, reason: 'the home card re-reads');
        expect(session.salons, 1, reason: '« Mes salons » re-reads');
        verify(() => pro.getMyProvider()).called(1); // the load's, only
      });

      test('202 pending → the request\'s validation at once (« Demande '
          'envoyée le … » has its date); the session re-reads', () async {
        final p = await loaded(me());
        expect(p.salonGoLiveState, GoLiveState.neverAsked);
        answerPublish(ApiResponse.success(PublishOutcome.requested(pending)));
        final session = _Session();
        var heard = 0;
        p.addListener(() => heard++);

        final outcome = await p.publish(SalonId('p1'), session: session);

        // Before the re-reads land: the screen already shows the request.
        expect(outcome?.saysRequestSent, isTrue);
        expect(p.salonGoLiveState, GoLiveState.pending);
        expect(p.validation, pending);
        expect(heard, greaterThan(0));
        await p.publishSettled;
        expect(session.memberships, 1);
        expect(session.salons, 1);
        verify(() => pro.getMyProvider()).called(1); // the load's, only
      });

      test(
        '202 the validation finishing (approved, not yet live) → pending',
        () async {
          final p = await loaded(me());
          answerPublish(
            ApiResponse.success(
              const PublishOutcome.requested(
                SalonValidation(
                  state: SalonValidationState.approved,
                  wentLive: false,
                ),
              ),
            ),
          );
          final outcome = await p.publish(SalonId('p1'), session: _Session());
          expect(outcome?.saysRequestSent, isTrue);
          expect(p.salonGoLiveState, GoLiveState.pending);
        },
      );

      test('202 refused at that very moment → shown, and NO « Demande '
          'envoyée » (decision 136 item 7)', () async {
        final p = await loaded(me());
        answerPublish(
          ApiResponse.success(const PublishOutcome.requested(refusedFinal)),
        );
        final session = _Session();
        final outcome = await p.publish(SalonId('p1'), session: session);
        await p.publishSettled;

        expect(outcome?.saysRequestSent, isFalse);
        expect(p.salonGoLiveState, GoLiveState.refusedFinal);
        expect(p.validation?.refusal?.code, 'outside_ci');
        expect(session.memberships, 1);
      });

      test('202 whose request vanished (null) → never asked, NO « Demande '
          'envoyée » (decision 136 item 7)', () async {
        final p = await loaded(me(validation: pending));
        answerPublish(
          ApiResponse.success(const PublishOutcome.requested(null)),
        );
        final outcome = await p.publish(SalonId('p1'), session: _Session());
        expect(outcome?.saysRequestSent, isFalse);
        expect(p.salonGoLiveState, GoLiveState.neverAsked);
        expect(p.validation, isNull);
      });

      test('202 with a body this build cannot read → « Demande envoyée » '
          '(it IS recorded), and « Configuration » re-reads its own', () async {
        final p = await loaded(me());
        answerPublish(
          ApiResponse.success(const PublishOutcome.requestedUnread()),
        );
        // The re-read answers the request.
        when(
          () => pro.getMyProvider(),
        ).thenAnswer((_) async => ApiResponse.success(me(validation: pending)));
        final session = _Session();

        final outcome = await p.publish(SalonId('p1'), session: session);
        expect(outcome?.saysRequestSent, isTrue);
        await p.publishSettled;

        expect(p.salonGoLiveState, GoLiveState.pending);
        expect(p.validation, pending);
        // The load's, then the re-read.
        verify(() => pro.getMyProvider()).called(2);
        expect(session.memberships, 1);
        expect(session.salons, 1);
      });

      test('409 validation_refused_final (a stale button) → « Mise en ligne '
          'refusée », then the state is re-read: the refused banner '
          '(decision 136 item 2)', () async {
        final p = await loaded(me());
        answerPublish(
          ApiResponse.error(
            'Mise en ligne refusée',
            code: 'validation_refused_final',
          ),
        );
        when(() => pro.getMyProvider()).thenAnswer(
          (_) async => ApiResponse.success(me(validation: refusedFinal)),
        );
        final session = _Session();

        expect(await p.publish(SalonId('p1'), session: session), isNull);
        // Said at the answer, before (and whatever) the re-read answers.
        expect(p.error, 'Mise en ligne refusée');
        expect(p.publishErrorCode, 'validation_refused_final');
        await p.publishSettled;

        expect(p.salonGoLiveState, GoLiveState.refusedFinal);
        expect(p.validation?.refusal?.isFinal, isTrue);
        expect(session.memberships, 1, reason: 'the card was stale too');
        expect(session.salons, 1);
      });

      test('a re-read that fails keeps the state it had', () async {
        final p = await loaded(me());
        answerPublish(
          ApiResponse.error(
            'Mise en ligne refusée',
            code: 'validation_refused_final',
          ),
        );
        when(() => pro.getMyProvider()).thenAnswer(
          (_) async => ApiResponse<MyProviderInfo>.error(kNoConnectionMessage),
        );
        await p.publish(SalonId('p1'), session: _Session());
        await p.publishSettled;
        expect(p.salonGoLiveState, GoLiveState.neverAsked);
        expect(p.error, 'Mise en ligne refusée');
      });

      test('a re-read answering ANOTHER salon is not taken', () async {
        final p = await loaded(me());
        answerPublish(
          ApiResponse.success(const PublishOutcome.requestedUnread()),
        );
        when(() => pro.getMyProvider()).thenAnswer(
          (_) async =>
              ApiResponse.success(me(id: 'p2', validation: refusedFinal)),
        );
        await p.publish(SalonId('p1'), session: _Session());
        await p.publishSettled;
        expect(p.salonGoLiveState, GoLiveState.neverAsked);
      });

      for (final code in ['incomplete', 'offer_required', 'forbidden']) {
        test('CONTROL — a refusal ($code) moves nothing: no re-read', () async {
          final p = await loaded(me());
          answerPublish(ApiResponse.error('Refus', code: code));
          final session = _Session();
          expect(await p.publish(SalonId('p1'), session: session), isNull);
          await p.publishSettled;
          expect(session.memberships, 0);
          expect(session.salons, 0);
          verify(() => pro.getMyProvider()).called(1); // the load's, only
          expect(p.salonGoLiveState, GoLiveState.neverAsked);
        });
      }
    });
  });

  group(
    '« Acompte & annulation » follows a SAVED choice (B7.7, decision 24)',
    () {
      // The server answers 200 with defaults for a salon that never chose
      // (`depositRequired: false`, `depositPercentage: 0`): an answer is not a
      // choice. docs/design/pro-app-batch7.md §2.7.
      Future<OnboardingStepStatus> depositStepFor(DepositPolicy policy) async {
        final salon = MockData.providers.first.copyWith(
          imageUrls: const ['a.jpg', 'b.jpg', 'c.jpg'],
        );
        when(() => pro.getProviderServices(SalonId('p1'))).thenAnswer(
          (_) async => ApiResponse.success(
            MockData.getServicesForProvider(SalonId('provider1')),
          ),
        );
        when(() => artists.getArtists(SalonId('p1'))).thenAnswer(
          (_) async => ApiResponse.success(
            MockData.getArtistsForProvider(SalonId('provider1')),
          ),
        );
        when(
          () => pro.getProviderAvailability(SalonId('p1')),
        ).thenAnswer((_) async => ApiResponse.success(salon.availability));
        when(
          () => pro.getDepositPolicy(SalonId('p1')),
        ).thenAnswer((_) async => ApiResponse.success(policy));
        when(() => pro.getMyProvider()).thenAnswer(
          (_) async => ApiResponse.success(
            MyProviderInfo(
              salon: salon,
              membership: ProMembership(
                role: TeamRole.owner,
                capabilities: presetCapabilitiesFor(TeamRole.owner),
                salonId: SalonId('p1'),
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
            providerId: SalonId('p1'),
          ),
          salonId: SalonId('p1'),
        );
        return statusOf(p, OnboardingStepKey.deposit);
      }

      test(
        'never chosen (the server\'s defaults) → optional, not done',
        () async {
          expect(
            await depositStepFor(
              const DepositPolicy(depositRequired: false, depositPercentage: 0),
            ),
            OnboardingStepStatus.optional,
          );
        },
      );

      test(
        'saved with deposits OFF (the form sends its 30 %) → done',
        () async {
          expect(
            await depositStepFor(
              const DepositPolicy(
                depositRequired: false,
                depositPercentage: 0.3,
              ),
            ),
            OnboardingStepStatus.done,
          );
        },
      );

      test('deposits ON → done', () async {
        expect(
          await depositStepFor(
            const DepositPolicy(depositRequired: true, depositPercentage: 0.3),
          ),
          OnboardingStepStatus.done,
        );
      });
    },
  );
}
