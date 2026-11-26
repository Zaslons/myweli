import 'package:http/http.dart' as http;

import '../access/membership_repository.dart';
import '../appointments/appointment_repository.dart';
import '../appointments/booking_service.dart';
import '../appointments/pro_appointment_service.dart';
import '../auth/demo_seam.dart';
import '../auth/provider_auth_repository.dart';
import '../clients/clients_repository.dart';
import '../providers_repository.dart';
import '../storage/storage_service.dart';
import '../subscription/salon_subscription_repository.dart';
import '../subscription/subscription.dart';
import 'demo_snapshot_repository.dart';

/// How often the demo salon is restored to its curated state.
const Duration kDemoResetInterval = Duration(days: 7);

/// The snapshot's keys the reset never writes back
/// (docs/design/demo-reset-restore.md §5.1, decision 251):
///   · identity, the public-set membership (the demo salon is draft
///     forever) and the slug (immutable everywhere else, kept immutable
///     here);
///   · `featured`, the admin's flag (its one writer is the admin console);
///   · `rating` and `reviewCount`, which the reviews compute
///     (`updateRatings`). The reset keeps the reviews, so a restored rating
///     would contradict them — and in Postgres the `rating` column, which
///     orders discovery, would disagree with the document.
const Set<String> kDemoNeverRestored = {
  'id',
  'slug',
  'status',
  'featured',
  'rating',
  'reviewCount',
};

/// The snapshot's keys the reset puts back through their own writer, never
/// through the merge (docs/design/demo-reset-restore.md §5.1, decisions
/// 250, 252). In Postgres the services and the hours live in tables the
/// document merge never reaches, and `beforeAfters` is absent from a new
/// salon's document, so a snapshot may lack it and a merge would never
/// remove a reviewer's pairs. `test/demo/demo_reset_guards_test.dart` holds
/// every key an owner can write to one of the two: in a new salon's
/// document, or here.
const Set<String> kDemoRestoredByOwnWriter = {
  'services',
  'availability',
  'beforeAfters',
};

/// The demo salon's reset (T69): capture the curated state once, restore it
/// on a 7-day clock. One mechanism, three jobs — undo defacement (restore
/// the document), keep the agenda looking alive (regenerate bookings
/// relative to now), and keep the subscription from ever showing expired
/// (extend coverage as it runs). Design:
/// docs/design/backend-demo-review-account.md §6.2; what the restore puts
/// back and through which writer: docs/design/demo-reset-restore.md (B16.2).
class DemoResetService {
  DemoResetService(
    this._auth,
    this._providers,
    this._appointments,
    this._clients,
    this._subscriptions,
    this._members,
    this._booking,
    this._snapshots, {
    required ProAppointmentService lifecycle,
    void Function(String)? log,
    StorageService? storage,
    http.Client? client,
  }) : _lifecycle = lifecycle,
       _log = log ?? print,
       _storage = storage,
       _client = client ?? http.Client();

  final ProviderAuthRepository _auth;
  final ProvidersRepository _providers;
  final AppointmentRepository _appointments;
  final ClientsRepository _clients;
  final SalonSubscriptionRepository _subscriptions;
  final MembershipRepository _members;
  final BookingService _booking;
  final DemoSnapshotRepository _snapshots;

  /// « Terminé » and « Non présenté », exactly as the Pro app sends them —
  /// the status and the client card's last visit (decision 249).
  final ProAppointmentService _lifecycle;
  final void Function(String) _log;

  /// Where a reviewer's KYC pieces live (`kyc/<account>/`) — erased at each
  /// reset (B6.4). Null only in legacy unit tests; production passes it.
  final StorageService? _storage;
  final http.Client _client;

