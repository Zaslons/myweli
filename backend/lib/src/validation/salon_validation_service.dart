import '../access/membership_repository.dart';
import '../admin/admin_kyc_service.dart' show AdminResult;
import '../admin/audit_log_repository.dart';
import '../auth/provider_auth_repository.dart';
import '../providers_repository.dart';
import '../salon_provisioning_service.dart';
import '../site/site_rebuild_notifier.dart';
import '../subscription/salon_subscription_service.dart';
import 'salon_decision_notifier.dart';
import 'salon_validation_dto.dart';
import 'salon_validation_repository.dart';

/// MyWeli's side of « a salon goes public only once MyWeli validates it »
/// (B0.18, decision 120 — docs/design/salon-go-live-approval.md §3.2, §3.3,
/// §3.5): the admin's queue, the request's detail, and the two decisions.
/// Every route that reaches it lives under `/admin/*` (deny by default,
/// `role == admin`).
///
/// **Single winner, twice.** The decision is a compare-and-set on the state
/// the admin saw ([SalonValidationRepository.decide]), and the going-live is
/// another ([SalonValidationRepository.goLive]). A double click, two tabs, a
/// refuse racing a validate: one winner each time, and only the winner of the
/// going-live fires the rebuild and the salon's notice.
class SalonValidationService {
  SalonValidationService(
    this._validations,
    this._providers,
    this._subscriptions,
    this._members,
    this._accounts,
    this._audit, {
    required SalonDecisionNotifier notice,
    SiteRebuildNotifier? rebuild,
    DateTime Function()? clock,
  }) : _notice = notice,
       _rebuild = rebuild ?? NoopSiteRebuildNotifier(),
       _now = clock ?? (() => DateTime.now().toUtc());

  final SalonValidationRepository _validations;
  final ProvidersRepository _providers;
  final SalonSubscriptionService _subscriptions;
  final MembershipRepository _members;

  /// Read only, through [ProviderAuthRepository.accountsByIds].
  final ProviderAuthRepository _accounts;
  final AuditLogRepository _audit;
  final SalonDecisionNotifier _notice;

  /// The validation takes a salon public — it joins the set the web
  /// prebuilds (`dynamicParams = false`). Optional so test constructions
  /// compile; `site_rebuild_wiring_test.dart` pins the composition root.
  final SiteRebuildNotifier _rebuild;
  final DateTime Function() _now;

  /// The note's cap, in code points (§3.3) — the console counts the same way.
  static const maxNoteCodePoints = 500;

  static const _froms = {
    ValidationStates.pending,
    ValidationStates.refused,
    ValidationStates.approved,
  };

  static AdminResult _fail(String error, [Object? data]) =>
      (ok: false, error: error, data: data);

