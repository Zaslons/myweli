import 'package:http/http.dart' as http;

import 'access/membership_repository.dart';
import 'appointments/appointment_repository.dart';
import 'auth/provider_auth_repository.dart';
import 'notifications/notifications_repository.dart';
import 'providers_repository.dart';
import 'push/device_token_repository.dart';
import 'site/site_rebuild_notifier.dart';
import 'storage/storage_service.dart';

/// Provider ACCOUNT lifecycle (audit 11.5 — threat T53): the deletion flow
/// that the `/me/provider` route delegates to. Orchestrates the
/// future-bookings gate, the salon unpublish, the KYC storage erasure and
/// the identity delete. Design: docs/design/pro-account-deletion-export.md.
class ProviderAccountService {
  ProviderAccountService(
    this._auth,
    this._providers,
    this._appointments,
    this._storage,
    this._memberships, {
    DeviceTokenRepository? devices,
    NotificationsRepository? notifications,
    http.Client? client,
    SiteRebuildNotifier? rebuild,
  }) : _devices = devices,
       _notifications = notifications,
       _client = client ?? http.Client(),
       _rebuild = rebuild ?? NoopSiteRebuildNotifier();

  final ProviderAuthRepository _auth;
  final ProvidersRepository _providers;
  final AppointmentRepository _appointments;
  final StorageService _storage;
  final MembershipRepository _memberships;

  /// L1/T59: optional so the existing constructions in tests keep compiling —
  /// but wired in `dependencies.dart`, so production always has them.
  final DeviceTokenRepository? _devices;
  final NotificationsRepository? _notifications;
  final http.Client _client;
  final SiteRebuildNotifier _rebuild;

  /// Delete the account behind [accountId]. Error codes: `forbidden`
  /// (unknown account), `future_bookings` (settle the agenda first).
  Future<({bool ok, String? error})> deleteAccount(String accountId) async {
    final account = await _auth.accountById(accountId);
    if (account == null) return (ok: false, error: 'forbidden');

    // R6 (T53): every salon the account OWNS — the scalar link plus active
    // owner membership rows. Member-only salons are never touched.
    final owned = <String>{
      if (account.providerId != null) account.providerId!,
      for (final m in await _memberships.listForAccount(accountId))
        if (m.role == 'owner' && m.status == 'active') m.providerId,
    };
    // Every owned salon settles its agenda first — no surprise
    // mass-cancellations anywhere in the fleet.
    final now = DateTime.now().toUtc();
    for (final providerId in owned) {
      final open = await _appointments.listForProvider(providerId);
      final hasFuture = open.any((a) {
        final status = a['status'] as String?;
        if (status != 'pending' && status != 'confirmed') return false;
        final date = DateTime.tryParse(a['appointmentDate'] as String? ?? '');
        return date != null && date.isAfter(now);
      });
      if (hasFuture) return (ok: false, error: 'future_bookings');
    }
    // Unpublish, don't destroy: T51 hides drafts everywhere while bookings,
    // reviews and the CRM keep resolving (business history ≠ identity).
    //
    // The prior status is read per salon because the fire below must be
    // GUARDED: an owner whose salons were all draft (or suspended) changes
    // nothing in the prebuilt slug set, and an unguarded fire would recreate
    // the build-nothing-but-burn-the-cooldown defect this slice removed from
    // salon creation.
    var anyWasActive = false;
    for (final providerId in owned) {
      final before = await _providers.byId(providerId);
      if (before?['status'] == 'active') anyWasActive = true;
      await _providers.setStatus(providerId, 'draft');
    }
    // Once for the whole account, after the loop — one erasure, one build.
    if (anyWasActive) {
      await _rebuild.requestRebuild('account.erased');
    }

    // Erase the KYC objects from the private bucket (T53 — « définitive »
    // means the documents too). Own-prefix keys only (defense in depth); a
    // storage hiccup never blocks the account erasure — the rows go next,
    // making any survivor unreachable.
    for (final doc in account.kycDocs) {
      final key = doc['key'] as String?;
      if (key == null || !key.startsWith('kyc/$accountId/')) continue;
      try {
        final url = _storage.presignDelete(key: key, bucket: StorageBucket.kyc);
        await _client.delete(Uri.parse(url));
      } catch (_) {
        // Tolerated: uuid-named + private + rows deleted ⇒ unreachable.
      }
    }

    // L1/T59: the SAME defect the consumer side had. This flow settled the
    // agenda, unpublished the salons and erased the KYC documents, and never
    // touched either of these — so a deleted salon owner's phone kept ringing.
    // Before the identity delete, like everything else here.
    await _devices?.deleteForUser(accountId);
    await _notifications?.deleteForUser(accountId);

    // Module `access` (drift §2.3-2): the identity's memberships die with it
    // — a member row must never outlive its account.
    await _memberships.revokeAllForAccount(accountId);

    final ok = await _auth.deleteAccount(accountId);
    return ok ? (ok: true, error: null) : (ok: false, error: 'forbidden');
  }
}