  /// Captures the demo salon's current state as the canonical snapshot.
  ///
  /// **The target is derived from [kDemoProviderEmail], never from input** —
  /// an operator typo must not be able to aim the weekly wipe at a real
  /// salon — and the salon it points at must be demo-OWNED (owner membership
  /// = the demo identity) or nothing is written (`not_demo_owned`).
  /// Re-capturing restarts the reset clock (the fresh state is by definition
  /// clean).
  Future<({bool ok, String? error, String? providerId})> capture(
    DateTime now,
  ) async {
    final account = await _auth.accountByEmail(kDemoProviderEmail);
    final providerId = account?.providerId;
    if (providerId == null) {
      return (ok: false, error: 'demo_account_missing', providerId: null);
    }
    final doc = await _providers.byId(providerId);
    if (doc == null) {
      return (ok: false, error: 'demo_salon_missing', providerId: null);
    }
    // The reset's owner check, run here too: the capture now WRITES billing
    // state (the offer pin below), so the scalar link alone may not aim it.
    // Refused before anything is written, the snapshot included — the reset
    // would refuse that snapshot forever anyway.
    if (!await _demoOwned(providerId)) {
      _log(
        'demo_reset capture REFUSED provider=$providerId cause=not_demo_owned',
      );
      return (ok: false, error: 'not_demo_owned', providerId: null);
    }
    await _snapshots.capture(providerId: providerId, doc: doc, capturedAt: now);
    // The offer too, from the first minute rather than the first reset: the
    // review notes are pasted right after this capture, and a demo salon
    // provisioned since the companion path cannot get a row any other way
    // (no choice in the app, the web choice demo-locked, publish refused).
    await _pinDemoOffer(providerId, now);
    _log('demo_reset captured provider=$providerId');
    return (ok: true, error: null, providerId: providerId);
  }

  /// Runs the reset iff ≥ [kDemoResetInterval] since the last one.
  ///
  /// Rides the daily subscriptions cron — a no-op on six days out of seven —
  /// so the cadence needs no Scheduler job of its own and nothing new that
  /// can stop silently.
  ///
  /// [outcome] is what the maintenance cron answers — `ran`, `not_due`,
  /// `no_snapshot`, `refused:not_demo_owned` or `refused:bad_snapshot` (a
  /// snapshot its writers cannot take, docs/design/demo-reset-restore.md
  /// §5.1): a bare `false` said both « not the day » and « the demo identity
  /// is lost » (docs/design/backend-integrity-batch6.md §2.9, B6.9).
  Future<({bool ran, String? error, String outcome})> tickIfDue(
    DateTime now,
  ) async {
    final snap = await _snapshots.read();
    if (snap == null) {
      // Nothing captured yet (pre-provisioning, or the seam was never used).
      // Quiet on purpose: this line would otherwise recur daily forever on
      // any deployment that never sets the demo up.
      return (ran: false, error: null, outcome: 'no_snapshot');
    }
    final last = snap.lastResetAt ?? snap.capturedAt;
    if (now.difference(last) < kDemoResetInterval) {
      return (ran: false, error: null, outcome: 'not_due');
    }

    // **The safety condition lives here, not in the operator's head**: even
    // though capture() derives the target from the constant and checks it,
    // the destructive half re-verifies it independently. A snapshot row pointing at a salon
    // whose owner is not the demo identity is refused loudly, whatever wrote
    // it.
    if (!await _demoOwned(snap.providerId)) {
      _log(
        'demo_reset REFUSED provider=${snap.providerId} '
        'cause=not_demo_owned',
      );
      return (
        ran: false,
        error: 'not_demo_owned',
        outcome: 'refused:not_demo_owned',
      );
    }

    // The snapshot must be one the writers below can take, or nothing is
    // written: a throw here would escape the maintenance tick before the
    // salon purge, every night, since `markReset` comes last.
    final badKey = _badSnapshotKey(snap.doc);
    if (badKey != null) {
      _log(
        'demo_reset REFUSED provider=${snap.providerId} '
        'cause=bad_snapshot key=$badKey',
      );
      return (
        ran: false,
        error: 'bad_snapshot',
        outcome: 'refused:bad_snapshot',
      );
    }

    // 1. Restore the curated salon (defacement undone) —
    //    docs/design/demo-reset-restore.md §5.1. Until B16.2 this step only
    //    merged the snapshot through `updateProfile`, which never reaches
    //    the services or (in Postgres) the hours, and never removes a key.
    //    The profile first: it puts back the timezone, which
    //    `replaceAvailability` reads to store a blocked day.
    final doc = snap.doc;
    final restore = Map<String, dynamic>.from(doc)
      ..removeWhere(
        (k, _) =>
            kDemoNeverRestored.contains(k) ||
            kDemoRestoredByOwnWriter.contains(k),
      );
    await _providers.updateProfile(snap.providerId, restore);
    //    Then each of [kDemoRestoredByOwnWriter] through its own writer. An
    //    absent `services` or `availability` skips its writer — it never
    //    wipes the catalogue or the hours — while absent pairs mean none.
    final services = doc['services'];
    if (services is List) {
      await _providers.replaceServices(snap.providerId, [
        for (final s in services) Map<String, dynamic>.from(s as Map),
      ]);
    }
    final availability = doc['availability'];
    if (availability is Map) {
      await _providers.replaceAvailability(
        snap.providerId,
        Map<String, dynamic>.from(availability),
      );
    }
    await _providers.updateBeforeAfters(snap.providerId, [
      for (final pair in (doc['beforeAfters'] as List?) ?? const <Object>[])
        Map<String, dynamic>.from(pair as Map),
    ]);

    // 2. Wipe the agenda and the client book (reviewer junk gone) …
    final wipedA = await _appointments.wipeForProvider(snap.providerId);
    final wipedC = await _clients.wipeForProvider(snap.providerId);

    // 3. … and regenerate a small plausible agenda RELATIVE TO NOW, through
    //    the real bookManual path, so the rows — and the auto-created client
    //    records — are exactly what the product produces. Frozen dates would
    //    show September forever.
    final regenerated = await _regenerateAgenda(snap.providerId, now);

    // 4. The subscription never shows expired to a reviewer: coverage is
    //    extended as part of the reset — no operator task, and no demo
    //    special case inside real billing logic.
    await _pinDemoOffer(snap.providerId, now);

    // 5. A reviewer may try the KYC flow on the demo account: its pieces and
    //    its state go with the rest of the week's junk (decision 18,
    //    docs/design/backend-integrity-batch6.md §2.4).
    await _forgetKyc(snap.providerId);

    await _snapshots.markReset(now);
    _log(
      'demo_reset ran provider=${snap.providerId} wiped=${wipedA + wipedC} '
      'regenerated=$regenerated',
    );
    return (ran: true, error: null, outcome: 'ran');
  }

