import '../../models/provider_user.dart';

enum OnboardingStepKey {
  profile,
  location,
  services,
  staff,
  availability,
  deposit,
  verification,
  photos,
  offer,
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
  required bool locationSet,
  required int serviceCount,
  required int staffCount,
  required bool availabilitySet,
  required bool depositConfigured,
  required int photoCount,
  required VerificationStatus verificationStatus,
  required bool hasSubmittedKyc,
  required BusinessType businessType,
  required bool offerLive,
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

  return [
    OnboardingStep(OnboardingStepKey.profile, doneIf(profileComplete)),
    OnboardingStep(OnboardingStepKey.location, doneIf(locationSet)),
    OnboardingStep(
        OnboardingStepKey.services, doneIf(serviceCount >= kMinServices)),
    OnboardingStep(OnboardingStepKey.staff, staffStatus),
    OnboardingStep(OnboardingStepKey.availability, doneIf(availabilitySet)),
    OnboardingStep(OnboardingStepKey.deposit, doneIf(depositConfigured)),
    OnboardingStep(OnboardingStepKey.verification, verificationStep()),
    // The upload pipeline shipped — photos gate go-live like the server does.
    OnboardingStep(OnboardingStepKey.photos, doneIf(photoCount >= kMinPhotos)),
    // Pricing pivot (team access R2a/R3): publishing requires a live offer
    // (trial/paid/grace) — the server gate's `offer` key mirrored.
    OnboardingStep(OnboardingStepKey.offer, doneIf(offerLive)),
  ];
}

/// The steps that gate « Mettre mon profil en ligne » — the MIRROR of the
/// server's publish gate (docs/design/pro-salon-lifecycle.md + the R2a
/// pricing pivot): profile + location + ≥3 services + hours + ≥3 photos +
/// a live offer. Deposit and verification are shown and recommended but
/// never block (matching the server).
const Set<OnboardingStepKey> _goLiveKeys = {
  OnboardingStepKey.profile,
  OnboardingStepKey.location,
  OnboardingStepKey.services,
  OnboardingStepKey.availability,
  OnboardingStepKey.photos,
  OnboardingStepKey.offer,
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
