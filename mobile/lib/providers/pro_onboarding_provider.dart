import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/access/salon_state_refresh.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/deposit.dart';
import '../core/utils/onboarding.dart';
import '../core/utils/salon_go_live.dart';
import '../core/utils/salon_id.dart';
import '../models/api_response.dart';
import '../models/availability.dart';
import '../models/provider_user.dart';
import '../models/salon_validation.dart';
import '../services/interfaces/pro_service_interface.dart';
import 'locality_provider.dart';

/// What « Profil de l’entreprise » needs from the salon: the three fields
/// filled, and where its commune comes from (R8).
typedef _Profile = ({bool filled, String? areaId, String? commune});

const _Profile _noProfile = (filled: false, areaId: null, commune: null);

/// Loads the inputs each onboarding step depends on (services, staff,
/// availability, deposit policy, listing photos, KYC) and exposes the computed
/// checklist + progress.
class ProOnboardingProvider extends ChangeNotifier implements SalonScoped {
  bool _isLoading = false;
  bool _loadFailed = false;
  String? _error;

  /// The checklist as the last settled load read it, given whether the
  /// profile step is done — built on demand ([steps]) rather than once at
  /// the load, because R8's half of that step depends on MyWeli's area tree,
  /// which the screen reads on its own clock ([_areas]): it counts the
  /// moment it lands, and the load never waits for it nor fails with it.
  List<OnboardingStep> Function(bool profileComplete)? _checklist;
  _Profile _profile = _noProfile;

  /// R8's lookup: the screen's tree of MyWeli's areas, handed to [load] —
  /// never read there. Null, or not read yet, or failed: today's three-field
  /// rule (the server decides — `communeIsKnown`).
  LocalityProvider? _areas;

  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;

  /// What these fields hold is the server's, not the defaults they start
  /// with: a read has answered since the last reset (B9.8). The screen
  /// waits for it — on the first frame it showed the defaults.
  bool get loaded => _loaded;
  bool _loaded = false;
  String? get error => _error;
  List<OnboardingStep> get steps {
    final checklist = _checklist;
    if (checklist == null) return const [];
    return checklist(_profile.filled && _communeKnown != false);
  }

  bool get readyToGoLive => canGoLive(steps);
  ({int done, int total}) get progress => onboardingProgress(steps);

  /// R8 (docs/design/salon-go-live-approval.md §6.3): the salon's commune
  /// as the server's `validArea` reads it — null while the tree is unread.
  bool? get _communeKnown => communeIsKnown(
    areaId: _profile.areaId,
    commune: _profile.commune,
    areas: _areas?.knownAreas,
  );

  /// « Profil de l’entreprise » is filled, and its commune is the ONE thing
  /// the server would refuse: typed by hand, it names none of MyWeli's
  /// areas. The step's sub-line then says « Choisissez la commune dans la
  /// liste » (decision 136 item 4) — and only then: an unread tree, a
  /// missing field, a commune from the list say nothing of the kind.
  bool get communeNotInList =>
      _checklist != null && _profile.filled && _communeKnown == false;

  /// The tree moved (it landed, failed, was read again): the profile step
  /// may have with it.
  void _areasMoved() {
    if (_checklist != null) notifyListeners();
  }

  void _watchAreas(LocalityProvider? areas) {
    if (identical(areas, _areas)) return;
    _areas?.removeListener(_areasMoved);
    _areas = areas;
    areas?.addListener(_areasMoved);
  }

  @override
  void dispose() {
    _areas?.removeListener(_areasMoved);
    super.dispose();
  }

  bool _isPublishing = false;
  bool get isPublishing => _isPublishing;

  /// Machine code of the last publish failure (`offer_required` → the
  /// screen's neutral « l’offre n’est plus active » sentence, no action;
  /// `validation_refused_final` → « Mise en ligne refusée », the state
  /// re-read).
  String? _publishErrorCode;
  String? get publishErrorCode => _publishErrorCode;