  /// Validate the salon (§3.2). [from] is the state the admin saw: `pending`,
  /// `refused` (correcting a refusal, from « Refusés »), or `approved` — the
  /// « Validation à terminer » button, which finishes a validation
  /// interrupted before it went live and skips the decision.
  ///
  /// Errors: `invalid_input` (400); `not_found` (404); 409s —
  /// `provider_suspended`, `incomplete` (+ `missing`, `offer` among them for
  /// an offer row that is no longer live), `validation_not_pending` (another
  /// decision won, or the salon already went live — answered before any
  /// write, the trial included), `no_owner`, `invalid_state` (the salon left
  /// `draft` between the hand-back and the going-live: an older image's
  /// publish racing it).
  ///
  /// A salon an older image left `active` is handed back to `draft` first
  /// ([SalonValidationRepository.handBack]); when a later step then fails,
  /// the prebuilt set shrinks (`salon.handed_back`, T68).
  Future<AdminResult> approve(
    String providerId, {
    required Object? from,
    required String adminId,
  }) async {
    if (from is! String || !_froms.contains(from)) {
      return _fail('invalid_input');
    }
    final provider = await _providers.byId(providerId);
    if (provider == null) return _fail('not_found');

    // 1. The checks, each a 409 with nothing written. They run before the
    // writes; the gate is Dart over several tables, so a window remains in
    // which the owner could edit — the decision stands on what the admin and
    // the checks saw.
    if (provider['status'] == 'suspended') return _fail('provider_suspended');
    final missing = SalonProvisioningService.publishGate(provider);
    final offer = await _subscriptions.stateFor(providerId);
    if (offer != null && !SalonSubscriptionService.isLiveState(offer)) {
      missing.add('offer');
    }
    if (missing.isNotEmpty) {
      return _fail('incomplete', {'missing': missing});
    }

    // 2. The decision — skipped when finishing one already taken.
    if (from == ValidationStates.approved) {
      // « Validation à terminer » finishes a validation interrupted before
      // it went live (§3.2), and nothing else. A salon that already went
      // live has nothing to finish, and says so HERE, before step 3: a 409
      // that minted a trial on its way would hand a salon validated long
      // ago a 90-day clock nobody granted — and the scheduler's notices
      // with it.
      final current = await _validations.get(providerId);
      if (current == null ||
          current.state != ValidationStates.approved ||
          current.wentLive) {
        return _fail('validation_not_pending');
      }
    } else {
      final decided = await _validations.decide(
        providerId,
        from: from,
        to: ValidationStates.approved,
        adminId: adminId,
        at: _now(),
      );
      // A refuse that landed first, a second click, a stale tab.
      if (decided == null) return _fail('validation_not_pending');
      // The winner alone is audited. No note travels here, ever.
      await _audit.append((
        actorAdminId: adminId,
        action: 'salon.approve',
        targetType: 'provider',
        targetId: providerId,
        reason: null,
        metadata: {'from': from},
      ));
    }

    // §9.3: an older image (a rollback) flipped this salon public without
    // the validation taking it live, and the admin validates it by hand. It
    // must end validated AND live, but the going-live (step 4) takes a
    // salon from `draft` — so it is handed back as a draft first: by the
    // decision's winner, or by the « finish » of a decision interrupted
    // before this point (else that finish could never complete: the
    // going-live would answer « not a draft » forever). [handBack] acts only
    // while the validation is approved and never went live, serialised with
    // the going-live, so a stale finish cannot hide a salon another call
    // just took live.
    final handedBack =
        provider['status'] == 'active' &&
        await _validations.handBack(providerId);
    if (!handedBack) return _takeLive(providerId);
    // Handed back, the salon left the public set. If a later step fails it
    // waits as any validation to finish does — unvalidated salons are not
    // public — and the prebuilt set must shrink with it (T68): the rebuild
    // that a success fires (`salon.approved`) will not come.
    try {
      final r = await _takeLive(providerId);
      if (!r.ok) await _rebuild.requestRebuild('salon.handed_back');
      return r;
    } catch (_) {
      await _rebuild.requestRebuild('salon.handed_back');
      rethrow;
    }
  }

  /// §3.2 steps 3–5, for a validation that is `approved` and never went
  /// live: the trial, the single-winner going-live, then — for its winner
  /// only — the rebuild and the salon's notice.
  Future<AdminResult> _takeLive(String providerId) async {
    // 3. The trial (§3.6): insert-if-absent with the tier derived NOW — a
    // salon that chose an offer on the website keeps its row and its clock
    // (T54) — then the liveness re-check on whichever row exists.
    final trial = await _subscriptions.startDefaultTrial(providerId);
    if (!SalonSubscriptionService.isLiveState(trial)) {
      // Validated but not live: « Validation à terminer » once the offer is
      // paid (« Marquer payé », then validate — the console says so).
      return _fail('incomplete', {
        'missing': ['offer'],
      });
    }

    // 4. Going live — all or nothing, and one winner.
    final outcome = await _validations.goLive(providerId, at: _now());
    switch (outcome) {
      case GoLiveOutcome.live:
        break;
      case GoLiveOutcome.alreadyLive:
      case GoLiveOutcome.notApproved:
        return _fail('validation_not_pending');
      case GoLiveOutcome.suspended:
        return _fail('provider_suspended');
      case GoLiveOutcome.noOwner:
        return _fail('no_owner');
      case GoLiveOutcome.notDraft:
        return _fail('invalid_state');
    }

    // The going-live is a `draft → public` transition, as the republish and
    // « Marquer payé » are, and clears the billing unpublish mark as they
    // do. A salon an older image published, which the scheduler then
    // unpublished for its lapsed offer, carries that mark; « Marquer payé »
    // leaves it (the salon was never validated), and kept, it would stop
    // the scheduler — which unpublishes only an unmarked row — from ever
    // taking this salon down again, and make a later restore read
    // « unpaid ».
    await _subscriptions.clearUnpublished(providerId);

    // 5. Only the winner of step 4 gets here: the rebuild, then the notice.
    // The rebuild swallows its own failures; the notice is best effort.
    await _rebuild.requestRebuild('salon.approved');
    await _notice.approved(
      providerId,
      trialEndsAt: trial['status'] == 'trial'
          ? DateTime.tryParse('${trial['trialEndsAt']}')
          : null,
    );
    final after = await _validations.get(providerId);
    return (
      ok: true,
      error: null,
      data: {
        'salonStatus': 'active',
        'validation': after == null ? null : salonValidationJson(after),
      },
    );
  }

