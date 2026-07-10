import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../core/utils/onboarding.dart';
import '../models/availability.dart';
import '../models/provider_user.dart';

/// Loads the inputs each onboarding step depends on (services, staff,
/// availability, deposit policy, listing photos, KYC) and exposes the computed
/// checklist + progress.
class ProOnboardingProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool _loadFailed = false;
  String? _error;
  List<OnboardingStep> _steps = const [];

  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;
  String? get error => _error;
  List<OnboardingStep> get steps => _steps;
  bool get readyToGoLive => canGoLive(_steps);
  ({int done, int total}) get progress => onboardingProgress(_steps);

  bool _isPublishing = false;
  bool get isPublishing => _isPublishing;

  /// Take the salon live (docs/design/pro-salon-lifecycle.md B3). The server
  /// re-checks the gate; `incomplete` surfaces its message. True on success.
  Future<bool> publish(String providerId) async {
    _isPublishing = true;
    _error = null;
    notifyListeners();
    final res = await serviceLocator.proService.publishSalon(providerId);
    _isPublishing = false;
    if (!res.success) _error = res.error ?? 'La mise en ligne a échoué';
    notifyListeners();
    return res.success;
  }

  Future<void> load(ProviderUser proUser) async {
    _isLoading = true;
    _loadFailed = false;
    _error = null;
    notifyListeners();

    try {
      final providerId = proUser.providerId;
      var serviceCount = 0;
      var staffCount = 0;
      var availabilitySet = false;
      var depositConfigured = false;
      var photoCount = 0;

      // A brand-new pro has no public listing yet — counts stay 0.
      if (providerId != null && providerId.isNotEmpty) {
        final pro = serviceLocator.proService;

        final services = await pro.getProviderServices(providerId);
        serviceCount = services.data?.length ?? 0;

        final staff =
            await serviceLocator.proArtistService.getArtists(providerId);
        staffCount = staff.data?.length ?? 0;

        final avail = await pro.getProviderAvailability(providerId);
        availabilitySet = avail.data != null && _hasAvailableSlot(avail.data!);

        final deposit = await pro.getDepositPolicy(providerId);
        depositConfigured = deposit.success && deposit.data != null;

        final listing =
            await serviceLocator.providerService.getProviderById(providerId);
        photoCount = listing.data?.imageUrls.length ?? 0;
      }

      final kyc = await serviceLocator.proKycService.getKycStatus(proUser.id);
      final verificationStatus = kyc.data?.status ?? proUser.verificationStatus;
      final hasSubmittedKyc = kyc.data?.documents.isNotEmpty ?? false;

      _steps = buildOnboardingChecklist(
        profileComplete: proUser.businessName.isNotEmpty,
        serviceCount: serviceCount,
        staffCount: staffCount,
        availabilitySet: availabilitySet,
        depositConfigured: depositConfigured,
        photoCount: photoCount,
        verificationStatus: verificationStatus,
        hasSubmittedKyc: hasSubmittedKyc,
        businessType: proUser.businessType,
      );
      _loadFailed = false;
    } catch (e) {
      _loadFailed = true;
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _hasAvailableSlot(Availability availability) =>
      availability.weeklySchedule.values
          .any((slots) => slots.any((s) => s.isAvailable));
}