  // ---- Where the salon stands with MyWeli's validation (B0.18) -------------
  //
  // « Configuration »'s copy of the salon's state — from its load's own GET
  // /me/provider, then from each publish's answer — never the session's: the
  // home card's copy lives in `ProAuthProvider`, and the two stay in step
  // because [publish] makes both re-read (see [SalonStateRefresh]).

  /// The salon's `status` as last read (`Provider.status`; null reads
  /// `active`, as seeded documents carry none).
  String? _salonStatus;
  SalonValidation? _validation;
  bool _validationSent = false;

  /// A read (or a publish's answer) has said where the salon stands.
  bool _stateKnown = false;

  /// The salon's validation as last read — the refusal's code and note, and
  /// the request's date (« Demande envoyée le … »).
  SalonValidation? get validation => _validation;

  /// What « Configuration » shows (the website's derivation, `goLiveState`):
  /// null until a read answered — before the load, and for a pro with no
  /// salon yet (nothing to read). [GoLiveState.legacy] on a server from
  /// before B0.18: today's screen (decision 136 item 10).
  GoLiveState? get salonGoLiveState => _stateKnown
      ? goLiveState(
          status: _salonStatus,
          validationSent: _validationSent,
          validation: _validation,
        )
      : null;

  /// The re-reads the last [publish] started, done. The snackbar is said at
  /// the answer, never after them; the screen waits on them only to bring
  /// a 409 `validation_refused_final`'s reason on screen once its own
  /// re-read has drawn it (decision 136 item 2).
  Future<void> get publishSettled => _publishSettled ?? Future<void>.value();
  Future<void>? _publishSettled;

  /// Ask MyWeli to put the salon online — or take it back online (B0.18 —
  /// docs/design/salon-go-live-approval.md §3.1): the outcome on success
  /// (200 live, 202 a request), null on a refusal ([error] and
  /// [publishErrorCode] say why; the server re-checks the gate).
  ///
  /// **The ONE place a submit refreshes the salon's state (§6.2).**
  /// « Configuration » takes the answer at once: a 200 is `active`; a 202
  /// readable body is the request's `validation` (decision 136 item 7: a
  /// `refused` or `null` one is just shown, the screen says no « Demande
  /// envoyée »). Then [session] re-reads its two copies — the home card's
  /// (`refreshMembership`) and « Mes salons »' (`loadMySalons`), each after
  /// any read already out — so the card, the picker and this screen say the
  /// same thing. Where the answer does not carry the state — a 202 whose
  /// body this build could not read, a 409 `validation_refused_final` (a
  /// stale button, decision 136 item 2) — « Configuration » re-reads its own
  /// too, quietly (no skeleton). None of it is awaited here;
  /// [publishSettled] is.
  Future<PublishOutcome?> publish(
    SalonId providerId, {
    required SalonStateRefresh session,
  }) async {
    final scope = _scope;
    _isPublishing = true;
    _error = null;
    _publishErrorCode = null;
    notifyListeners();
    final ApiResponse<PublishOutcome> res;
    try {
      res = await serviceLocator.proService.publishSalon(providerId);
    } catch (_) {
      // The services answer failures; a throw is a bug — said as one, and
      // the button comes back.
      if (scope != _scope) return null;
      _isPublishing = false;
      _error = kGenericErrorMessage;
      notifyListeners();
      return null;
    }
    // Another salon or account since: its screen shows nothing of this one.
    if (scope != _scope) return res.success ? res.data : null;
    _isPublishing = false;
    final outcome = res.success ? res.data : null;
    if (outcome == null) {
      _error = res.error ?? 'La mise en ligne a échoué';
      _publishErrorCode = res.code;
      notifyListeners();
      if (res.code == 'validation_refused_final') {
        _settleAfterPublish(providerId, session, rereadOwn: true);
      }
      return null;
    }
    if (outcome.isLive) {
      _salonStatus = 'active';
      _stateKnown = true;
    } else if (outcome.validationRead) {
      // A 202 is only ever a draft's: an active salon answers 200, a
      // suspended one 403 (§3.1).
      _salonStatus = 'draft';
      _validation = outcome.validation;
      _validationSent = true;
      _stateKnown = true;
    }
    notifyListeners();
    _settleAfterPublish(
      providerId,
      session,
      rereadOwn: !outcome.isLive && !outcome.validationRead,
    );
    return outcome;
  }

