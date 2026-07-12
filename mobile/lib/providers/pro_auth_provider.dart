import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/access/pro_access_guard.dart';
import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../core/router/pro_router.dart';
import '../models/api_response.dart';
import '../models/pro_membership.dart';
import '../models/provider_login_result.dart';
import '../models/provider_user.dart';
import '../models/salon_membership_info.dart';
import '../models/team_invitation.dart';
import '../models/team_member.dart';
import '../services/interfaces/auth_service_interface.dart';

class ProAuthProvider extends ChangeNotifier {
  final AuthServiceInterface _authService = serviceLocator.authService;

  ProviderUser? _provider;
  bool _isLoading = false;
  String? _error;

  ProviderUser? get provider => _provider;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _provider != null;

  // ---- Membership (team access R4b) ----------------------------------------

  /// The acting membership from GET /me/provider — cached in the persisted
  /// session for instant cold-start shaping, refreshed each start. UI gating
  /// only; the server recomputes every decision (T38).
  ProMembership? _membership;
  ProMembership? get membership => _membership;

  TeamRole get role => _membership?.role ?? TeamRole.owner;
  bool get isStaff => _membership?.role == TeamRole.staff;

  // ---- Multi-salons (team access R6) ----------------------------------------

  /// The salon the user SWITCHED to (« Mes salons »), null = the default.
  /// Persisted in the session (cold-start continuity) and revalidated by
  /// every `?salonId=` request server-side (T55).
  String? _selectedSalonId;
  String? get selectedSalonId => _selectedSalonId;

  /// « Mes salons » — the switcher payload (loaded at start + on demand).
  List<SalonMembershipInfo> _salons = const [];
  List<SalonMembershipInfo> get salons => _salons;
  bool get hasMultipleSalons => _salons.length > 1;

  /// Server-computed « Ajouter un salon » gate (≥1 owned live Réseau).
  bool _canAddSalon = false;
  bool get canAddSalon => _canAddSalon;

  bool _loadingSalons = false;

  /// Refresh « Mes salons » (best-effort — the switcher opens on cached
  /// data and refreshes in place).
  Future<void> loadMySalons() async {
    if (_provider == null || _loadingSalons) return;
    _loadingSalons = true;
    try {
      final res = await serviceLocator.proService.getMySalons();
      if (res.success && res.data != null) {
        _salons = res.data!.items;
        _canAddSalon = res.data!.canAddSalon;
        notifyListeners();
      }
    } catch (_) {/* keep the cached list */} finally {
      _loadingSalons = false;
    }
  }

