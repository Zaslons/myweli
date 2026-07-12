import '../auth/provider_auth_repository.dart';
import '../providers_repository.dart';
import '../salon_provisioning_service.dart';
import '../subscription/salon_subscription_service.dart';
import 'membership_repository.dart';
import 'membership_service.dart';

typedef DirectoryResult = ({bool ok, String? error, Object? data});

/// Module `access` R6 — the « Mes salons » directory: every salon the
/// account holds an ACTIVE membership in (owned + member), and the
/// server-computed « Ajouter un salon » gate (clients never derive rights).
/// Design: docs/design/team-access-r6-multi-salons.md.
class SalonDirectoryService {
  SalonDirectoryService(
    this._members,
    this._memberService,
    this._providers,
    this._subscriptions,
    this._accounts,
  );

  final MembershipRepository _members;
  final MembershipService _memberService;
  final ProvidersRepository _providers;
  final SalonSubscriptionService _subscriptions;
  final ProviderAuthRepository _accounts;

  /// Anti-abuse bound on « Ajouter un salon » (threat T55): no legitimate
  /// pre-launch network needs more; raise deliberately when one does.
  static const int maxOwnedSalons = 20;

  /// The picker payload: ACTIVE memberships joined with the salon rows,
  /// owned first then salonName (case-insensitive). Revoked and pending
  /// invitations are excluded (invitations have their own surface).
  Future<List<Map<String, dynamic>>> listForAccount(String accountId) async {
    // Self-heal first: a legacy linked owner without a membership row yet
    // must still see its salon in the list (mirrors memberOf's heal).
    final account = await _accounts.accountById(accountId);
    if (account?.providerId != null) {
      await _memberService.memberOf(accountId, account!.providerId!);
    }
    final rows = await _members.listForAccount(accountId);
    final entries = <Map<String, dynamic>>[];
    for (final m in rows) {
      if (m.status != 'active') continue;
      final salon = await _providers.byId(m.providerId);
      if (salon == null) continue;
      entries.add({
        'salonId': m.providerId,
        'salonName': (salon['name'] as String?) ?? '',
        'role': m.role,
        'salonStatus': (salon['status'] as String?) ?? 'active',
        'verified': salon['verified'] == true,
        'imageUrl': _thumbOf(salon),
      });
    }
    entries.sort((a, b) {
      final aOwner = a['role'] == 'owner' ? 0 : 1;
      final bOwner = b['role'] == 'owner' ? 0 : 1;
      if (aOwner != bOwner) return aOwner - bOwner;
      final byName = (a['salonName'] as String).toLowerCase().compareTo(
        (b['salonName'] as String).toLowerCase(),
      );
      if (byName != 0) return byName;
      return (a['salonId'] as String).compareTo(b['salonId'] as String);
    });
    return entries;
  }

  /// The « Ajouter un salon » gate (user decision 2026-07-12): the account
  /// OWNS ≥1 salon with a LIVE (trial/paid/grace) Réseau offer, under the
  /// abuse cap.
  Future<bool> canAddSalon(String accountId) async {
    final owned = await _ownedSalonIds(accountId);
    if (owned.isEmpty || owned.length >= maxOwnedSalons) return false;
    for (final id in owned) {
      final state = await _subscriptions.stateFor(id);
      if (state == null) continue;
      final status = state['status'] as String;
      final live = status == 'trial' || status == 'paid' || status == 'grace';
      if (live && state['tier'] == 'reseau') return true;
    }
    return false;
  }

  /// « Ajouter un salon » (R6): create an ADDITIONAL draft salon under the
  /// caller's account. Never touches `account.providerId` (the scalar stays
  /// the default salon); no subscription row (fresh SETUP — its own offer,
  /// its own trial, its own publish gate). The verified badge is inherited
  /// from the account's KYC (T52).
  Future<DirectoryResult> addSalon(
    String accountId, {
    required Object? businessName,
    required Object? businessType,
    Object? phoneNumber,
    Object? address,
  }) async {
    final account = await _accounts.accountById(accountId);
    if (account == null) return (ok: false, error: 'forbidden', data: null);

    final name = businessName is String ? businessName.trim() : '';
    final type = businessType is String ? businessType : '';
    if (name.isEmpty ||
        !SalonProvisioningService.businessTypes.contains(type)) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final phone = phoneNumber is String && phoneNumber.trim().isNotEmpty
        ? phoneNumber.trim()
        : account.phoneNumber;
    final where = address is String && address.trim().isNotEmpty
        ? address.trim()
        : null;

    // Gate order: the Réseau requirement reads before the cap so a capped
    // Réseau fleet still gets the accurate code.
    final owned = await _ownedSalonIds(accountId);
    var reseau = false;
    for (final id in owned) {
      final state = await _subscriptions.stateFor(id);
      if (state == null) continue;
      final status = state['status'] as String;
      final live = status == 'trial' || status == 'paid' || status == 'grace';
      if (live && state['tier'] == 'reseau') {
        reseau = true;
        break;
      }
    }
    if (!reseau) return (ok: false, error: 'reseau_required', data: null);
    if (owned.length >= maxOwnedSalons) {
      return (ok: false, error: 'salon_limit', data: null);
    }

    final salon = await _providers.createSalon(
      name: name,
      category: SalonProvisioningService.categoryFor(type),
      phoneNumber: phone,
      address: where,
    );
    final id = salon['id'] as String;
    await _members.ensureOwner(
      providerId: id,
      accountId: accountId,
      email: account.email ?? account.phoneNumber,
    );
    // Badge inheritance (T52): the account's KYC approval covers every salon
    // it owns — including ones created after the approval.
    if (account.verificationStatus == 'verified') {
      await _providers.updateProfile(id, {'verified': true});
    }
    return (
      ok: true,
      error: null,
      data: {
        'salonId': id,
        'salonName': name,
        'role': 'owner',
        'salonStatus': 'draft',
        'verified': account.verificationStatus == 'verified',
        'imageUrl': null,
      },
    );
  }

  /// Salons the account OWNS: the scalar link ∪ active owner rows (the
  /// membership table is authoritative; the scalar is the legacy default).
  Future<Set<String>> _ownedSalonIds(String accountId) async {
    final owned = <String>{};
    final account = await _accounts.accountById(accountId);
    if (account?.providerId != null) owned.add(account!.providerId!);
    for (final m in await _members.listForAccount(accountId)) {
      if (m.role == 'owner' && m.status == 'active') owned.add(m.providerId);
    }
    return owned;
  }

  String? _thumbOf(Map<String, dynamic> salon) {
    final logo = salon['logoUrl'];
    if (logo is String && logo.isNotEmpty) return logo;
    final images = salon['imageUrls'];
    if (images is List && images.isNotEmpty && images.first is String) {
      return images.first as String;
    }
    return null;
  }
}
