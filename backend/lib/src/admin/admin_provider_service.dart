import '../access/membership_repository.dart';
import '../appointments/appointment_repository.dart';
import '../providers_repository.dart';
import '../site/site_rebuild_notifier.dart';
import '../subscription/salon_subscription_service.dart';
import '../validation/salon_validation_repository.dart';
import 'admin_kyc_service.dart' show AdminResult;
import 'audit_log_repository.dart';

/// Why « Lever la suspension » left a salon offline (B0.18 §3.4) — the
/// console words each one (§4.4).
abstract final class RestoreReasons {
  /// Never validated by MyWeli, or never taken live by its validation.
  static const notValidated = 'not_validated';

  /// No active owner — an erased account. Nobody could run the salon.
  static const noOwner = 'no_owner';

  /// No offer row, or one that is no longer live.
  static const offerNotLive = 'offer_not_live';

  /// Unpublished for non-payment (`unpublished_at` set).
  static const unpaid = 'unpaid';

  /// The salon was not live when it was suspended, or it was suspended
  /// before migration 0044 recorded what a suspension interrupts.
  static const unknownPrior = 'unknown_prior';
}

/// Admin provider management (design: docs/design/admin-console.md §12). List /
/// view providers, suspend/restore (hide from discovery + block new bookings),
/// and toggle featured placement — every mutation audited.
class AdminProviderService {
  AdminProviderService(
    this._providers,
    this._appointments,
    this._audit,
    this._subscriptions, {
    required SalonValidationRepository validations,
    required MembershipRepository members,
    SiteRebuildNotifier? rebuild,
  }) : _validations = validations,
       _members = members,
       _rebuild = rebuild ?? NoopSiteRebuildNotifier();

  final ProvidersRepository _providers;
  final AppointmentRepository _appointments;
  final AuditLogRepository _audit;
  final SalonSubscriptionService _subscriptions;

  /// B0.18 §3.4: restore returns a salon to `active` only when MyWeli
  /// validated it and it went live. Required: a forgotten wiring is a
  /// compile error, never a restore that publishes unvalidated salons.
  final SalonValidationRepository _validations;

  /// The active-owner check of the same rule.
  final MembershipRepository _members;

  /// Suspending or restoring changes the set `/sitemap/providers` lists, and
  /// the web prebuilds that set (`dynamicParams = false`). Without a rebuild a
  /// restored salon stays 404 until the next deploy.
  final SiteRebuildNotifier _rebuild;

  Future<AdminResult> list({
    String? status,
    String? q,
    int page = 1,
    int pageSize = 20,
  }) async {
    final r = await _providers.listForAdmin(
      status: status,
      q: q,
      page: page,
      pageSize: pageSize,
    );
    return (
      ok: true,
      error: null,
      data: {
        'items': r.items,
        'page': page,
        'pageSize': pageSize,
        'total': r.total,
      },
    );
  }

  /// Read-only support view: the provider + its recent bookings (no act-as).
  Future<AdminResult> detail(String id) async {
    final p = await _providers.byId(id);
    if (p == null) return (ok: false, error: 'not_found', data: null);
    final appts = await _appointments.listForProvider(id);
    return (
      ok: true,
      error: null,
      data: {...p, 'recentAppointments': appts.take(20).toList()},
    );
  }

  /// Suspend: hidden from discovery, new bookings refused (T17). The
  /// providers repository records what the suspension interrupted
  /// (`suspended_from`, B0.18 §3.4) — only when the salon was not suspended
  /// already: a second suspension keeps the first value.
  Future<AdminResult> suspend(String adminId, String id, Object? reason) async {
    final updated = await _providers.setStatus(id, 'suspended');
    if (updated == null) return (ok: false, error: 'not_found', data: null);
    // After the write, and awaited only so a test can observe it — it swallows
    // its own failures, so this can never turn a successful suspension into an
    // error for the operator.
    await _rebuild.requestRebuild('provider.suspend');
    await _audit.append((
      actorAdminId: adminId,
      action: 'provider.suspend',
      targetType: 'provider',
      targetId: id,
      reason: reason is String && reason.trim().isNotEmpty
          ? reason.trim()
          : null,
      metadata: const {},
    ));
    return (ok: true, error: null, data: updated);
  }