  /// Refuse the request (§3.3): a compare-and-set from `pending` only.
  ///
  /// [code] from §4.3's closed list (`invalid_input`); [note] trimmed,
  /// required for `other` (`note_required`), at most [maxNoteCodePoints]
  /// code points (`note_too_long`) — all 400s, checked before anything is
  /// read. `validation_not_pending` (409) when another decision won.
  Future<AdminResult> refuse(
    String providerId, {
    required Object? code,
    required Object? note,
    required String adminId,
  }) async {
    if (code is! String || !kRefusalCodes.contains(code)) {
      return _fail('invalid_input');
    }
    if (note != null && note is! String) return _fail('invalid_input');
    final trimmed = (note as String?)?.trim() ?? '';
    if (code == 'other' && trimmed.isEmpty) return _fail('note_required');
    if (trimmed.runes.length > maxNoteCodePoints) {
      return _fail('note_too_long');
    }
    final cleanNote = trimmed.isEmpty ? null : trimmed;

    final provider = await _providers.byId(providerId);
    if (provider == null) return _fail('not_found');

    final decided = await _validations.decide(
      providerId,
      from: ValidationStates.pending,
      to: ValidationStates.refused,
      adminId: adminId,
      code: code,
      note: cleanNote,
      at: _now(),
    );
    if (decided == null) return _fail('validation_not_pending');
    // The audit log is append-only and outlives an erasure: the CODE only,
    // never the note (§2.2, §7).
    await _audit.append((
      actorAdminId: adminId,
      action: 'salon.refuse',
      targetType: 'provider',
      targetId: providerId,
      reason: null,
      metadata: {'code': code},
    ));
    // A refused salon is never public. `status` is `draft` already — unless
    // an older image (a rollback, §9.3) flipped it live directly: then back
    // to draft, conditionally, and the prebuilt set shrinks.
    if (provider['status'] == 'active') {
      final hidden = await _providers.compareAndSetStatus(
        providerId,
        from: 'active',
        to: 'draft',
      );
      if (hidden != null) await _rebuild.requestRebuild('salon.refused');
    }
    await _notice.refused(providerId, code: code, note: cleanNote);
    return (
      ok: true,
      error: null,
      data: {'validation': salonValidationJson(decided)},
    );
  }

