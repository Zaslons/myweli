import 'package:http/http.dart' as http;

import 'access/membership_repository.dart';
import 'appointments/appointment_repository.dart';
import 'auth/apple_tokens.dart';
import 'auth/demo_seam.dart';
import 'auth/provider_auth_repository.dart';
import 'idempotency/idempotency_store.dart';
import 'notifications/notifications_repository.dart';
import 'providers_repository.dart';
import 'push/device_token_repository.dart';
import 'site/site_rebuild_notifier.dart';
import 'storage/storage_service.dart';

/// Provider ACCOUNT lifecycle (audit 11.5 — threat T53): the deletion flow
/// that the `/me/provider` route delegates to. Orchestrates the demo lock
/// (T69), the future-bookings gate, the salon unpublish, the KYC storage
/// erasure and the identity delete. Design:
/// docs/design/pro-account-deletion-export.md; the demo lock:
/// docs/design/demo-account-deletion-lock.md.
class ProviderAccountService {
  ProviderAccountService(
    this._auth,
    this._providers,
    this._appointments,
    this._storage,
    this._memberships, {
    DeviceTokenRepository? devices,
    NotificationsRepository? notifications,
    IdempotencyStore? idempotency,
    AppleTokenService? apple,
    http.Client? client,
    SiteRebuildNotifier? rebuild,
  }) : _devices = devices,
       _notifications = notifications,
       _idempotency = idempotency,
       _apple = apple,
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

  /// The kept answers of its writes (docs/design/write-idempotency.md §6) —
  /// a manual booking's holds the client's name and phone for 24 h.
  final IdempotencyStore? _idempotency;
  final http.Client _client;
  final SiteRebuildNotifier _rebuild;

  /// Sign in with Apple (B6.7) — optional for the same reason; wired in
  /// `dependencies.dart`.
  final AppleTokenService? _apple;

  /// Delete the account behind [accountId]. Error codes: `forbidden`
  /// (unknown account), `demo_account_locked` (the store-review demo
  /// identity, T69 — answered first, nothing is written), `future_bookings`
  /// (settle the agenda first).
  /// What an erased owner's salons lose (B6.3): the contact numbers, the
  /// address, and the deposit that needed the Mobile Money number.
  static const Map<String, dynamic> _erasedContact = {
    'phoneNumber': '',
    'address': '',
    'whatsapp': null,
    'depositMobileMoneyNumber': null,
    'depositMobileMoneyOperator': null,
    'depositRequired': false,
  };

  Future<({bool ok, String? error})> deleteAccount(String accountId) async {
    final account = await _auth.accountById(accountId);
    if (account == null) return (ok: false, error: 'forbidden');

    // The demo review account (T69) may not delete itself. Its credential is
    // PUBLIC (printed in both stores' review notes), the Pro app offers
    // account deletion, and nothing recreates the identity automatically
    // (it can only be registered again by hand, into a new EMPTY salon): one
    // reviewer trying the feature on the shared account would end every
    // later review.
    //
    // FIRST, before the agenda gate below. That gate holds only while the
    // weekly reset's two upcoming bookings exist, and the account can clear
    // them itself — the answer must not depend on the day. Nothing past this
    // line runs: no unpublish, no KYC erasure, no device, notification or
    // membership write, no identity delete.
    //
    // Keyed on the CALLER's own e-mail (the caller is the subject, as for
    // salon creation) against the compile-time demo constant, and in the
    // service, not the route, so no future caller can route around it.
    // Design: docs/design/demo-account-deletion-lock.md.
    if (isDemoIdentity(account.email ?? '')) {
      return (ok: false, error: 'demo_account_locked');
    }

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
      // The salon outlives its owner — its name and history stay for the
      // clients — but the PERSON's numbers and address do not (decision 17,
      // docs/design/backend-integrity-batch6.md §2.3). A deposit without a
      // number is no deposit: off.
      await _providers.updateProfile(providerId, _erasedContact);
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
    await _idempotency?.deleteForAccount(accountId);

    // B6.7 (App Store 5.1.1(v)): revoke the Sign in with Apple authorization
    // and forget the token — never blocking, and before the identity, so a
    // failed delete retries into an empty list. The demo identity never gets
    // here (locked above). docs/design/backend-integrity-batch6.md §13.
    await _apple?.revokeAll(kind: 'provider', accountId: accountId);

    final ok = await _auth.deleteAccount(accountId);
    if (!ok) return (ok: false, error: 'forbidden');

    // Module `access` (drift §2.3-2): the identity's memberships die with it
    // — a member row must never outlive its account. DELETED, not revoked:
    // a revoked row keeps `account_id`, a foreign key to the identity, and
    // until 0038 that key had no ON DELETE action — so the identity delete
    // answered 500 to every salon owner in production (2026-10-14).
    //
    // AFTER the identity, never before. In Postgres 0038's cascade has
    // already removed the rows inside the identity's transaction, and this
    // finds none; it is what the in-memory twin, which has no foreign keys,
    // needs. Deleted first, a failed identity delete lost them for good, and
    // in between an account with no membership let GET /me/provider
    // auto-create a salon for a staff account.
    // docs/design/backend-provider-deletion-member-fk.md
    await _memberships.deleteAllForAccount(accountId);
    return (ok: true, error: null);
  }
}
