import 'access/membership_repository.dart';
import 'admin/admin_notifier.dart';
import 'auth/demo_seam.dart';
import 'auth/provider_auth_repository.dart';
import 'localities/localities_repository.dart';
import 'localities/localities_service.dart';
import 'providers_repository.dart';
import 'site/site_rebuild_notifier.dart';
import 'subscription/salon_subscription_service.dart';
import 'validation/salon_validation_dto.dart';
import 'validation/salon_validation_repository.dart';
import 'validation/salon_validation_view.dart';

/// What [SalonProvisioningService.publish] — the owner's request to go live
/// (B0.18, docs/design/salon-go-live-approval.md §3.1) — answered:
///
/// - `ok` and not [accepted]: **200**, [data] is the salon, live — it was
///   already, or a validated salon came back online (the republish);
/// - `ok` and [accepted]: **202**, [data] is `{ validation }` — the request
///   is recorded (or was already), the admin decides;
/// - not `ok`: [error] — `not_found` (404), `demo_account_locked` and
///   `provider_suspended` (403), `incomplete` with `missing` in [data] and
///   `validation_refused_final` (409).
typedef SubmitResult = ({bool ok, bool accepted, String? error, Object? data});

/// Salon lifecycle (docs/design/pro-salon-lifecycle.md): every pro account
/// gets a DRAFT salon (created at registration, or healed on first read for
/// pre-fix accounts), publicly invisible until the owner asks to go live
/// with a completed profile AND MyWeli validates it (B0.18 —
/// docs/design/salon-go-live-approval.md).
class SalonProvisioningService {
  SalonProvisioningService(
    this._providers,
    this._accounts,
    this._members, {
    SalonSubscriptionService? subscriptions,
    SiteRebuildNotifier? rebuild,
    SalonValidationRepository? validations,
    AdminNotifier? adminNotifier,
    DateTime Function()? clock,
    void Function(String)? log,
  }) : _subscriptions = subscriptions,
       _rebuild = rebuild ?? NoopSiteRebuildNotifier(),
       _validations = validations,
       _adminNotifier = adminNotifier,
       _now = clock ?? (() => DateTime.now().toUtc()),
       _log = log ?? print;

  final ProvidersRepository _providers;
  final ProviderAuthRepository _accounts;
  final MembershipRepository _members;

  /// The offer gate (pricing pivot): a request is refused for an offer row
  /// that exists and is no longer live; the trial itself starts at the
  /// validation now (B0.18 §3.6). Nullable only for legacy unit tests;
  /// production wiring always passes it.
  final SalonSubscriptionService? _subscriptions;

  /// A validated salon coming back online (the republish, §3.1) rejoins the
  /// set the web prebuilds (`dynamicParams = false`); without a rebuild its
  /// public page 404s until the next deploy.
  final SiteRebuildNotifier _rebuild;

  /// B0.18: the validation beside `status`. Optional so the constructions
  /// that only provision keep compiling; [publish] refuses to run without it
  /// (a [StateError]) rather than fall back to the old direct flip — and
  /// `salon_validation_wiring_test.dart` fails if `dependencies.dart` omits
  /// it.
  final SalonValidationRepository? _validations;

  /// The admin's e-mail on each NEW request (§5.1). Absent: nobody is told.
  final AdminNotifier? _adminNotifier;

  final DateTime Function() _now;

  /// Structured stdout (Cloud Logging reads it) — a refusal is said.
  final void Function(String) _log;