  void _settleAfterPublish(
    SalonId providerId,
    SalonStateRefresh session, {
    required bool rereadOwn,
  }) {
    _publishSettled =
        Future.wait<void>([
          session.rereadMembership(),
          session.rereadMySalons(),
          if (rereadOwn) _rereadState(providerId),
        ]).then<void>(
          (_) {},
          // Each one keeps what it had on a failure, by itself; nothing to
          // say here.
          onError: (Object _) {},
        );
  }

  /// GET /me/provider for the salon's state alone — quiet: the checklist
  /// stays on screen. Written only for [providerId], in the same scope.
  Future<void> _rereadState(SalonId providerId) async {
    final scope = _scope;
    try {
      final res = await serviceLocator.proService.getMyProvider();
      final info = res.data;
      if (scope != _scope || !res.success || info == null) return;
      if (info.salon.id != providerId) return;
      _takeState(info);
      notifyListeners();
    } catch (_) {
      /* the state stays as it was; the next load reads it again */
    }
  }

  /// The salon's state, from a GET /me/provider answer.
  void _takeState(MyProviderInfo info) {
    _salonStatus = info.salon.status;
    _validation = info.validation;
    _validationSent = info.validationSent;
    _stateKnown = true;
  }

  /// [salonId] is the ACTING salon (`ProAuthProvider.activeSalonId`), never
  /// the account's default `providerId`: R6's « Ajouter un salon » switches
  /// to the new draft and lands here, and the checklist counted the default
  /// salon's services, team, hours and deposit under the new salon's name
  /// (docs/design/r6-salon-id-pin.md). [proUser] stays for what is the
  /// account's own: its KYC and its business type.
  ///
  /// [areas] is the screen's tree of MyWeli's areas, for R8 — kept, never
  /// read here: the load's six reads stay six, and a tree that fails cannot
  /// fail the checklist ([communeNotInList]).
  Future<void> load(
    ProviderUser proUser, {
    required SalonId? salonId,
    LocalityProvider? areas,
  }) async {
    _watchAreas(areas);
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
      var profile = _noProfile;
      var locationSet = false;
      MyProviderInfo? state;

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
        // The same answer says where the salon stands with MyWeli's
        // validation (B0.18): no read of its own.
        state = listing;
        photoCount = listing?.salon.imageUrls.length ?? 0;
        // Mirror the server's publish gate (pro-salon-lifecycle):
        // profile = description + address + commune, the commune one of
        // MyWeli's (R8 — judged on demand against the tree, [steps]);
        // location = the map pin.
        final l = listing?.salon;
        profile = (
          filled:
              l != null &&
              l.description.trim().isNotEmpty &&
              l.address.trim().isNotEmpty &&
              (l.commune ?? '').trim().isNotEmpty,
          areaId: l?.areaId,
          commune: l?.commune,
        );
        locationSet = l?.latitude != null && l?.longitude != null;
        // No offer read: the offer is not a step — the server starts the
        // trial when MyWeli validates the salon (B0.18 §3.6; it was the
        // first publish before — docs/design/pro-companion-path.md).
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

      final businessType = proUser.businessType;
      _profile = profile;
      _checklist = (profileComplete) => buildOnboardingChecklist(
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
      if (state != null) _takeState(state);
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
    _checklist = null;
    _profile = _noProfile;
    _isPublishing = false;
    _publishErrorCode = null;
    _salonStatus = null;
    _validation = null;
    _validationSent = false;
    _stateKnown = false;
    _publishSettled = null;
    notifyListeners();
  }
}
