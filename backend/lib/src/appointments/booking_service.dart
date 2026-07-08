import 'dart:math';

import '../clients/clients_service.dart';
import '../providers_repository.dart';
import 'appointment_repository.dart';
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
  }) : _clients = clients;

  final ProvidersRepository _providers;
  final AppointmentRepository _appointments;
  final SlotService _slots;

  /// Module `clients`: every booking upserts the salon's client row
  /// ("derived, not entered" — docs/modules/clients.md). Best-effort.
  final ClientsService? _clients;
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
    final provider = await _providers.byId(providerId);
    if (provider == null) {
      return (ok: false, error: 'provider_not_found', appointment: null);
    }
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
      // A disabled service is not bookable (the server is the authority).
      if (service == null || service['active'] == false) {
        return (ok: false, error: 'invalid_service', appointment: null);
      }
      total += (service['price'] as num).toDouble();
      durationMinutes += (service['durationMinutes'] as num?)?.toInt() ?? 0;
    }
    if (durationMinutes <= 0) durationMinutes = 30; // safety floor

    // The server decides availability: the requested time must be a free slot
    // (rejects past/closed/break/already-booked, and non-aligned times).
    final slotResult = await _slots.availableSlots(
      providerId: providerId,
      date: appointmentDateTime,
      serviceIds: serviceIds,
    );
    final wanted = appointmentDateTime.toUtc();
    final isFree = (slotResult.slots ?? const []).any(
      (s) => s.isAtSameMomentAs(wanted),
    );
    if (!isFree) {
      return (ok: false, error: 'slot_unavailable', appointment: null);
    }

    final depositRequired = provider['depositRequired'] as bool? ?? false;
    final pct = (provider['depositPercentage'] as num?)?.toDouble() ?? 0;
    final deposit = depositRequired ? total * pct : 0.0;

    final appointment = {
      'id':
          'appt_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}',
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
      'depositScreenshotUrl': depositScreenshotUrl,
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
  /// (past/now/future, off-grid) is allowed; the DB partial unique index still
  /// rejects an exact-start collision with a non-cancelled booking
  /// (→ `slot_unavailable`). Authz (the caller manages [providerId]) is the
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