  /// Switch the acting salon: validate against the server (the membership
  /// there becomes the new shape), persist the selection, and RESET every
  /// per-salon provider so no stale cross-salon data lingers. False = the
  /// selection was refused (revoked there / salon gone) — the caller stays
  /// on the current salon and the list refreshes.
  Future<bool> switchSalon(String salonId) async {
    if (_provider == null) return false;
    if (salonId == activeSalonId) return true;
    _isLoading = true;
    notifyListeners();
    try {
      final res =
          await serviceLocator.proService.getMyProvider(salonId: salonId);
      if (res.success && res.data != null) {
        _selectedSalonId = salonId;
        await _authService.setSelectedProviderSalon(salonId);
        _membership = res.data!.membership;
        await _authService.cacheProviderMembership(_membership);
        ProSalonScope.resetAll();
        return true;
      }
      // A per-salon denial (uniform 403) — likely revoked there since the
      // list loaded. Refresh the list; the session stays intact.
      await loadMySalons();
      return false;
    } catch (_) {
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// « Ajouter un salon » (R6): create the additional draft salon, refresh
  /// « Mes salons » and SWITCH to it (the caller then lands on onboarding).
  /// Null on failure — [error]/[errorCode] carry the gate
  /// (`reseau_required`/`salon_limit`) for the form.
  Future<SalonMembershipInfo?> addSalon({
    required String businessName,
    required BusinessType businessType,
    String? phoneNumber,
    String? address,
  }) async {
    if (_provider == null) return null;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      final res = await serviceLocator.proService.addSalon(
        businessName: businessName,
        businessType: businessType,
        phoneNumber: phoneNumber,
        address: address,
      );
      if (res.success && res.data != null) {
        await loadMySalons();
        await switchSalon(res.data!.salonId);
        return res.data;
      }
      _error = res.error ?? 'Création du salon impossible.';
      _errorCode = res.code;
      return null;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Drop the selection back to the default salon (used when the selected
  /// salon refuses the session mid-flight).
  Future<void> _clearSalonSelection() async {
    _selectedSalonId = null;
    try {
      await _authService.setSelectedProviderSalon(null);
    } catch (_) {/* best-effort */}
  }

  /// The salon the session acts in: the switched-to salon first (R6), then
  /// the owner's linked salon, else the membership's. Screens use THIS
  /// (never `provider.id` — an account id is not a salon id).
  String? get activeSalonId =>
      _selectedSalonId ?? _provider?.providerId ?? _membership?.salonId;

  String get salonName {
    final fromMembership = _membership?.salonName;
    if (fromMembership != null && fromMembership.isNotEmpty) {
      return fromMembership;
    }
    final business = _provider?.businessName;
    return (business == null || business.isEmpty) ? 'votre salon' : business;
  }

  /// Capability gate. Fallback without a membership (legacy session /
  /// offline first frame): a linked OWNER account stays owner-shaped; a bare
  /// member gets the minimal surface until the fetch lands.
  bool can(String capability) =>
      _membership?.can(capability) ?? (_provider?.providerId != null);

  bool _refreshingMembership = false;

  /// Fetch + cache the membership. On `not_a_member` (revoked — R4a) the
  /// session ends with the « accès retiré » notice. R6: a `forbidden` on a
  /// SELECTED salon is a per-salon denial — the selection silently falls
  /// back to the default salon, never a sign-out.
  Future<void> refreshMembership() async {
    if (_provider == null || _refreshingMembership) return;
    _refreshingMembership = true;
    try {
      var res = await serviceLocator.proService.getMyProvider();
      if (!res.success && res.code == 'forbidden' && _selectedSalonId != null) {
        await _clearSalonSelection();
        res = await serviceLocator.proService.getMyProvider();
      }
      if (res.success && res.data != null) {
        _membership = res.data!.membership;
        await _authService.cacheProviderMembership(_membership);
        notifyListeners();
      } else if (res.code == 'not_a_member') {
        await _signOutRevoked();
      }
      // Network/other failures: keep the cached shape — server still guards.
    } catch (_) {/* keep the cached shape */} finally {
      _refreshingMembership = false;
    }
  }

  bool _probing = false;

  /// The ProAccessGuard handler: a forbidden response somewhere probes the
  /// membership ONCE — an active member (capability miss) sees nothing; a
  /// revoked member is signed out gracefully (§5.3, no dead-end screens).
  Future<void> checkMembershipAlive() async {
    if (_provider == null || _probing) return;
    _probing = true;
    try {
      var res = await serviceLocator.proService.getMyProvider();
      if (!res.success && res.code == 'forbidden' && _selectedSalonId != null) {
        // R6: revoked from the SELECTED salon only — fall back to the
        // default salon and reshape; the session survives.
        await _clearSalonSelection();
        res = await serviceLocator.proService.getMyProvider();
        if (res.success && res.data != null) {
          ProSalonScope.resetAll();
          await loadMySalons();
        }
      }
      if (res.code == 'not_a_member') {
        await _signOutRevoked();
      } else if (res.success && res.data != null) {
        _membership = res.data!.membership;
        await _authService.cacheProviderMembership(_membership);
        notifyListeners();
      }
    } catch (_) {/* transient — the next action retries */} finally {
      _probing = false;
    }
  }

  String? _revokedNotice;

  /// One-shot: the revoked salon's name for the login banner.
  String? consumeRevokedNotice() {
    final notice = _revokedNotice;
    _revokedNotice = null;
    return notice;
  }

  Future<void> _signOutRevoked() async {
    _revokedNotice = salonName;
    _membership = null;
    await logout();
    ProRouter.router.go('/pro/login');
  }

  ProAuthProvider() {
    // The global 403 seam (access §5.3): forbidden responses anywhere in the
    // pro surfaces trigger ONE membership probe — revoked members sign out.
    ProAccessGuard.onForbidden = checkMembershipAlive;
    loadCurrentProvider();
  }

  Future<void> loadCurrentProvider() async {
    _isLoading = true;
    notifyListeners();

    try {
      _provider = await _authService.getCurrentProvider();
      _error = null;
      if (_provider != null) {
        // Instant shaping from the cached membership + the R6 selection,
        // then a live refresh (which also catches an offline revocation —
        // R4b — and validates the selection, falling back on a 403).
        _membership = await _authService.getCachedProviderMembership();
        _selectedSalonId = await _authService.getSelectedProviderSalon();
        _syncPush();
        await refreshMembership();
        unawaited(loadMySalons());
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendOtp(String phoneNumber) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.sendOtpToProvider(phoneNumber);
      if (response.success) {
        _error = null;
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de l\'envoi du code';
        return false;
      }
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String phoneNumber, String otp) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response =
          await _authService.verifyOtpForProvider(phoneNumber, otp);
      if (response.success && response.data != null) {
        _provider = response.data;
        _error = null;
        _syncPush();
        return true;
      } else {
        _error = response.error ?? 'Code OTP invalide';
        return false;
      }
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---- Pro auth overhaul (docs/design/pro-auth-social.md) -------------------

  /// devCode from the last email-OTP request (dev backends only).
  String? _emailDevCode;
  String? get emailDevCode => _emailDevCode;

  /// Machine code of the last auth failure (e.g. `provider_not_found` → the
  /// login screen offers « Créer un compte »).
  String? _errorCode;
  String? get errorCode => _errorCode;

  /// Shared login/registration handling — a signed-in provider comes back.
  /// A user-cancelled Google sheet fails silently.
  Future<bool> _login(Future<ApiResponse<ProviderUser>> Function() run) async {
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      final response = await run();
      if (response.success && response.data != null) {
        _provider = response.data;
        _syncPush();
        await refreshMembership();
        unawaited(loadMySalons());
        return true;
      }
      _errorCode = response.code;
      _error = _errorCode == 'cancelled'
          ? null
          : (response.error ?? 'Connexion impossible.');
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---- Team access R3: the login invitation bridge --------------------------

  /// Pending invitations surfaced by the last login attempt (the 202
  /// bridge) + the identity proof to accept/decline them. Memory only —
  /// never persisted (short-lived credential).
  List<TeamInvitation> _pendingInvitations = const [];
  InvitationProof? _invitationProof;

  List<TeamInvitation> get pendingInvitations => _pendingInvitations;
  bool get hasPendingInvitations => _pendingInvitations.isNotEmpty;

  /// Login handling for the three bridged sign-ins: signed in → true;
  /// invitations → false with [pendingInvitations] set (the screen shows
  /// the « Invitations » step); failure → false with error/errorCode.
  Future<bool> _bridgedLogin(
    Future<ProviderLoginResult> Function() run,
  ) async {
    _isLoading = true;
    _error = null;
    _errorCode = null;
    _pendingInvitations = const [];
    _invitationProof = null;
    notifyListeners();
    try {
      final result = await run();
      if (result.signedIn) {
        _provider = result.provider;
        _syncPush();
        await refreshMembership();
        unawaited(loadMySalons());
        return true;
      }
      if (result.hasInvitations) {
        _pendingInvitations = result.invitations;
        _invitationProof = result.proof;
        return false;
      }
      _errorCode = result.code;
      _error = _errorCode == 'cancelled'
          ? null
          : (result.error?.isNotEmpty ?? false
              ? result.error
              : 'Connexion impossible.');
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// « Rejoindre » from the login step — accepts under the retained proof;
  /// success = authenticated (the session was persisted service-side).
  Future<bool> acceptPendingInvitation(String invitationId) async {
    final proof = _invitationProof;
    if (proof == null) return false;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      final response =
          await _authService.acceptProviderInvitation(invitationId, proof);
      if (response.success && response.data != null) {
        _provider = response.data;
        _pendingInvitations = const [];
        _invitationProof = null;
        _syncPush();
        await refreshMembership();
        unawaited(loadMySalons());
        return true;
      }
      _error = response.error ?? 'Invitation impossible à accepter.';
      _errorCode = response.code;
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// « Refuser » from the login step — removes the card in place; an empty
  /// list falls back to today's « Créer un compte » messaging.
  Future<bool> declinePendingInvitation(String invitationId) async {
    final proof = _invitationProof;
    if (proof == null) return false;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      final response =
          await _authService.declineProviderInvitation(invitationId, proof);
      if (!response.success) {
        _error = response.error ?? 'Refus impossible.';
        _errorCode = response.code;
        return false;
      }
      _pendingInvitations = _pendingInvitations
          .where((i) => i.id != invitationId)
          .toList(growable: false);
      if (_pendingInvitations.isEmpty) {
        _invitationProof = null;
        _errorCode = 'provider_not_found';
        _error = 'Compte introuvable. Créez votre compte.';
      }
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Back/« Changer d'e-mail » from the invitations step.
  void clearPendingInvitations() {
    _pendingInvitations = const [];
    _invitationProof = null;
    _error = null;
    _errorCode = null;
    notifyListeners();
  }

  Future<bool> signInWithGoogle() =>
      _bridgedLogin(_authService.signInProviderWithGoogle);

  Future<bool> signInWithApple() =>
      _bridgedLogin(_authService.signInProviderWithApple);

  Future<bool> requestEmailOtp(String email) async {
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      final response = await _authService.requestProviderEmailOtp(email);
      if (response.success) {
        _emailDevCode =
            (response.data?.isNotEmpty ?? false) ? response.data : null;
        return true;
      }
      _error = response.error ?? 'Envoi du code impossible.';
      _errorCode = response.code;
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyEmailOtp(String email, String code) =>
      _bridgedLogin(() => _authService.verifyProviderEmailOtp(email, code));

  Future<bool> registerWithGoogle({
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  }) =>
      _login(() => _authService.registerProviderWithGoogle(
            phoneNumber: phoneNumber,
            businessName: businessName,
            businessType: businessType,
            address: address,
          ));

  Future<bool> registerWithEmail({
    required String email,
    required String code,
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  }) =>
      _login(() => _authService.registerProviderWithEmail(
            email: email,
            code: code,
            phoneNumber: phoneNumber,
            businessName: businessName,
            businessType: businessType,
            address: address,
          ));

  /// Best-effort: register this device under the provider session if push
  /// permission is already granted. Never throws into the auth flow.
  void _syncPush() {
    try {
      unawaited(serviceLocator.proPushRegistration.registerIfGranted());
    } catch (_) {/* best-effort */}
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Unregister this device first — the call needs the live provider session.
      try {
        await serviceLocator.proPushRegistration.unregister();
      } catch (_) {/* best-effort */}
      await _authService.logoutProvider();
      _provider = null;
      _membership = null;
      _selectedSalonId = null;
      _salons = const [];
      _canAddSalon = false;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
