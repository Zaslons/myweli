import 'dart:math';

import '../providers_repository.dart';
import 'appointment_repository.dart';

/// Outcome of a booking attempt.
typedef BookingResult = ({
  bool ok,
  String? error,
  Map<String, dynamic>? appointment,
});

/// Booking business logic (docs/BACKEND.md §1, §3.4). The **server is the
/// authority** on price: total/deposit/balance are computed from the provider's
/// own service prices + deposit policy — never taken from the client. Bookings
/// are created `pending` (the salon confirms; Myweli never auto-confirms on
/// payment — PRD OQ-1). Slot/availability validation is a later slice.
class BookingService {
  BookingService(this._providers, this._appointments);

  final ProvidersRepository _providers;
  final AppointmentRepository _appointments;
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

    final services = (provider['services'] as List)
        .cast<Map<String, dynamic>>();
    var total = 0.0;
    for (final id in serviceIds) {
      Map<String, dynamic>? service;
      for (final s in services) {
        if (s['id'] == id) {
          service = s;
          break;
        }
      }
      if (service == null) {
        return (ok: false, error: 'invalid_service', appointment: null);
      }
      total += (service['price'] as num).toDouble();
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
    return (
      ok: true,
      error: null,
      appointment: await _appointments.create(appointment),
    );
  }
}
