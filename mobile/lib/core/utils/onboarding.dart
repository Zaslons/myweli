import '../../models/provider_user.dart';

enum OnboardingStepKey {
  profile,
  services,
  staff,
  availability,
  deposit,
  verification,
  photos,
}

enum OnboardingStepStatus { done, todo, inProgress, optional }

class OnboardingStep {
  final OnboardingStepKey key;
  final OnboardingStepStatus status;

  const OnboardingStep(this.key, this.status);

  bool get isDone => status == OnboardingStepStatus.done;
}

const int kMinServices = 3;
const int kMinPhotos = 3;

/// Builds the ordered onboarding checklist from the provider's current data.
/// Pure and deterministic so it can be unit-tested.
List<OnboardingStep> buildOnboardingChecklist({
  required bool profileComplete,
  required int serviceCount,
  required int staffCount,
  required bool availabilitySet,
  required bool depositConfigured,
  required int photoCount,
  required VerificationStatus verificationStatus,
  required bool hasSubmittedKyc,
  required BusinessType businessType,
}) {
  OnboardingStepStatus doneIf(bool ok) =>
      ok ? OnboardingStepStatus.done : OnboardingStepStatus.todo;

  OnboardingStepStatus verificationStep() {
    if (verificationStatus == VerificationStatus.verified) {
      return OnboardingStepStatus.done;
    }
    if (hasSubmittedKyc && verificationStatus == VerificationStatus.pending) {
      return OnboardingStepStatus.inProgress;
    }
    return OnboardingStepStatus.todo; // no docs yet, or rejected
  }

  // Staff is optional for solo freelancers (businessType == other).
  final staffStatus = businessType == BusinessType.other
      ? (staffCount >= 1
          ? OnboardingStepStatus.done
          : OnboardingStepStatus.optional)
      : doneIf(staffCount >= 1);

  // Photo upload UI is deferred to the image pipeline: done if the listing
  // already has enough, otherwise optional (can't upload on-device yet).
  final photosStatus = photoCount >= kMinPhotos
      ? OnboardingStepStatus.done
      : OnboardingStepStatus.optional;

  return [
    OnboardingStep(OnboardingStepKey.profile, doneIf(profileComplete)),
    OnboardingStep(
        OnboardingStepKey.services, doneIf(serviceCount >= kMinServices)),
    OnboardingStep(OnboardingStepKey.staff, staffStatus),
    OnboardingStep(OnboardingStepKey.availability, doneIf(availabilitySet)),
    OnboardingStep(OnboardingStepKey.deposit, doneIf(depositConfigured)),
    OnboardingStep(OnboardingStepKey.verification, verificationStep()),
    OnboardingStep(OnboardingStepKey.photos, photosStatus),
  ];
}

/// The self-serve essentials that gate go-live. Verification (admin-gated) and
/// photos (pending the image pipeline) are shown but don't block.
const Set<OnboardingStepKey> _goLiveKeys = {
  OnboardingStepKey.profile,
  OnboardingStepKey.services,
  OnboardingStepKey.availability,
  OnboardingStepKey.deposit,
};

bool canGoLive(List<OnboardingStep> steps) =>
    steps.where((s) => _goLiveKeys.contains(s.key)).every((s) => s.isDone);

/// Progress over the actionable steps (optional ones don't count).
({int done, int total}) onboardingProgress(List<OnboardingStep> steps) {
  final actionable =
      steps.where((s) => s.status != OnboardingStepStatus.optional).toList();
  return (
    done: actionable.where((s) => s.isDone).length,
    total: actionable.length,
  );
}
