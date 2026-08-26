import '../access/membership_repository.dart';
import '../appointments/appointment_repository.dart';
import '../appointments/booking_service.dart';
import '../auth/demo_seam.dart';
import '../auth/provider_auth_repository.dart';
import '../clients/clients_repository.dart';
import '../providers_repository.dart';
import '../subscription/salon_subscription_repository.dart';
import 'demo_snapshot_repository.dart';

/// How often the demo salon is restored to its curated state.
const Duration kDemoResetInterval = Duration(days: 7);

/// The demo salon's reset (T69): capture the curated state once, restore it
/// on a 7-day clock. One mechanism, three jobs — undo defacement (restore
/// the document), keep the agenda looking alive (regenerate bookings
/// relative to now), and keep the subscription from ever showing expired
/// (extend coverage as it runs). Design:
/// docs/design/backend-demo-review-account.md §6.2.
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
    void Function(String)? log,
  }) : _log = log ?? print;

  final ProviderAuthRepository _auth;
  final ProvidersRepository _providers;
  final AppointmentRepository _appointments;
  final ClientsRepository _clients;
  final SalonSubscriptionRepository _subscriptions;
  final MembershipRepository _members;
  final BookingService _booking;
  final DemoSnapshotRepository _snapshots;
  final void Function(String) _log;

  /// Keys that must never be written back on a restore: identity, the
  /// public-set membership (the demo salon is draft forever), and the slug
  /// (immutable everywhere else, kept immutable here).
  static const Set<String> _neverRestored = {'id', 'slug', 'status'};

  /// Captures the demo salon's current state as the canonical snapshot.
  ///
  /// **The target is derived from [kDemoProviderEmail], never from input** —
  /// an operator typo must not be able to aim the weekly wipe at a real
  /// salon. Re-capturing restarts the reset clock (the fresh state is by
  /// definition clean).
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
    await _snapshots.capture(providerId: providerId, doc: doc, capturedAt: now);
    _log('demo_reset captured provider=$providerId');
    return (ok: true, error: null, providerId: providerId);
  }

  /// Runs the reset iff ≥ [kDemoResetInterval] since the last one.
  ///
  /// Rides the daily subscriptions cron — a no-op on six days out of seven —
  /// so the cadence needs no Scheduler job of its own and nothing new that
  /// can stop silently.
  Future<({bool ran, String? error})> tickIfDue(DateTime now) async {
    final snap = await _snapshots.read();
    if (snap == null) {
      // Nothing captured yet (pre-provisioning, or the seam was never used).
      // Quiet on purpose: this line would otherwise recur daily forever on
      // any deployment that never sets the demo up.
      return (ran: false, error: null);
    }
    final last = snap.lastResetAt ?? snap.capturedAt;
    if (now.difference(last) < kDemoResetInterval) {
      return (ran: false, error: null);
    }

    // **The safety condition lives here, not in the operator's head**: even
    // though capture() derives the target from the constant, the destructive
    // half re-verifies it independently. A snapshot row pointing at a salon
    // whose owner is not the demo identity is refused loudly, whatever wrote
    // it.
    final members = await _members.listForProvider(snap.providerId);
    final demoOwned = members.any(
      (m) => m.role == 'owner' && isDemoIdentity(m.email),
    );
    if (!demoOwned) {
      _log(
        'demo_reset REFUSED provider=${snap.providerId} '
        'cause=not_demo_owned',
      );
      return (ran: false, error: 'not_demo_owned');
    }

    // 1. Restore the curated document (defacement undone). `updateProfile`
    //    merges, and every key that existed at capture is in the snapshot,
    //    so everything the catalog surfaces can write gets reverted.
    final restore = Map<String, dynamic>.from(snap.doc)
      ..removeWhere((k, _) => _neverRestored.contains(k));
    await _providers.updateProfile(snap.providerId, restore);

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
    await _subscriptions.update(
      snap.providerId,
      paidUntil: now.add(const Duration(days: 30)),
    );
    await _subscriptions.clearNotices(snap.providerId);

    await _snapshots.markReset(now);
    _log(
      'demo_reset ran provider=${snap.providerId} wiped=${wipedA + wipedC} '
      'regenerated=$regenerated',
    );
    return (ran: true, error: null);
  }

  /// A handful of manual bookings around [now]: a few past (history for the
  /// journal and revenue), one upcoming today-ish, a couple ahead (a live
  /// agenda). French names, CI-shaped numbers, the salon's own services.
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
    String svc(int i) => services[i % services.length];
    final plan = <({Duration offset, int hour, String name, String phone})>[
      (
        offset: const Duration(days: -3),
        hour: 10,
        name: 'Awa K.',
        phone: '+2250700000101',
      ),
      (
        offset: const Duration(days: -1),
        hour: 15,
        name: 'Mariam T.',
        phone: '+2250700000102',
      ),
      (
        offset: const Duration(days: 1),
        hour: 11,
        name: 'Fatou B.',
        phone: '+2250700000103',
      ),
      (
        offset: const Duration(days: 2),
        hour: 16,
        name: 'Aïcha D.',
        phone: '+2250700000104',
      ),
    ];
    var created = 0;
    for (final (i, p) in plan.indexed) {
      final day = now.add(p.offset);
      final r = await _booking.bookManual(
        providerId: providerId,
        serviceIds: [svc(i)],
        appointmentDateTime: DateTime.utc(day.year, day.month, day.day, p.hour),
        clientName: p.name,
        clientPhone: p.phone,
      );
      if (r.ok) created++;
    }
    return created;
  }
}
