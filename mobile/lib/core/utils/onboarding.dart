import '../../models/locality.dart';
import '../../models/provider_user.dart';
import 'slug.dart';

enum OnboardingStepKey {
  profile,
  location,
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

/// R8 — the server's `validArea` (`SalonProvisioningService.publishGate`;
/// docs/design/salon-go-live-approval.md §6.3, web-salon-validation.md §5,
/// the website's `communeIsKnown`): whether the salon's commune is one the
/// publish gate takes.
///
/// - an [areaId] → yes (the server only ever stores a resolved one);
/// - no commune → no (the profile is not filled anyway);
/// - [areas] null — MyWeli's area tree not read (loading, failed) → null:
///   this side cannot tell, and the server decides. Blocking a valid salon
///   on a failed read would be worse than its 409;
/// - else the commune must name an area the way `seedAreaForCommuneName`
///   matches it: `slugify(commune)` equals the area's `slug`, or `slugify`
///   of its name ([slugify] is the backend's twin).
bool? communeIsKnown({
  required String? areaId,
  required String? commune,
  required Iterable<LocalityArea>? areas,
}) {
  if (areaId != null) return true;
  final name = (commune ?? '').trim();
  if (name.isEmpty) return false;
  if (areas == null) return null;
  final wanted = slugify(name);
  if (wanted.isEmpty) return false;
  return areas.any((a) => a.slug == wanted || slugify(a.name) == wanted);
}

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
      OnboardingStepKey.services,
      doneIf(serviceCount >= kMinServices),
    ),
    OnboardingStep(OnboardingStepKey.staff, staffStatus),
    OnboardingStep(OnboardingStepKey.availability, doneIf(availabilitySet)),
    // Never a todo (B7.7, decision 24): done once a choice is saved, else
    // optional — a deposit is not a go-live condition.
    OnboardingStep(
      OnboardingStepKey.deposit,
      depositConfigured
          ? OnboardingStepStatus.done
          : OnboardingStepStatus.optional,
    ),
    OnboardingStep(OnboardingStepKey.verification, verificationStep()),
    // The upload pipeline shipped — photos gate go-live like the server does.
    OnboardingStep(OnboardingStepKey.photos, doneIf(photoCount >= kMinPhotos)),
    // No offer step. The server starts the salon's trial when MyWeli
    // validates it (B0.18 §3.6 — the first publish before), so a salon with
    // no offer asks like any other — and the Pro app never asks for a choice
    // it may not offer (App Store 3.1.1, docs/design/pro-companion-path.md
    // §2.2).
  ];
}

/// The steps that gate the publish button (« Demander la mise en ligne »,
/// « Mettre mon profil en ligne » on a server from before B0.18) — the
/// MIRROR of the server's publish gate (docs/design/pro-salon-lifecycle.md):
/// profile (its commune one of MyWeli's — R8, [communeIsKnown]) + location +
/// ≥3 services + hours + ≥3 photos. Deposit and verification are shown and
/// recommended but never block (matching the server). The offer is not a
/// step: the server starts the trial when MyWeli validates the salon (B0.18
/// §3.6), and refuses (`offer_required`) only a salon whose offer EXPIRED — a
/// state the checklist cannot fix (docs/design/pro-companion-path.md §3.1).
const Set<OnboardingStepKey> _goLiveKeys = {
  OnboardingStepKey.profile,
  OnboardingStepKey.location,
  OnboardingStepKey.services,
  OnboardingStepKey.availability,
  OnboardingStepKey.photos,
};

bool canGoLive(List<OnboardingStep> steps) =>
    steps.where((s) => _goLiveKeys.contains(s.key)).every((s) => s.isDone);

/// Progress over the actionable steps (optional ones don't count).
({int done, int total}) onboardingProgress(List<OnboardingStep> steps) {
  final actionable = steps
      .where((s) => s.status != OnboardingStepStatus.optional)
      .toList();
  return (
    done: actionable.where((s) => s.isDone).length,
    total: actionable.length,
  );
}