  /// « Lever la suspension » (B0.18 — docs/design/salon-go-live-approval.md
  /// §3.4). It used to write `active` over ANY salon, so suspend → restore,
  /// or a bare POST, published a never-validated draft, a salon unpublished
  /// for non-payment or an erased owner's salon.
  ///
  /// Now: `not_suspended` unless the salon is suspended. It lifts to `active`
  /// only when the suspension interrupted a live salon (`suspended_from`),
  /// MyWeli validated it and it went live, a live offer row exists, it is not
  /// unpublished for non-payment, and an active owner exists — otherwise to
  /// `draft`, with the first [RestoreReasons] that held it back. The lift is
  /// a compare-and-set from `suspended`. The rebuild fires only on `active`:
  /// a draft changes no public byte.
  ///
  /// Answers `{ status, reason }` (`reason` null when live).
  Future<AdminResult> restore(String adminId, String id) async {
    final current = await _providers.byId(id);
    if (current == null) return (ok: false, error: 'not_found', data: null);
    if (current['status'] != 'suspended') {
      return (ok: false, error: 'not_suspended', data: null);
    }
    final reason = await _whyNotLive(id);
    final to = reason == null ? 'active' : 'draft';
    final lifted = await _providers.liftSuspension(id, to: to);
    // Lifted by someone else between the read and the write.
    if (lifted == null) return (ok: false, error: 'not_suspended', data: null);
    if (to == 'active') await _rebuild.requestRebuild('provider.restore');
    await _audit.append((
      actorAdminId: adminId,
      action: 'provider.restore',
      targetType: 'provider',
      targetId: id,
      reason: null,
      metadata: {'status': to, 'reason': ?reason},
    ));
    return (ok: true, error: null, data: {'status': to, 'reason': reason});
  }

  /// Null when the salon may go back online; else the first reason it may
  /// not, in the order an admin can act on them.
  Future<String?> _whyNotLive(String id) async {
    final v = await _validations.get(id);
    if (v == null || v.state != ValidationStates.approved || !v.wentLive) {
      return RestoreReasons.notValidated;
    }
    final members = await _members.listForProvider(id);
    final hasOwner = members.any(
      (m) => m.role == 'owner' && m.status == 'active' && m.accountId != null,
    );
    if (!hasOwner) return RestoreReasons.noOwner;
    final offer = await _subscriptions.stateFor(id);
    if (!SalonSubscriptionService.isLiveState(offer)) {
      return RestoreReasons.offerNotLive;
    }
    if (offer!['unpublishedForBilling'] == true) return RestoreReasons.unpaid;
    if (await _providers.suspendedFrom(id) != 'active') {
      return RestoreReasons.unknownPrior;
    }
    return null;
  }

  Future<AdminResult> feature(
    String adminId,
    String id,
    Object? featured,
  ) async {
    if (featured is! bool) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final updated = await _providers.setFeatured(id, featured);
    if (updated == null) return (ok: false, error: 'not_found', data: null);
    await _audit.append((
      actorAdminId: adminId,
      action: 'provider.feature',
      targetType: 'provider',
      targetId: id,
      reason: null,
      metadata: {'featured': featured},
    ));
    return (ok: true, error: null, data: updated);
  }

  /// Manual billing (« Nous contacter », T54): record [months] months of
  /// payment for the salon; republishes a billing-unpublished salon when the
  /// publish gate passes and MyWeli validated it (B0.18 §3.4). Audited.
  Future<AdminResult> markSubscriptionPaid(
    String adminId,
    String id,
    Object? months, {
    Object? reason,
  }) async {
    if (months is! int || months < 1 || months > 24) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final r = await _subscriptions.markPaid(id, months: months);
    if (!r.ok) return (ok: false, error: r.error, data: null);
    await _audit.append((
      actorAdminId: adminId,
      action: 'subscription.paid',
      targetType: 'provider',
      targetId: id,
      reason: reason is String ? reason : null,
      metadata: {'months': months},
    ));
    return (ok: true, error: null, data: r.data);
  }
}
