import 'dart:math';

import '../clients/clients_service.dart';
import '../providers_repository.dart';
import '../salon_time.dart';
import '../salon_visibility.dart';
import '../security/identity_limits.dart';
import '../security/rate_limiter.dart';
import '../storage/storage_service.dart';
import '../upload_verification_service.dart';
import 'appointment_repository.dart';
import 'booking_window.dart';
import 'slot_service.dart';

/// Outcome of a booking attempt.
typedef BookingResult = ({
  bool ok,
  String? error,
  Map<String, dynamic>? appointment,
});

/// Booking business logic (docs/BACKEND.md §1, §3.4). The **server is the
/// authority** on price (total/deposit/balance from the provider's own prices +
/// policy) **and on availability** — the requested time must be a free slot per
/// [SlotService], so a client can't book a closed/past/already-taken slot
/// (double-booking prevention). Bookings are created `pending` (the salon
/// confirms; Myweli never auto-confirms on payment — PRD OQ-1).
class BookingService {
  BookingService(
    this._providers,
    this._appointments,
    this._slots, {
    ClientsService? clients,
    UploadVerificationService? verifier,
    RateLimiter? limiter,
    IdentityLimits limits = kDefaultIdentityLimits,
  }) : _clients = clients,
       _verifier = verifier,
       _limiter = limiter,
       _limits = limits;

  final ProvidersRepository _providers;
  final AppointmentRepository _appointments;
  final SlotService _slots;

  /// Module `clients`: every booking upserts the salon's client row
  /// ("derived, not entered" — docs/modules/clients.md). Best-effort.
  final ClientsService? _clients;

  /// Claim-time verification for a deposit screenshot attached inline at
  /// booking (T61). Optional so existing construction sites and the local flow
  /// keep working; the composition root always supplies it, which is what makes
  /// `_screenshotKey` below a real control in production.
  final UploadVerificationService? _verifier;

  /// Per-identity rate limit (T65). Optional for the same reason as the
  /// verifier above — existing construction sites keep compiling — and the
  /// composition root always supplies it, which is what makes this a real
  /// control in production rather than a decoration. A source-level test in
  /// `dependencies_wiring_test.dart` is what turns "always" from a claim into
  /// a check, because a null limiter means NO LIMIT with every test green.
  final RateLimiter? _limiter;
  final IdentityLimits _limits;

  final Random _random = Random.secure();