  /// The first key of [doc] the reset's own writers could not take, or null
  /// (docs/design/demo-reset-restore.md §5.1): a service needs the columns
  /// Postgres casts (`id`, `name`, `price`, `durationMinutes`), the hours a
  /// map, the pairs a list of maps.
  static String? _badSnapshotKey(Map<String, dynamic> doc) {
    final services = doc['services'];
    if (services != null) {
      if (services is! List) return 'services';
      for (final s in services) {
        if (s is! Map ||
            s['id'] is! String ||
            s['name'] is! String ||
            s['price'] is! num ||
            s['durationMinutes'] is! num) {
          return 'services';
        }
      }
    }
    final availability = doc['availability'];
    if (availability != null && availability is! Map) return 'availability';
    final pairs = doc['beforeAfters'];
    if (pairs != null && (pairs is! List || pairs.any((p) => p is! Map))) {
      return 'beforeAfters';
    }
    return null;
  }

  /// The demo OWNER account's KYC, erased: each piece under its own prefix
  /// (`kyc/<account>/` — defence in depth, as the account erasure does), then
  /// the record — no pieces, `pending`, no rejection reason. A storage
  /// hiccup never blocks the reset: the record no longer points at the piece.
  Future<void> _forgetKyc(String providerId) async {
    final owner = (await _members.listForProvider(
      providerId,
    )).where((m) => m.role == 'owner' && isDemoIdentity(m.email));
    final accountId = owner.isEmpty ? null : owner.first.accountId;
    if (accountId == null) return;
    final account = await _auth.accountById(accountId);
    if (account == null || account.kycDocs.isEmpty) return;
    final storage = _storage;
    if (storage != null) {
      for (final doc in account.kycDocs) {
        final key = doc['key'] as String?;
        if (key == null || !key.startsWith('kyc/$accountId/')) continue;
        try {
          final url = storage.presignDelete(
            key: key,
            bucket: StorageBucket.kyc,
          );
          await _client.delete(Uri.parse(url));
        } catch (_) {
          // Tolerated: private, uuid-named, and no longer on the record.
        }
      }
    }
    await _auth.submitKyc(accountId, const []);
  }

