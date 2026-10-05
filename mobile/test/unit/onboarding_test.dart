import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/onboarding.dart';
import 'package:myweli/models/provider_user.dart';

void main() {
  List<OnboardingStep> build({
    bool profileComplete = true,
    bool locationSet = true,
    int serviceCount = 3,
    int staffCount = 1,
    bool availabilitySet = true,
    bool depositConfigured = true,
    int photoCount = 3,
    VerificationStatus verificationStatus = VerificationStatus.verified,
    bool hasSubmittedKyc = true,
    BusinessType businessType = BusinessType.salon,
  }) => buildOnboardingChecklist(
    profileComplete: profileComplete,
    locationSet: locationSet,
    serviceCount: serviceCount,
    staffCount: staffCount,
    availabilitySet: availabilitySet,
    depositConfigured: depositConfigured,
    photoCount: photoCount,
    verificationStatus: verificationStatus,
    hasSubmittedKyc: hasSubmittedKyc,
    businessType: businessType,
  );

  OnboardingStepStatus statusOf(
    List<OnboardingStep> steps,
    OnboardingStepKey key,
  ) => steps.firstWhere((s) => s.key == key).status;

  test('a fully-set salon has every step done and can go live', () {
    final steps = build();
    expect(steps.every((s) => s.isDone), isTrue);
    expect(canGoLive(steps), isTrue);
  });

  test('fewer than 3 services blocks services and go-live', () {
    final steps = build(serviceCount: 2);
    expect(
      statusOf(steps, OnboardingStepKey.services),
      OnboardingStepStatus.todo,
    );
    expect(canGoLive(steps), isFalse);
  });

  test('the map pin gates go-live (pro-salon-lifecycle L2)', () {
    final steps = build(locationSet: false);
    expect(
      statusOf(steps, OnboardingStepKey.location),
      OnboardingStepStatus.todo,
    );
    expect(canGoLive(steps), isFalse);
  });

  test('staff is optional for a freelancer and does not block go-live', () {
    final steps = build(businessType: BusinessType.other, staffCount: 0);
    expect(
      statusOf(steps, OnboardingStepKey.staff),
      OnboardingStepStatus.optional,
    );
    expect(canGoLive(steps), isTrue);
  });

  test('staff is required for a salon', () {
    expect(
      statusOf(build(staffCount: 0), OnboardingStepKey.staff),
      OnboardingStepStatus.todo,
    );
  });

  test('verification reflects the KYC state', () {
    expect(
      statusOf(
        build(verificationStatus: VerificationStatus.verified),
        OnboardingStepKey.verification,
      ),
      OnboardingStepStatus.done,
    );
    expect(
      statusOf(
        build(
          verificationStatus: VerificationStatus.pending,
          hasSubmittedKyc: true,
        ),
        OnboardingStepKey.verification,
      ),
      OnboardingStepStatus.inProgress,
    );
    expect(
      statusOf(
        build(
          verificationStatus: VerificationStatus.pending,
          hasSubmittedKyc: false,
        ),
        OnboardingStepKey.verification,
      ),
      OnboardingStepStatus.todo,
    );
  });

  test('verification and deposit do not block go-live (server mirror)', () {
    final steps = build(
      verificationStatus: VerificationStatus.pending,
      hasSubmittedKyc: false,
      depositConfigured: false,
    );
    expect(canGoLive(steps), isTrue);
  });

  test('photos gate go-live like the server (upload pipeline shipped)', () {
    expect(
      statusOf(build(photoCount: 0), OnboardingStepKey.photos),
      OnboardingStepStatus.todo,
    );
    expect(
      statusOf(build(photoCount: 3), OnboardingStepKey.photos),
      OnboardingStepStatus.done,
    );
    expect(canGoLive(build(photoCount: 0)), isFalse);
  });

  test('there is no offer step, and go-live never waits for an offer — the '
      'server starts the trial at the first publish (pro-companion-path)', () {
    // The checklist used to end on « Choisissez votre offre » / « 3 mois
    // offerts » and block « Mettre mon profil en ligne » until a choice was
    // made. The Pro app no longer offers a choice (App Store 3.1.3(f)), so a
    // gate on one would be a dead end it could not explain.
    final steps = build();
    expect(
      steps.map((s) => s.key.name),
      isNot(contains('offer')),
      reason: 'the offer step is back in the checklist',
    );
    expect(
      OnboardingStepKey.values.map((k) => k.name),
      isNot(contains('offer')),
    );
    // Every server gate key done, and nothing else asked: live.
    expect(canGoLive(steps), isTrue);
  });

  test('the go-live keys are exactly the server publish gate', () {
    // Each of the five gates, alone, blocks; nothing else does.
    expect(canGoLive(build(profileComplete: false)), isFalse);
    expect(canGoLive(build(locationSet: false)), isFalse);
    expect(canGoLive(build(serviceCount: 2)), isFalse);
    expect(canGoLive(build(availabilitySet: false)), isFalse);
    expect(canGoLive(build(photoCount: 2)), isFalse);
    expect(
      canGoLive(
        build(
          depositConfigured: false,
          verificationStatus: VerificationStatus.pending,
          hasSubmittedKyc: false,
          businessType: BusinessType.other,
          staffCount: 0,
        ),
      ),
      isTrue,
    );
  });

  test('progress ignores optional steps', () {
    final steps = build(
      businessType: BusinessType.other,
      staffCount: 0,
      photoCount: 0,
    );
    final p = onboardingProgress(steps);
    // actionable = profile, location, services, availability, deposit,
    // verification, photos (staff optional for a freelancer; no offer step).
    expect(p.total, 7);
    expect(p.done, 6); // photos still todo
  });
}