  Future<BookingResult> book({
    required String userId,
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? artistId,
    String? notes,
    String? depositScreenshotUrl,
  }) async {
    if (serviceIds.isEmpty) {
      return (ok: false, error: 'no_services', appointment: null);
    }
    // **The deposit proof is a CLAIM, and it was never treated as one.** This
    // field arrived as an opaque string and went straight into the column, from
    // where `DepositService.screenshotUrl` presigns it for the consumer, the
    // salon and admins — while that endpoint authorizes on the APPOINTMENT
    // (`appt['userId'] == sub`), never on the key. So owning a booking was
    // enough to have the server presign a key you do not own. (Bounded to the
    // deposit bucket, which is a compile-time constant at the presign call
    // site, and not enumerable — object ids are 16 bytes of `Random.secure()`.)
    //
    // The certain damage was the honest path, not the attack: the app attaches
    // the key it was just signed, which is a PENDING one, and nothing here ever
    // promoted it — so production's daily expiry deleted the payment proof for
    // a real dispute while the row went on claiming one was attached. And no
    // `objectSize` ever ran on it, so T61 simply did not apply to this path.
    //
    // Ownership first, and free: no I/O, so a forged key costs nothing and
    // creates nothing. `DepositService.submit` has always done exactly this;
    // the inline path is the one that never did.
    if (depositScreenshotUrl != null &&
        !depositScreenshotUrl.startsWith('${kPendingPrefix}deposit/$userId/')) {
      return (ok: false, error: 'invalid_input', appointment: null);
    }
    // **Counted before the work, not after it.** Everything above is pure
    // validation of the caller's own body; from here the request costs reads,
    // a slot computation and possibly a storage round trip. An attacker chooses
    // whether their attempt succeeds — a booking refused for `slot_unavailable`
    // leaves no row and still cost all of that — so they must not also get to
    // choose whether they are counted.
    //
    // On T61's ordering rule: that rule forbids MUTATING before authorizing,
    // and this is an INSERT. The subject is the difference. T61 protects
    // against a mutation whose subject is not yet proven to be the caller's;
    // this row's subject is the caller's own JWT-verified `sub`, established
    // before the handler ran. docs/design/backend-identity-rate-limits.md §4.
    if (!await allowUnderLimit(
      _limiter,
      bookingBucket(userId),
      _limits.booking,
    )) {
      return (ok: false, error: 'rate_limited', appointment: null);
    }

    // One question, asked in one place (`clientBookingRefusal`): missing,
    // suspended and not-yet-published each have their own code, and the
    // argument for the split lives with the rule rather than here. The
    // consumer reschedule asks the identical question, which is why this
    // stopped being three inline `if`s.
    final found = await _providers.byId(providerId);
    final refusal = clientBookingRefusal(found);
    if (refusal != null) {
      return (ok: false, error: refusal, appointment: null);
    }
    // Reaching here proves the salon exists — `clientBookingRefusal` answers
    // non-null for a null salon — but the analyzer cannot see that through the
    // helper, so the promotion is stated rather than inferred.
    final provider = found!;

    final services = (provider['services'] as List)
        .cast<Map<String, dynamic>>();
    var total = 0.0;
    var durationMinutes = 0;
    for (final id in serviceIds) {
      Map<String, dynamic>? service;
      for (final s in services) {
        if (s['id'] == id) {
          service = s;
          break;
        }
      }
      // A disabled service is not bookable (the server is the authority).
      if (service == null || service['active'] == false) {
        return (ok: false, error: 'invalid_service', appointment: null);
      }
      total += (service['price'] as num).toDouble();
      durationMinutes += (service['durationMinutes'] as num?)?.toInt() ?? 0;
    }
    if (durationMinutes <= 0) durationMinutes = 30; // safety floor

    // A14d — the bookable window, said explicitly on the WRITE path.
    //
    // The slot gate below already refuses these, but only as
    // `slot_unavailable`, which every client renders as some version of
    // « someone else just took your slot » — five such sentences exist across
    // mobile and web, and not one is true when the date is simply outside what
    // the salon accepts. So the two conditions get their own codes here, and
    // the booking route maps BOTH to 409 with an explicit `case`: the switch's
    // fallback is `HttpStatus.badRequest`, so a new code added without one
    // would silently ship as a 400.
    final availability = (provider['availability'] as Map)
        .cast<String, dynamic>();
    final tzName = provider['timezone'] as String?;
    final horizonDays =
        (availability['bookingHorizonDays'] as num?)?.toInt() ??
        kDefaultBookingHorizonDays;
    final noticeMinutes =
        (availability['minimumNoticeMinutes'] as num?)?.toInt() ??
        kDefaultMinimumNoticeMinutes;
    final nowUtc = DateTime.now().toUtc();
    final lastBookableDayStart = salonDayStartPlusUtc(
      nowUtc,
      tzName,
      horizonDays,
    );
    final requestedDayStart = salonCalendarDayBoundsUtc(
      appointmentDateTime,
      tzName,
    ).startUtc;
    if (requestedDayStart.isAfter(lastBookableDayStart)) {
      return (ok: false, error: 'beyond_horizon', appointment: null);
    }
    if (appointmentDateTime.toUtc().isBefore(
      nowUtc.add(Duration(minutes: noticeMinutes)),
    )) {
      return (ok: false, error: 'too_soon', appointment: null);
    }

    // The server decides availability: the requested time must be a free slot
    // (rejects past/closed/break/already-booked, and non-aligned times).
    // Capacity model (booking-capacity-web-hub.md): the check is per-artist
    // when one is chosen; « Sans préférence » needs a free capable chair.
    final slotResult = await _slots.availableSlots(
      providerId: providerId,
      date: appointmentDateTime,
      serviceIds: serviceIds,
      artistId: artistId,
    );
    if (!slotResult.ok) {
      return (ok: false, error: slotResult.error, appointment: null);
    }
    final wanted = appointmentDateTime.toUtc();
    final isFree = (slotResult.slots ?? const []).any(
      (s) => s.isAtSameMomentAs(wanted),
    );
    if (!isFree) {
      return (ok: false, error: 'slot_unavailable', appointment: null);
    }

    // Size-check and PROMOTE, immediately before the insert: a refused upload
    // must not leave a booking behind, and a promoted object must not outlive
    // one. `verifyAndPromote` and not `promoteNewUrls` on purpose — this column
    // holds a bare private KEY (the read presigns it directly), and at create
    // time there is no prior row, so `alreadyStored` is empty by construction.
    // The claim form is the correct one.
    //
    // Residual, stated: if the insert below then loses the slot race, one
    // promoted screenshot is orphaned. Rare, and strictly better than the
    // status quo, where EVERY screenshot was orphaned under `pending/` and
    // then deleted.
    var screenshotKey = depositScreenshotUrl;
    if (screenshotKey != null && _verifier != null) {
      final v = await _verifier.verifyAndPromote([
        screenshotKey,
      ], bucket: StorageBucket.deposit);
      if (!v.ok) {
        return (ok: false, error: v.error, appointment: null);
      }
      screenshotKey = v.keys.single;
    }

    final depositRequired = provider['depositRequired'] as bool? ?? false;
    final pct = (provider['depositPercentage'] as num?)?.toDouble() ?? 0;
    final deposit = depositRequired ? total * pct : 0.0;

    final appointment = {
      'id':
          'appt_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}',
      // Multi-pays §4: financial records are stamped with the salon's
      // currency at write time (immutable — the Fresha rule).
      'currency': provider['currency'] ?? 'XOF',
      'userId': userId,
      'providerId': providerId,
      'serviceIds': serviceIds,
      'artistId': artistId,
      'appointmentDate': appointmentDateTime.toUtc().toIso8601String(),
      'durationMinutes': durationMinutes,
      'status': 'pending',
      'totalPrice': total,
      'depositAmount': deposit,
      'balanceDue': total - deposit,
      'cancellationWindowHours':
          provider['cancellationWindowHours'] as int? ?? 24,
      'clientName': null,
      'clientPhone': null,
      'notes': notes,
      'depositScreenshotUrl': screenshotKey,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    final created = await _appointments.create(appointment);
    if (created == null) {
      // Lost the race — the DB rejected a concurrent booking for this slot.
      return (ok: false, error: 'slot_unavailable', appointment: null);
    }
    await _clients?.recordBooking(created);
    return (ok: true, error: null, appointment: created);
  }

  /// Salon-entered booking (walk-in, after-the-fact, or a phone booking for a
  /// future date). Server-priced from the provider's services like [book], but
  /// created **`confirmed`** with **no online deposit** and a sentinel
  /// `userId` (`'manual'` — no app account). Unlike [book] it does **not**
  /// validate the slot engine — the salon owns its calendar — so any time
  /// (past/now/future, off-grid) is allowed; the PER-ARTIST DB guards
  /// (migration 0026) still reject a same-artist collision
  /// (→ `slot_unavailable`); unassigned manual bookings are unguarded by
  /// design (§2.2 of booking-capacity-web-hub.md — the salon's own entry). Authz (the caller manages [providerId]) is the
  /// route's responsibility. (Design: docs/design/pro-manual-booking.md.)
  Future<BookingResult> bookManual({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? artistId,
    String? clientName,
    String? clientPhone,
    String? notes,
  }) async {
    if (serviceIds.isEmpty) {
      return (ok: false, error: 'no_services', appointment: null);
    }
    final provider = await _providers.byId(providerId);
    if (provider == null) {
      return (ok: false, error: 'provider_not_found', appointment: null);
    }
    // **A draft salon owns its calendar — only `suspended` is refused here.**
    // This used to refuse `draft` too, which meant the very first thing a new
    // salon tries — entering the appointments it already has, before going
    // live — failed with a bare « Une erreur est survenue. » (§21 row 82).
    // Three things say it should not: A14d's principle that the salon owns its
    // calendar, which is why this method skips the slot engine entirely; the
    // fact that a draft salon can already set hours, block dates and add
    // services, so refusing only appointments is arbitrary; and T54, which
    // already promises that a billing unpublish (`status → draft`) leaves
    // « journal/bookings/export » working — a guarantee this line was
    // contradicting.
    //
    // A suspended salon does not get the same latitude: it was stopped
    // deliberately, and it should not keep operating.
    if (provider['status'] == 'suspended') {
      return (ok: false, error: 'provider_suspended', appointment: null);
    }

    final services = (provider['services'] as List)
        .cast<Map<String, dynamic>>();
    var total = 0.0;
    var durationMinutes = 0;
    for (final id in serviceIds) {
      Map<String, dynamic>? service;
      for (final s in services) {
        if (s['id'] == id) {
          service = s;
          break;
        }
      }
      if (service == null || service['active'] == false) {
        return (ok: false, error: 'invalid_service', appointment: null);
      }
      total += (service['price'] as num).toDouble();
      durationMinutes += (service['durationMinutes'] as num?)?.toInt() ?? 0;
    }
    if (durationMinutes <= 0) durationMinutes = 30; // safety floor

    final appointment = {
      'id':
          'manual_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}',
      // Multi-pays §4: stamped with the salon's currency at write time.
      'currency': provider['currency'] ?? 'XOF',
      'userId': 'manual', // walk-in / phone client — no app account
      'providerId': providerId,
      'serviceIds': serviceIds,
      'artistId': artistId,
      'appointmentDate': appointmentDateTime.toUtc().toIso8601String(),
      'durationMinutes': durationMinutes,
      'status': 'confirmed', // salon-entered → confirmed, no client step
      'totalPrice': total,
      'depositAmount': 0,
      'balanceDue': total, // paid in person; no online deposit
      'cancellationWindowHours':
          provider['cancellationWindowHours'] as int? ?? 24,
      'clientName': clientName,
      'clientPhone': clientPhone,
      'notes': notes,
      'depositScreenshotUrl': null,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    final created = await _appointments.create(appointment);
    if (created == null) {
      return (ok: false, error: 'slot_unavailable', appointment: null);
    }
    await _clients?.recordBooking(created);
    return (ok: true, error: null, appointment: created);
  }
}
