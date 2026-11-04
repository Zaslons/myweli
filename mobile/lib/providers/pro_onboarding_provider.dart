import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/deposit.dart';
import '../core/utils/onboarding.dart';
import '../core/utils/salon_id.dart';
import '../models/api_response.dart';
import '../models/availability.dart';
import '../models/provider_user.dart';

/// Loads the inputs each onboarding step depends on (services, staff,
/// availability, deposit policy, listing photos, KYC) and exposes the computed
/// checklist + progress.
class ProOnboardingProvider extends ChangeNotifier implements SalonScoped {
  bool _isLoading = false;
  bool _loadFailed = false;
  String? _error;
  List<OnboardingStep> _steps = const [];

  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;

  /// What these fields hold is the server's, not the defaults they start
  /// with: a read has answered since the last reset (B9.8). The screen
  /// waits for it — on the first frame it showed the defaults.
  bool get loaded => _loaded;
  bool _loaded = false;
  String? get error => _error;
  List<OnboardingStep> get steps => _steps;
  bool get readyToGoLive => canGoLive(_steps);
  ({int done, int total}) get progress => onboardingProgress(_steps);

  bool _isPublishing = false;
  bool get isPublishing => _isPublishing;

  /// Machine code of the last publish failure (`offer_required` → the
  /// screen's neutral « l’offre n’est plus active » sentence, no action).
  String? _publishErrorCode;
  String? get publishErrorCode => _publishErrorCode;

  /// Take the salon live (docs/design/pro-salon-lifecycle.md B3). The server
  /// re-checks the gate; `incomplete` surfaces its message. True on success.
  Future<bool> publish(SalonId providerId) async {
    final scope = _scope;
    _isPublishing = true;
    _error = null;
    _publishErrorCode = null;
    notifyListeners();
    final res = await serviceLocator.proService.publishSalon(providerId);
    if (scope != _scope) return res.success;
    _isPublishing = false;
    if (!res.success) {
      _error = res.error ?? 'La mise en ligne a échoué';
      _publishErrorCode = res.code;
    }
    notifyListeners();
    return res.success;
  }

  /// [salonId] is the ACTING salon (`ProAuthProvider.activeSalonId`), never
  /// the account's default `providerId`: R6's « Ajouter un salon » switches
  /// to the new draft and lands here, and the checklist counted the default
  /// salon's services, team, hours and deposit under the new salon's name
  /// (docs/design/r6-salon-id-pin.md). [proUser] stays for what is the
  /// account's own: its KYC and its business type.
  Future<void> load(ProviderUser proUser, {required SalonId? salonId}) async {
    final scope = _scope;
    _isLoading = true;
    _loadFailed = false;
    _error = null;
    notifyListeners();

    try {
      // A read that failed is not « nothing done ». Every service answers a
      // failure instead of throwing, and each read below took one for ✗: a
      // salon offline saw its whole checklist to do, and the error state
      // under it could not be reached (B9.8). The first failure is the
      // load's.
      String? failure;
      T? read<T>(ApiResponse<T> res) {
        if (!res.success) failure ??= res.error ?? kGenericErrorMessage;
        return res.data;
      }

      final providerId = salonId;
      var serviceCount = 0;
      var staffCount = 0;
      var availabilitySet = false;
      var depositConfigured = false;
      var photoCount = 0;
      var profileComplete = false;
      var locationSet = false;

      // A brand-new pro has no public listing yet — counts stay 0.
      if (providerId != null && providerId.isNotEmpty) {
        final pro = serviceLocator.proService;

        final services = read(await pro.getProviderServices(providerId));
        if (scope != _scope) return;
        // ACTIVE services, as the server's gate counts them
        // (docs/design/web-pro-golive-signup-like-app.md §1): counting the
        // hidden ones said ✓ to a salon the server would refuse.
        serviceCount = services?.where((service) => service.active).length ?? 0;

        final staff = read(
          await serviceLocator.proArtistService.getArtists(providerId),
        );
        if (scope != _scope) return;
        staffCount = staff?.length ?? 0;

        final avail = read(await pro.getProviderAvailability(providerId));
        if (scope != _scope) return;
        availabilitySet = avail != null && _hasAvailableSlot(avail);

        // Configured = a choice SAVED, not an answer: the server answers
        // every salon with defaults (B7.7).
        final policy = read(await pro.getDepositPolicy(providerId));
        if (scope != _scope) return;
        depositConfigured =
            policy != null &&
            depositChosen(
              depositRequired: policy.depositRequired,
              percentage: policy.depositPercentage,
            );

        // By account, not by public id — and note this stays INSIDE the
        // `providerId != null` guard: a brand-new pro with no salon must not
        // issue the call at all. The checklist exists precisely while the
        // salon is a draft, which is the state the public read is about to
        // stop serving, and a failed read here is NOT a throw — it would have
        // rendered a plausible all-todo checklist with no error at all.
        final listing = read(await pro.getMyProvider());
        if (scope != _scope) return;
        photoCount = listing?.salon.imageUrls.length ?? 0;
        // Mirror the server's publish gate (pro-salon-lifecycle):
        // profile = description + address + commune; location = the map pin.
        final l = listing?.salon;
        profileComplete =
            l != null &&
            l.description.trim().isNotEmpty &&
            l.address.trim().isNotEmpty &&
            (l.commune ?? '').trim().isNotEmpty;
        locationSet = l?.latitude != null && l?.longitude != null;
        // No offer read: the offer is not a step — the server starts the
        // trial at the first publish (docs/design/pro-companion-path.md).
      }

      final kyc = read(
        await serviceLocator.proKycService.getKycStatus(proUser.id),
      );
      if (scope != _scope) return;
      if (failure != null) {
        _loadFailed = true;
        _error = failure;
        return;
      }
      final verificationStatus = kyc?.status ?? proUser.verificationStatus;
      final hasSubmittedKyc = kyc?.documents.isNotEmpty ?? false;

      _steps = buildOnboardingChecklist(
        profileComplete: profileComplete,
        locationSet: locationSet,
        serviceCount: serviceCount,
        staffCount: staffCount,
        availabilitySet: availabilitySet,
        depositConfigured: depositConfigured,
        photoCount: photoCount,
        verificationStatus: verificationStatus,
        hasSubmittedKyc: hasSubmittedKyc,
        businessType: proUser.businessType,
      );
      _loaded = true;
      _loadFailed = false;
    } catch (e) {
      if (scope != _scope) return;
      _loadFailed = true;
      _error = kGenericErrorMessage;
    } finally {
      if (scope == _scope) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// A day with hours — the server's rule (`publishGate`: some weekday is a
  /// non-empty list), whatever each slot's flag says; the `isAvailable` test
  /// this replaced said ✗ to a salon the server would publish.
  bool _hasAvailableSlot(Availability availability) =>
      availability.weeklySchedule.values.any((slots) => slots.isNotEmpty);

  /// R6 multi-salons: drop the previous salon's data on a switch.
  /// Which salon this state belongs to — moved by [resetForSalonSwitch]
  /// only. A read or a write takes it before it awaits and writes nothing
  /// when it moved meanwhile: its answer is the previous salon's, or the
  /// previous account's (docs/design/pro-account-scope.md §2.2).
  int _scope = 0;

  @override
  void resetForSalonSwitch() {
    _scope++;
    _loaded = false;
    _isLoading = false;
    _loadFailed = false;
    _error = null;
    _steps = const [];
    _isPublishing = false;
    _publishErrorCode = null;
    notifyListeners();
  }
}
