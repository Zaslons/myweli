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
  }) =>
      buildOnboardingChecklist(
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
          List<OnboardingStep> steps, OnboardingStepKey key) =>
      steps.firstWhere((s) => s.key == key).status;

  test('a fully-set salon has every step done and can go live', () {
    final steps = build();
    expect(steps.every((s) => s.isDone), isTrue);
    expect(canGoLive(steps), isTrue);
  });

  test('fewer than 3 services blocks services and go-live', () {
    final steps = build(serviceCount: 2);
    expect(
        statusOf(steps, OnboardingStepKey.services), OnboardingStepStatus.todo);
    expect(canGoLive(steps), isFalse);
  });

  test('the map pin gates go-live (pro-salon-lifecycle L2)', () {
    final steps = build(locationSet: false);
    expect(
        statusOf(steps, OnboardingStepKey.location), OnboardingStepStatus.todo);
    expect(canGoLive(steps), isFalse);
  });

  test('staff is optional for a freelancer and does not block go-live', () {
    final steps = build(businessType: BusinessType.other, staffCount: 0);
    expect(statusOf(steps, OnboardingStepKey.staff),
        OnboardingStepStatus.optional);
    expect(canGoLive(steps), isTrue);
  });

  test('staff is required for a salon', () {
    expect(statusOf(build(staffCount: 0), OnboardingStepKey.staff),
        OnboardingStepStatus.todo);
  });

  test('verification reflects the KYC state', () {
    expect(
      statusOf(build(verificationStatus: VerificationStatus.verified),
          OnboardingStepKey.verification),
      OnboardingStepStatus.done,
    );
    expect(
      statusOf(
          build(
              verificationStatus: VerificationStatus.pending,
              hasSubmittedKyc: true),
          OnboardingStepKey.verification),
      OnboardingStepStatus.inProgress,
    );
    expect(
      statusOf(
          build(
              verificationStatus: VerificationStatus.pending,
              hasSubmittedKyc: false),
          OnboardingStepKey.verification),
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
    expect(statusOf(build(photoCount: 0), OnboardingStepKey.photos),
        OnboardingStepStatus.todo);
    expect(statusOf(build(photoCount: 3), OnboardingStepKey.photos),
        OnboardingStepStatus.done);
    expect(canGoLive(build(photoCount: 0)), isFalse);
  });

  test('progress ignores optional steps', () {
    final steps = build(
      businessType: BusinessType.other,
      staffCount: 0,
      photoCount: 0,
    );
    final p = onboardingProgress(steps);
    // actionable = profile, location, services, availability, deposit,
    // verification, photos (staff optional for a freelancer).
    expect(p.total, 7);
    expect(p.done, 6); // photos still todo
  });
}