  /// The admin queue (§3.5): one tab's page, `{ items, page, pageSize,
  /// total }`. `pending` is oldest first and leaves suspended salons out;
  /// each item carries the salon's name and place, the owner's contact and
  /// the number of KYC documents sent — hydrated by one bulk read each
  /// (salons, owners, accounts), so the round trips do not grow with the
  /// page size (no N+1).
  Future<AdminResult> queue({
    required Object? state,
    int page = 1,
    int pageSize = 50,
  }) async {
    if (state is! String || !ValidationStates.all.contains(state)) {
      return _fail('invalid_input');
    }
    final p = page < 1 ? 1 : page;
    final ps = pageSize.clamp(1, 100);
    final r = await _validations.queue(state, page: p, pageSize: ps);
    final ids = [for (final v in r.items) v.providerId];
    final salons = {
      for (final s in await _providers.byIds(ids)) s['id'] as String: s,
    };
    final owners = await _members.activeOwnersOf(ids);
    final accounts = await _accounts.accountsByIds([
      for (final m in owners.values) m.accountId!,
    ]);
    return (
      ok: true,
      error: null,
      data: {
        'items': [
          for (final v in r.items)
            _queueItem(
              v,
              salons[v.providerId],
              owners[v.providerId],
              accounts[owners[v.providerId]?.accountId],
            ),
        ],
        'page': p,
        'pageSize': ps,
        'total': r.total,
      },
    );
  }

  Map<String, dynamic> _queueItem(
    SalonValidation v,
    Map<String, dynamic>? salon,
    Member? owner,
    ProviderAccount? account,
  ) => {
    'providerId': v.providerId,
    'name': salon?['name'],
    'commune': salon?['commune'],
    'city': salon?['city'],
    'countryCode': salon?['countryCode'],
    'salonStatus': salon?['status'],
    'validation': salonValidationJson(v),
    'ownerContact': _contact(owner, account),
    'kycDocCount': account?.kycDocs.length ?? 0,
  };

  /// The owner's e-mail, or the phone when there is none (§3.5) — through
  /// [Member.emailOrNull], so a phone in the e-mail column reads as a phone.
  static String? _contact(Member? owner, ProviderAccount? account) =>
      owner?.emailOrNull ?? account?.phoneNumber ?? owner?.email;

  /// The request's detail (§3.5): the salon as the admin provider detail
  /// reads it (`byId` — without its recent bookings, which a decision does
  /// not need); the owner — account id, name, contact, account age, KYC
  /// status and document count, the other salons they own; the validation,
  /// with the admin who decided (the console only), and its history.
  Future<AdminResult> detail(String providerId) async {
    final salon = await _providers.byId(providerId);
    if (salon == null) return _fail('not_found');
    final v = await _validations.get(providerId);
    final events = await _validations.events(providerId);
    final owner = (await _members.activeOwnersOf([providerId]))[providerId];
    final account = owner == null
        ? null
        : (await _accounts.accountsByIds([owner.accountId!]))[owner.accountId];
    return (
      ok: true,
      error: null,
      data: {
        'salon': salon,
        'offer': await _subscriptions.stateFor(providerId),
        'owner': owner == null
            ? null
            : await _owner(providerId, owner, account),
        'validation': v == null
            ? null
            : {...salonValidationJson(v), 'decidedBy': v.decidedBy},
        'events': [
          for (final e in events)
            {
              'kind': e.kind,
              'at': e.at.toIso8601String(),
              'by': e.byAdmin,
              'refusalCode': e.refusalCode,
              'refusalNote': e.refusalNote,
            },
        ],
      },
    );
  }

  Future<Map<String, dynamic>> _owner(
    String providerId,
    Member owner,
    ProviderAccount? account,
  ) async {
    // Owned = the scalar link ∪ active owner rows — the set billing and the
    // directory gate on.
    final owned = <String>{
      if (account?.providerId != null) account!.providerId!,
      for (final m in await _members.listForAccount(owner.accountId!))
        if (m.role == 'owner' && m.status == 'active') m.providerId,
    }..remove(providerId);
    final others = owned.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _providers.byIds(owned.toList());
    final created = account?.createdAt;
    return {
      'accountId': owner.accountId,
      'name': account?.name,
      'businessName': account?.businessName,
      'email': owner.emailOrNull ?? account?.email,
      'phone': account?.phoneNumber,
      'contact': _contact(owner, account),
      'createdAt': created?.toIso8601String(),
      'accountAgeDays': created == null
          ? null
          : _now().difference(created).inDays,
      'kycStatus': account?.verificationStatus,
      'kycDocCount': account?.kycDocs.length ?? 0,
      'otherSalons': [
        for (final s in others)
          {'id': s['id'], 'name': s['name'], 'status': s['status']},
      ],
    };
  }
}