  /// Upper bound on a salon's display name — the same two call sites as
  /// [businessTypes], and for the same reason: one source of truth.
  ///
  /// **It had none, and that was reachable from the outside.** `businessName`
  /// is interpolated into every booking push sent to that salon's clients
  /// (`BookingNotifier` → `renderTemplate` → `PushService`), and FCM rejects a
  /// `messages:send` payload over ~4096 bytes. A salon owner could therefore
  /// make every push to their clients fail — which, before the provider learned
  /// to tell a payload rejection from a dead device, deleted those clients'
  /// push tokens.
  ///
  /// 120 is generous for a real business name and far below anything that could
  /// pressure a notification payload. The provider caps independently
  /// (`FcmV1PushProvider.maxBodyChars`); this is the boundary check, that is the
  /// belt.
  static const int maxBusinessNameChars = 120;

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
      final salonId = account.providerId!;
      // T72 in depth (docs/design/backend-integrity-batch6.md §2.8, B6.8b):
      // never an owner row on a salon ANOTHER account owns. The route no
      // longer lets a client choose the link, so nothing reaches this today;
      // if anything ever does, it is refused and said.
      final members = await _members.listForProvider(salonId);
      if (members.any(
        (m) =>
            m.role == MemberRoleNames.owner &&
            m.status == 'active' &&
            m.accountId != account.id,
      )) {
        _log(
          'ensure_salon REFUSED provider=$salonId account=${account.id} '
          'cause=owned_by_another',
        );
        return account;
      }
      // Module `access` R1: keep the membership table authoritative — the
      // linked owner gets its row even on the already-linked path.
      await _ensureOwnerRow(account, salonId);
      return account;
    }
    final salon = await _providers.createSalon(
      name: account.businessName,
      category: categoryFor(account.businessType),
      phoneNumber: account.phoneNumber,
      address: account.address,
    );
    final id = salon['id'] as String;
    // No rebuild here, deliberately: the salon is created 'draft', and the
    // prebuilt slug set excludes drafts — a build now would change zero bytes
    // while consuming the notifier's cooldown window. The set grows at the
    // validation (`SalonValidationService.approve`) and at a validated
    // salon's republish (publish below), which is where the fires live.
    if (market != null) {
      await _providers.updateProfile(id, market.providerChanges);
    }
    await _accounts.linkProvider(account.id, id);
    account.providerId = id;
    await _ensureOwnerRow(account, id);
    return account;
  }

  /// Whether [providerId]'s OWNER membership is the demo identity — the
  /// membership rows carry the email (`_ensureOwnerRow` writes it), so no
  /// account read is needed.
  Future<bool> _ownedByDemoAccount(String providerId) async {
    final members = await _members.listForProvider(providerId);
    return members.any((m) => m.role == 'owner' && isDemoIdentity(m.email));
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

  /// The owner asks to go live (B0.18, docs/design/salon-go-live-approval.md
  /// §3.1). The route and its name stay (`POST /providers/{id}/publish`,
  /// `salon.publish`); what changed is what it does — it no longer flips the
  /// salon public, MyWeli's validation does (`SalonValidationService`). In
  /// order:
  ///
  /// 1. **the demo lock**, first and unchanged — the demo salon can never be
  ///    pending, so the validation needs no lock of its own;
  /// 2. **`suspended`** → `provider_suspended`, unchanged;
  /// 3. **the area self-heal, then a re-read**: Postgres `updateProfile`
  ///    returns the raw blob, whose `services` and `weeklySchedule` are
  ///    stale, so gating it answered a false `incomplete` on a first try;
  /// 4. **the go-live gate**, with `offer` only for a row that exists and is
  ///    no longer live;
  /// 5. **the branch on the validation** — see [SubmitResult]. No trial is
  ///    started here any more, and nothing is rebuilt on a 202.
  Future<SubmitResult> publish(String providerId) async {
    var provider = await _providers.byId(providerId);
    if (provider == null) {
      return (ok: false, accepted: false, error: 'not_found', data: null);
    }
    // The demo review account (T69) may never publish: its credential is
    // PUBLIC (printed in both stores' review notes), so its salon must never
    // enter the public slug set, discovery, the sitemap — or the admin's
    // queue. Keyed on the owner-membership email against the compile-time
    // demo constant: in the service, not the route, so no future caller can
    // route around it.
    if (await _ownedByDemoAccount(providerId)) {
      return (
        ok: false,
        accepted: false,
        error: 'demo_account_locked',
        data: null,
      );
    }
    // An admin suspension (T17) is lifted only by the audited admin restore.
    // A suspended salon asks for nothing and writes nothing here.
    // Design: docs/design/pro-companion-path.md §3.1.
    if (provider['status'] == 'suspended') {
      return (
        ok: false,
        accepted: false,
        error: 'provider_suspended',
        data: null,
      );
    }
    final validations = _validations;
    if (validations == null) {
      // Never the old direct flip: without the validation record there is
      // no request to record, and going live is the admin's to decide.
      throw StateError('publish needs the salon validation repository');
    }
    // Multi-pays MP1 self-heal: a legacy commune display name that matches a
    // seeded area gets its market facts stamped before gating — then the
    // salon is READ AGAIN, never gated on what `updateProfile` returned.
    if (provider['areaId'] == null) {
      final commune = (provider['commune'] as String?)?.trim() ?? '';
      final area = commune.isEmpty ? null : seedAreaForCommuneName(commune);
      if (area != null) {
        await _providers.updateProfile(providerId, marketChangesForArea(area));
        provider = await _providers.byId(providerId) ?? provider;
      }
    }
    final missing = publishGate(provider);
    // The pricing pivot: going live requires a live offer (trial/paid/grace).
    // A salon with NO offer row is not refused for it — its trial starts at
    // the validation (§3.6), and the Pro app may not send it anywhere to
    // choose (App Store 3.1.3(f)). Only a row that exists and is no longer
    // live yields `offer`: one trial per salon, the `trial_used` rule.
    final subs = _subscriptions;
    if (subs != null) {
      final state = await subs.stateFor(providerId);
      if (state != null && !SalonSubscriptionService.isLiveState(state)) {
        missing.add('offer');
      }
    }
    if (missing.isNotEmpty) return _incomplete(missing);

    if ((provider['status'] ?? 'active') == 'active') {
      // Already live: idempotent, nothing to ask.
      return (ok: true, accepted: false, error: null, data: provider);
    }
    final current = await validations.get(providerId);
    if (current != null && current.state == ValidationStates.approved) {
      return _approvedAnswer(providerId, current);
    }
    if (current != null && current.isFinalRefusal) return _refusedFinal;
    if (current != null && current.state == ValidationStates.pending) {
      // Already asked: no new event, no second e-mail to the admin.
      return _accepted(current);
    }
    // Never asked, or refused for a reason the salon could fix: a request —
    // from the state just read, so a request still in flight when the admin
    // decides (a double tap, a slow retry) can never reopen that decision.
    final outcome = await validations.submit(providerId, _now(), seen: current);
    final v = outcome.validation;
    if (outcome.recorded && v != null) {
      // Only a row that came back is a NEW request (a double tap records
      // once), and only a new request reaches the admin's inbox. Best effort
      // inside the notifier: a failed send never fails the request.
      await _adminNotifier?.newSalonRequest(
        providerId: providerId,
        salonName: (provider['name'] as String?) ?? providerId,
        commune: provider['commune'] as String?,
        city: provider['city'] as String?,
        countryCode: provider['countryCode'] as String?,
      );
      return _accepted(v);
    }
    // Nothing recorded: the admin decided at that very moment. The answer
    // follows the validation as it really is now.
    if (v == null) {
      // The row went in between (the owner's account was erased): nothing
      // is pending, and nothing was asked.
      return (
        ok: true,
        accepted: true,
        error: null,
        data: {'validation': null},
      );
    }
    if (v.state == ValidationStates.approved) {
      return _approvedAnswer(providerId, v);
    }
    if (v.isFinalRefusal) return _refusedFinal;
    // Pending — or refused a moment ago: the request the owner sent was the
    // one just decided, and a new one would erase a decision they have not
    // read yet. The body carries the real state.
    return _accepted(v);
  }

  /// A validated salon (§3.1's first three rows of the table).
  Future<SubmitResult> _approvedAnswer(
    String providerId,
    SalonValidation v,
  ) async {
    if (!v.wentLive) {
      // The admin's validation is finishing (§3.2): it takes the salon live
      // itself. Nothing to do here, and nothing public yet.
      return _accepted(v);
    }
    // Validated and went live once — back to `draft` since (an unpaid offer,
    // a lifted suspension). Read the salon as it is NOW.
    final provider = await _providers.byId(providerId);
    if (provider == null) {
      return (ok: false, accepted: false, error: 'not_found', data: null);
    }
    final status = (provider['status'] as String?) ?? 'active';
    if (status == 'active') {
      return (ok: true, accepted: false, error: null, data: provider);
    }
    if (status == 'suspended') {
      return (
        ok: false,
        accepted: false,
        error: 'provider_suspended',
        data: null,
      );
    }
    final subs = _subscriptions;
    if (subs != null && !await subs.hasLiveOffer(providerId)) {
      // No live offer row: the billing pointer, never a second trial.
      return _incomplete(['offer']);
    }
    // The republish: a compare-and-set from `draft`, so a suspension that
    // lands meanwhile holds.
    final republished = await _providers.compareAndSetStatus(
      providerId,
      from: 'draft',
      to: 'active',
    );
    if (republished == null) {
      // Another writer got there first — answer from what it did.
      final now = await _providers.byId(providerId);
      if (now?['status'] == 'active') {
        return (ok: true, accepted: false, error: null, data: now);
      }
      return (
        ok: false,
        accepted: false,
        error: 'provider_suspended',
        data: null,
      );
    }
    // As « Marquer payé » does: the scheduler can unpublish it again when
    // its offer next lapses.
    await subs?.clearUnpublished(providerId);
    // The listable set just grew, and the web prebuilds it (`dynamicParams =
    // false`): without this fire the salon's public page 404s until an
    // unrelated deploy. After the write, and only for it — a 202 changes no
    // public byte and must not consume the cooldown window. The reason is
    // markPaid's: the same transition (T68).
    await _rebuild.requestRebuild('salon.republished');
    return (ok: true, accepted: false, error: null, data: republished);
  }

  static SubmitResult _accepted(SalonValidation v) => (
    ok: true,
    accepted: true,
    error: null,
    data: {'validation': salonValidationJson(v)},
  );

  static SubmitResult _incomplete(List<String> missing) => (
    ok: false,
    accepted: false,
    error: 'incomplete',
    data: {'missing': missing},
  );

  static const SubmitResult _refusedFinal = (
    ok: false,
    accepted: false,
    error: 'validation_refused_final',
    data: null,
  );

  /// The `validation` `GET /me/provider` carries for [providerId] (§3.5),
  /// or null when the salon never asked — or when this construction has no
  /// validation record (legacy tests; `salon_validation_wiring_test.dart`
  /// pins the composition root). [salonStatus] is the salon's status as the
  /// caller just read it: `offerLive` is said only for a validated salon
  /// that is not live.
  Future<Map<String, dynamic>?> validationFor(
    String providerId, {
    required String? salonStatus,
  }) async {
    final validations = _validations;
    if (validations == null) return null;
    final views = await salonValidationViews(validations, _subscriptions, {
      providerId: salonStatus,
    });
    return views[providerId];
  }
}