  /// Whether [providerId]'s OWNER membership is the demo identity — the one
  /// safety condition both writers (capture and reset) verify independently.
  Future<bool> _demoOwned(String providerId) async {
    final members = await _members.listForProvider(providerId);
    return members.any((m) => m.role == 'owner' && isDemoIdentity(m.email));
  }

  /// The demo salon is ALWAYS on a live Pro offer (docs/design/
  /// pro-companion-path.md §3.3), so the reviewer sees « Offre Pro active »:
  /// the row is created if absent (it used to be chosen through the app,
  /// which no longer offers a choice), the tier is pinned back to `pro`
  /// (whatever a pre-lock switch left), and paid coverage runs 30 days from
  /// [now]. The trial clock a created row gets is the ordinary 90 days — the
  /// backstop that still reads « live » if the resets ever stop.
  Future<void> _pinDemoOffer(String providerId, DateTime now) async {
    await _subscriptions.createIfAbsent(
      providerId: providerId,
      tier: 'pro',
      trialEndsAt: now.add(const Duration(days: kProTrialDays)),
    );
    await _subscriptions.update(
      providerId,
      tier: 'pro',
      paidUntil: now.add(const Duration(days: 30)),
    );
    await _subscriptions.clearNotices(providerId);
  }

  /// The demo salon's agenda, RELATIVE TO [now] and through the real paths
  /// (docs/design/pro-revenue-analytics.md §8.1, decision 249): every
  /// booking is entered with `bookManual`, as the salon would, then the past
  /// ones are closed with the Pro app's own « Terminé » or « Non présenté »
  /// — so the store reviewer opens « Revenus » on figures, not on « Pas
  /// encore de revenus ».
  ///
  /// - Twelve completed bookings over the last eight weeks, so « Mois » and
  ///   its comparison both hold some, on every prestation in turn, one of
  ///   them with two prestations;
  /// - one absence;
  /// - yesterday's booking left confirmed: the « À clôturer » banner;
  /// - two ahead: « Prévu » and a live agenda.
  ///
  /// Collaborateurs: the salon's own, in turn, every fourth booking without
  /// one — and none at all while the salon has none (read 2026-11-26: the
  /// demo salon has none; adding them is the owner's, in the app, followed
  /// by a new capture, or the next reset removes them).
  Future<int> _regenerateAgenda(String providerId, DateTime now) async {
    final doc = await _providers.byId(providerId);
    final services = ((doc?['services'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((s) => s['active'] != false)
        .map((s) => s['id'] as String)
        .toList();
    if (services.isEmpty) {
      _log('demo_reset agenda_skipped cause=no_services');
      return 0;
    }
    final artists = [
      for (final a in (doc?['artists'] as List?) ?? const [])
        if (a is Map && a['id'] is String) a['id'] as String,
    ];
    String svc(int i) => services[i % services.length];
    String? artist(int i) =>
        (artists.isEmpty || i % 4 == 3) ? null : artists[i % artists.length];
    final owner = await _ownerAccountId(providerId);

    var created = 0;
    for (final (i, p) in kDemoAgenda.indexed) {
      final day = now.add(Duration(days: p.day));
      final r = await _booking.bookManual(
        providerId: providerId,
        serviceIds: [
          svc(p.service),
          if (p.secondService != null) svc(p.secondService!),
        ],
        appointmentDateTime: DateTime.utc(day.year, day.month, day.day, p.hour),
        artistId: artist(i),
        clientName: p.name,
        clientPhone: p.phone,
      );
      if (!r.ok) continue;
      created++;
      final id = r.appointment!['id'] as String;
      if (owner == null || p.close == null) continue;
      final closed = p.close == 'noShow'
          ? await _lifecycle.noShow(id, owner)
          : await _lifecycle.complete(id, owner);
      if (!closed.ok) {
        _log('demo_reset agenda_close_failed cause=${closed.error}');
      }
    }
    return created;
  }

  /// The demo salon's owner account — the one that closes its bookings.
  Future<String?> _ownerAccountId(String providerId) async {
    final owner = (await _members.listForProvider(
      providerId,
    )).where((m) => m.role == 'owner' && isDemoIdentity(m.email));
    return owner.isEmpty ? null : owner.first.accountId;
  }
}

/// One booking of the demo salon's agenda: [day] from the reset, at [hour]
/// UTC (the demo salon is in Abidjan), on the salon's [service]-th active
/// prestation (and a [secondService]), closed as [close] (`completed`,
/// `noShow`) or left confirmed (null). French names, CI-shaped numbers; the
/// same clients come back, as a salon's regulars do.
typedef DemoBooking = ({
  int day,
  int hour,
  int service,
  int? secondService,
  String name,
  String phone,
  String? close,
});

/// The agenda each reset rebuilds (decision 249). Twelve completed over
/// eight weeks, one absence, yesterday's « à clôturer », two ahead.
const List<DemoBooking> kDemoAgenda = [
  (
    day: -52,
    hour: 10,
    service: 0,
    secondService: null,
    name: 'Awa K.',
    phone: '+2250700000101',
    close: 'completed',
  ),
  (
    day: -47,
    hour: 15,
    service: 1,
    secondService: null,
    name: 'Mariam T.',
    phone: '+2250700000102',
    close: 'completed',
  ),
  (
    day: -41,
    hour: 11,
    service: 2,
    secondService: null,
    name: 'Fatou B.',
    phone: '+2250700000103',
    close: 'completed',
  ),
  (
    day: -36,
    hour: 16,
    service: 0,
    secondService: 3,
    name: 'Aïcha D.',
    phone: '+2250700000104',
    close: 'completed',
  ),
  (
    day: -30,
    hour: 10,
    service: 4,
    secondService: null,
    name: 'Awa K.',
    phone: '+2250700000101',
    close: 'completed',
  ),
  (
    day: -26,
    hour: 14,
    service: 1,
    secondService: null,
    name: 'Kadi S.',
    phone: '+2250700000105',
    close: 'completed',
  ),
  (
    day: -21,
    hour: 9,
    service: 0,
    secondService: null,
    name: 'Mariam T.',
    phone: '+2250700000102',
    close: 'completed',
  ),
  (
    day: -17,
    hour: 17,
    service: 2,
    secondService: null,
    name: 'Nadia C.',
    phone: '+2250700000106',
    close: 'completed',
  ),
  (
    day: -12,
    hour: 11,
    service: 3,
    secondService: null,
    name: 'Awa K.',
    phone: '+2250700000101',
    close: 'completed',
  ),
  (
    day: -10,
    hour: 16,
    service: 2,
    secondService: null,
    name: 'Rokia Y.',
    phone: '+2250700000107',
    close: 'noShow',
  ),
  (
    day: -8,
    hour: 15,
    service: 4,
    secondService: null,
    name: 'Fatou B.',
    phone: '+2250700000103',
    close: 'completed',
  ),
  (
    day: -5,
    hour: 10,
    service: 0,
    secondService: null,
    name: 'Aïcha D.',
    phone: '+2250700000104',
    close: 'completed',
  ),
  (
    day: -3,
    hour: 10,
    service: 1,
    secondService: null,
    name: 'Awa K.',
    phone: '+2250700000101',
    close: 'completed',
  ),
  (
    day: -1,
    hour: 15,
    service: 0,
    secondService: null,
    name: 'Mariam T.',
    phone: '+2250700000102',
    close: null,
  ),
  (
    day: 1,
    hour: 11,
    service: 1,
    secondService: null,
    name: 'Fatou B.',
    phone: '+2250700000103',
    close: null,
  ),
  (
    day: 2,
    hour: 16,
    service: 2,
    secondService: null,
    name: 'Aïcha D.',
    phone: '+2250700000104',
    close: null,
  ),
];
