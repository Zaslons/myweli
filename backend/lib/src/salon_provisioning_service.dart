import 'access/membership_repository.dart';
import 'auth/provider_auth_repository.dart';
import 'localities/localities_repository.dart';
import 'localities/localities_service.dart';
import 'providers_repository.dart';
import 'subscription/salon_subscription_service.dart';

/// Salon lifecycle (docs/design/pro-salon-lifecycle.md): every pro account
/// gets a DRAFT salon (created at registration, or healed on first read for
/// pre-fix accounts), publicly invisible until the owner publishes a
/// completed profile.
class SalonProvisioningService {
  SalonProvisioningService(
    this._providers,
    this._accounts,
    this._members, {
    SalonSubscriptionService? subscriptions,
  }) : _subscriptions = subscriptions;

  final ProvidersRepository _providers;
  final ProviderAuthRepository _accounts;
  final MembershipRepository _members;

  /// The offer gate (pricing pivot): publishing requires a live offer.
  /// Nullable only for legacy unit tests; production wiring always passes it.
  final SalonSubscriptionService? _subscriptions;

  /// The registration/add-salon business-type enum — ONE source of truth
  /// (register.dart + SalonDirectoryService.addSalon validate against it).
  static const Set<String> businessTypes = {
    'salon',
    'barber',
    'spa',
    'nailSalon',
    'massage',
    'other',
  };

  /// `businessType` → public listing category (the seed taxonomy).
  static String categoryFor(String businessType) => switch (businessType) {
    'barber' => 'barber',
    'spa' => 'spa',
    'nailSalon' => 'nails',
    'massage' => 'massage',
    _ => 'salon', // salon | other (à-domicile freelancers list as salons)
  };

  /// The ONE create+link path: returns the account with a salon attached —
  /// creating a draft from the account's business fields when missing.
  /// Idempotent; used by register AND the /me/provider self-heal. An
  /// optional resolved [market] (multi-pays MP1 — the route validated the
  /// `areaId` against the locality tree) stamps the salon's derived
  /// commune/city/timezone/currency at creation.
  Future<ProviderAccount> ensureSalon(
    ProviderAccount account, {
    SalonMarket? market,
  }) async {
    if (account.providerId != null) {
      // Module `access` R1: keep the membership table authoritative — the
      // linked owner gets its row even on the already-linked path.
      await _ensureOwnerRow(account, account.providerId!);
      return account;
    }
    final salon = await _providers.createSalon(
      name: account.businessName,
      category: categoryFor(account.businessType),
      phoneNumber: account.phoneNumber,
      address: account.address,
    );
    final id = salon['id'] as String;
    if (market != null) {
      await _providers.updateProfile(id, market.providerChanges);
    }
    await _accounts.linkProvider(account.id, id);
    account.providerId = id;
    await _ensureOwnerRow(account, id);
    return account;
  }

  Future<void> _ensureOwnerRow(ProviderAccount account, String salonId) =>
      _members.ensureOwner(
        providerId: salonId,
        accountId: account.id,
        email: account.email ?? account.phoneNumber,
      );

  /// The go-live gate (PRD FR-PRO-ONB-001 thresholds, server-authoritative).
  /// Empty list = publishable; otherwise the missing checklist keys.
  static List<String> publishGate(Map<String, dynamic> provider) {
    final missing = <String>[];
    final description = (provider['description'] as String?)?.trim() ?? '';
    final address = (provider['address'] as String?)?.trim() ?? '';
    final commune = (provider['commune'] as String?)?.trim() ?? '';
    // Multi-pays MP1: the commune must be a VALID locality (an areaId, or a
    // name that resolves to one — publish() self-heals the match first); a
    // free-text miss stays under the existing `profile` checklist key.
    final validArea =
        provider['areaId'] != null ||
        (commune.isNotEmpty && seedAreaForCommuneName(commune) != null);
    if (description.isEmpty ||
        address.isEmpty ||
        commune.isEmpty ||
        !validArea) {
      missing.add('profile');
    }
    // The map pin (L1) — no coordinates, no listing on the discovery map.
    if (provider['latitude'] == null || provider['longitude'] == null) {
      missing.add('location');
    }
    final services = ((provider['services'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((s) => s['active'] != false)
        .length;
    if (services < 3) missing.add('services');
    final photos = ((provider['imageUrls'] as List?) ?? const []).length;
    if (photos < 3) missing.add('photos');
    final schedule =
        ((provider['availability'] as Map?)?['weeklySchedule'] as Map?) ??
        const {};
    final openDays = schedule.values.any(
      (day) => day is List && day.isNotEmpty,
    );
    if (!openDays) missing.add('availability');
    return missing;
  }

  /// Publish [providerId]: flips `draft` → `active` when the gate passes.
  /// `{ok: true}` also for an already-active salon (idempotent).
  Future<({bool ok, String? error, Object? data})> publish(
    String providerId,
  ) async {
    var provider = await _providers.byId(providerId);
    if (provider == null) {
      return (ok: false, error: 'not_found', data: null);
    }
    // Multi-pays MP1 self-heal: a legacy commune display name that matches a
    // seeded area gets its market facts stamped before gating.
    if (provider['areaId'] == null) {
      final commune = (provider['commune'] as String?)?.trim() ?? '';
      final area = commune.isEmpty ? null : seedAreaForCommuneName(commune);
      if (area != null) {
        provider =
            await _providers.updateProfile(
              providerId,
              marketChangesForArea(area),
            ) ??
            provider;
      }
    }
    final missing = publishGate(provider);
    // The pricing pivot: going live requires a live offer (trial/paid/grace)
    // — the `offer` key sends the clients to « Choisissez une offre ».
    final subs = _subscriptions;
    if (subs != null && !await subs.hasLiveOffer(providerId)) {
      missing.add('offer');
    }
    if (missing.isNotEmpty) {
      return (ok: false, error: 'incomplete', data: {'missing': missing});
    }
    if ((provider['status'] ?? 'active') == 'active') {
      return (ok: true, error: null, data: provider);
    }
    final updated = await _providers.setStatus(providerId, 'active');
    return (ok: true, error: null, data: updated);
  }
}
