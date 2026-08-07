import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/breaks.dart';
import '../../core/utils/salon_time.dart';
import '../../core/utils/staff_hours.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/artist.dart';
import '../../models/provider.dart' as models;
import '../interfaces/appointment_service_interface.dart';
import 'mock_data.dart';

class MockAppointmentService implements AppointmentServiceInterface {
  final _uuid = const Uuid();
  static const String _appointmentsKey = 'mock_appointments';
  List<Appointment> _appointments = [];

  MockAppointmentService() {
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? appointmentsJson = prefs.getString(_appointmentsKey);
      if (appointmentsJson != null) {
        final List<dynamic> decoded = json.decode(appointmentsJson);
        _appointments = decoded
            .map((json) => Appointment.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        // Initialize with default mock data
        _appointments = List.from(MockData.appointments);
        await _saveAppointments();
      }
    } catch (e) {
      // If loading fails, use default mock data
      _appointments = List.from(MockData.appointments);
    }
  }

  Future<void> _saveAppointments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String appointmentsJson = json.encode(
        _appointments.map((a) => a.toJson()).toList(),
      );
      await prefs.setString(_appointmentsKey, appointmentsJson);
    } catch (e) {
      // Silently fail - this is mock data
    }
  }

  @override
  Future<ApiResponse<Appointment>> bookAppointment({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? artistId,
    String? notes,
    double depositAmount = 0,
    String? depositScreenshotUrl,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    // Find provider to get service prices
    final provider = MockData.providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => MockData.providers.first,
    );

    // Calculate total price from actual services
    double totalPrice = 0.0;
    for (final serviceId in serviceIds) {
      final service = provider.services.firstWhere(
        (s) => s.id == serviceId,
        orElse: () => provider.services.first,
      );
      totalPrice += service.price;
    }

    // If user has no preference, pick an available artist who can do the selected services.
    final resolvedArtistId =
        artistId ??
        _pickArtistIdForBooking(
          providerId: providerId,
          serviceIds: serviceIds,
          appointmentDateTime: appointmentDateTime,
        );

    if (resolvedArtistId == null &&
        MockData.getArtistsForProvider(providerId).isNotEmpty) {
      return ApiResponse.error('Aucun spécialiste disponible pour ce créneau');
    }

    final appointment = Appointment(
      id: _uuid.v4(),
      userId: 'user1', // Mock user ID - in real app, get from auth
      providerId: providerId,
      serviceIds: serviceIds,
      artistId: resolvedArtistId,
      appointmentDate: appointmentDateTime,
      // Always pending: the salon confirms (after receiving the deposit, if
      // one was required) — Myweli never auto-confirms on payment.
      status: AppointmentStatus.pending,
      totalPrice: totalPrice,
      depositAmount: depositAmount,
      balanceDue: (totalPrice - depositAmount)
          .clamp(0.0, totalPrice)
          .toDouble(),
      cancellationWindowHours: provider.cancellationWindowHours,
      notes: notes,
      depositScreenshotUrl: depositScreenshotUrl,
      createdAt: AppClock.now(),
    );

    _appointments.add(appointment);
    await _saveAppointments();

    return ApiResponse.success(
      appointment,
      message: 'Rendez-vous réservé avec succès',
    );
  }

  String? _pickArtistIdForBooking({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
  }) {
    final provider = MockData.providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => MockData.providers.first,
    );

    if (provider.artists.isEmpty) return null;

    final eligible = _eligibleArtistIdsFor(
      provider: provider,
      serviceIds: serviceIds,
    );
    if (eligible.isEmpty) return null;

    final duration = _durationMinutesFor(
      providerId: providerId,
      serviceIds: serviceIds,
    );
    final start = appointmentDateTime;
    final end = appointmentDateTime.add(Duration(minutes: duration));

    for (final aid in eligible) {
      final busy = _appointments.any((apt) {
        if (apt.status == AppointmentStatus.cancelled) return false;
        if (apt.providerId != providerId) return false;
        if (apt.artistId != aid) return false;
        final aptStart = apt.appointmentDate;
        final aptEnd = aptStart.add(
          Duration(
            minutes: _durationMinutesFor(
              providerId: providerId,
              serviceIds: apt.serviceIds,
            ),
          ),
        );
        return _overlaps(start, end, aptStart, aptEnd);
      });
      if (!busy) return aid;
    }

    return null;
  }

  /// The mock's copy of the backend's `withProviderFacts`
  /// (`salon-state-and-refusals.md` §5, Decision C).
  ///
  /// The consumer surfaces read the salon's name, contact, deposit handle and
  /// booking window OFF the appointment now, so a mock that returns bare rows
  /// would show the app degrading in exactly the way the real backend never
  /// will — the opposite of what a mock is for (ROADMAP §2.1: mocks simulate
  /// the real response, including its enrichment).
  Appointment _withProviderFacts(Appointment a) {
    final salon = MockData.providers
        .where((p) => p.id == a.providerId)
        .firstOrNull;
    if (salon == null) return a;
    final services = {for (final s in salon.services) s.id: s};
    return a.copyWith(
      providerName: salon.name,
      providerStatus: 'active',
      providerPhone: salon.phoneNumber,
      providerWhatsapp: salon.whatsapp,
      providerAddress: salon.address,
      providerCountryCode: salon.countryCode,
      providerTimezone: salon.timezone,
      providerCurrency: salon.currency,
      depositMobileMoneyOperator: salon.depositMobileMoneyOperator,
      depositMobileMoneyNumber: salon.depositMobileMoneyNumber,
      artistName: a.artistId == null
          ? null
          : salon.artists.where((x) => x.id == a.artistId).firstOrNull?.name,
      serviceNames: [
        for (final id in a.serviceIds)
          if (services[id] case final s?) s.name,
      ],
      providerBookingHorizonDays: salon.availability.bookingHorizonDays,
      providerMinimumNoticeMinutes: salon.availability.minimumNoticeMinutes,
      durationMinutes:
          a.durationMinutes ??
          (a.serviceIds.any(services.containsKey)
              ? a.serviceIds.fold<int>(
                  0,
                  (t, id) => t + (services[id]?.durationMinutes ?? 0),
                )
              : null),
    );
  }

  @override
  Future<ApiResponse<List<Appointment>>> getUserAppointments({
    AppointmentStatus? status,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    var appointments = List<Appointment>.from(_appointments);

    // Filter by status
    if (status != null) {
      appointments = appointments.where((a) => a.status == status).toList();
    }

    // Sort by date (upcoming first)
    appointments.sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));

    return ApiResponse.success(appointments.map(_withProviderFacts).toList());
  }

  @override
  Future<ApiResponse<Appointment>> getAppointmentById(String id) async {
    await Future.delayed(AppConstants.mockDelay);

    try {
      final appointment = _appointments.firstWhere((a) => a.id == id);
      return ApiResponse.success(_withProviderFacts(appointment));
    } catch (e) {
      return ApiResponse.error('Rendez-vous non trouvé');
    }
  }

  @override
  Future<ApiResponse<String>> uploadDepositScreenshot({
    required String source,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    // Mimic the real private upload: return an opaque key (no public URL).
    return ApiResponse.success('deposit/mock-user/${const Uuid().v4()}.jpg');
  }

  @override
  Future<ApiResponse<Appointment>> submitDeposit({
    required String appointmentId,
    required String screenshotKey,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    final index = _appointments.indexWhere((a) => a.id == appointmentId);
    if (index == -1) {
      return ApiResponse.error('Rendez-vous non trouvé');
    }
    if (_appointments[index].status != AppointmentStatus.pending) {
      return ApiResponse.error('Cette action n’est plus possible.');
    }
    _appointments[index] = _appointments[index].copyWith(
      depositScreenshotUrl: screenshotKey,
    );
    await _saveAppointments();
    return ApiResponse.success(_appointments[index]);
  }

  @override
  Future<ApiResponse<String>> depositScreenshotUrl({
    required String appointmentId,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    final index = _appointments.indexWhere((a) => a.id == appointmentId);
    if (index == -1 || _appointments[index].depositScreenshotUrl == null) {
      return ApiResponse.error('Aucune capture jointe');
    }
    // A sample image stands in for the signed URL in mock mode.
    return ApiResponse.success(
      'asset:assets/images/providers/salon_excellence_photo.png',
    );
  }

  @override
  Future<ApiResponse<void>> cancelAppointment(String id) async {
    await Future.delayed(AppConstants.mockDelay);

    final index = _appointments.indexWhere((a) => a.id == id);
    if (index == -1) {
      return ApiResponse.error('Rendez-vous non trouvé');
    }

    _appointments[index] = _appointments[index].copyWith(
      status: AppointmentStatus.cancelled,
    );
    await _saveAppointments();

    return ApiResponse.success(null, message: 'Rendez-vous annulé');
  }

  @override
  Future<ApiResponse<Appointment>> rescheduleAppointment({
    required String id,
    required DateTime newDateTime,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    final index = _appointments.indexWhere((a) => a.id == id);
    if (index == -1) {
      return ApiResponse.error('Rendez-vous non trouvé');
    }

    final current = _appointments[index];
    if (current.status == AppointmentStatus.cancelled ||
        current.status == AppointmentStatus.completed) {
      return ApiResponse.error('Ce rendez-vous ne peut pas être reporté');
    }
    if (newDateTime.isBefore(AppClock.now())) {
      return ApiResponse.error('Veuillez choisir une date à venir');
    }

    // Deposit and balance carry over; only the date moves.
    final updated = current.copyWith(appointmentDate: newDateTime);
    _appointments[index] = updated;
    await _saveAppointments();

    return ApiResponse.success(updated, message: 'Rendez-vous reporté');
  }

  @override
  Future<ApiResponse<List<DateTime>>> getAvailableTimeSlots({
    required String providerId,
    required DateTime date,
    List<String>? serviceIds,
    String? artistId,
    int? durationMinutes,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    final provider = MockData.providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => MockData.providers.first,
    );
    // The requested calendar day (its y/m/d FIELDS) names THIS salon's day,
    // and slot instants are that salon's wall-clocks — mirroring the MP1
    // backend slot engine (salon_time.dart).
    final tz = provider.timezone;
    final dayStartUtc = salonDateTime(date.year, date.month, date.day, tz: tz);
    final todayStartUtc = salonDayBoundsUtc(tz: tz).startUtc;

    // Skip past dates
    if (dayStartUtc.isBefore(todayStartUtc)) {
      return ApiResponse.success([]);
    }

    // A14d — the FAR end of the bookable window. Placed here, after the past
    // gate and before the blocked-date scan, to mirror
    // `backend/lib/src/appointments/slot_service.dart`: the cheapest refusal
    // comes first, and every « no slots » condition returns the SAME shape
    // (a success with an empty list), never an error.
    //
    // The mock had no horizon check at all before A14d, so a day 400 days out
    // returned a full slot list while the server refused the booking. Every
    // mobile test runs against this file, so a gate written without this would
    // have passed while the API said no.
    final today = salonToday(tz: tz);
    // Field arithmetic, not `add(Duration(days:))`: the latter adds fixed
    // 24-hour blocks and lands an hour into the wrong day across a DST
    // boundary. `salonDateTime` normalises the overflow.
    final lastBookableDayStartUtc = salonDateTime(
      today.year,
      today.month,
      today.day + provider.availability.bookingHorizonDays,
      tz: tz,
    );
    if (dayStartUtc.isAfter(lastBookableDayStartUtc)) {
      return ApiResponse.success([]);
    }

    // Respect blocked dates (SALON calendar days) from provider availability.
    final blocked = provider.availability.blockedDates.any((d) {
      final wall = toSalonTime(d, tz: tz);
      return wall.year == date.year &&
          wall.month == date.month &&
          wall.day == date.day;
    });
    if (blocked) return ApiResponse.success([]);

    // Determine base opening starts from the weekly schedule — weekday of the
    // requested calendar date (pure field math).
    //
    // **Each entry is a RANGE, and reading only its `startTime` was a booking
    // outage on both engines.** This used to map one start per entry and
    // discard `endTime`, which is correct only when the template holds one
    // entry per 30-minute step — the shape `MockData._generateTimeSlots` emits
    // and the only shape this engine had ever been asked about. The pro's day
    // editor writes one `TimeSlot` per range the owner picks, so « 09:00 –
    // 18:00 » is ONE entry and a split day is two: nine open hours offered one
    // start, and a lunch-closed day offered two. `slot_service.dart` carries
    // the identical fix and the identical reasoning; the A14 device run found
    // it there, and the adversarial review of that write-up found it here.
    //
    // Enumerating `[start, end)` in steps is strictly a superset: an entry
    // exactly one step long still contributes exactly its own start, so the
    // seeded template's meaning — which most of the mock suite depends on — is
    // untouched. `mock_open_hours_test.dart` holds the pair.
    final weekdayIndex =
        DateTime.utc(date.year, date.month, date.day).weekday - 1;
    final templateSlots =
        provider.availability.weeklySchedule[weekdayIndex] ?? const [];
    final openMinutes = <int>{};
    for (final s in templateSlots) {
      if (!s.isAvailable) continue;
      final startMin = s.startTime.hour * 60 + s.startTime.minute;
      final endMin = s.endTime.hour * 60 + s.endTime.minute;
      // An inverted or zero-length window contributes its start and nothing
      // more — which is what EVERY window used to do, so the floor never gets
      // worse than it already was.
      if (endMin <= startMin) {
        openMinutes.add(startMin);
        continue;
      }
      for (var m = startMin; m < endMin; m += 30) {
        openMinutes.add(m);
      }
    }
    final openingSlots =
        openMinutes
            .map(
              (m) => salonDateTime(
                date.year,
                date.month,
                date.day,
                hour: m ~/ 60,
                minute: m % 60,
                tz: tz,
              ),
            )
            .toList()
          ..sort((a, b) => a.compareTo(b));

    if (openingSlots.isEmpty) return ApiResponse.success([]);

    // A14d — the NEAR end. This was « for today, only offer starts >= 1h from
    // now », computed only when the requested day WAS today and left null
    // otherwise: correct for a one-hour notice and structurally incapable of
    // expressing a longer one, because a salon requiring 48 hours must exclude
    // TOMORROW and that branch did not exist. One absolute instant says both,
    // mirroring the same restructure in `slot_service.dart`.
    //
    // At the default 60 this is byte-identical to the old rule: on today it IS
    // the old rule, and on any later day `now + 60min` precedes every slot, so
    // nothing is filtered. That equivalence is asserted rather than claimed.
    final minStart = AppClock.now().toUtc().add(
      Duration(minutes: provider.availability.minimumNoticeMinutes),
    );

    final duration =
        durationMinutes ??
        (serviceIds == null
            ? 30
            : _durationMinutesFor(
                providerId: providerId,
                serviceIds: serviceIds,
              ));
    final durationBlocks = (duration / 30).ceil().clamp(1, 48);

    // Keep a gap between appointments (cleanup/setup) by padding each existing
    // booking's busy window on both sides.
    final bufferMinutes = provider.availability.bufferMinutes;

    bool candidateOk(DateTime start) {
      if (start.isBefore(minStart)) return false;
      final end = start.add(Duration(minutes: duration));

      // Ensure provider opening slots cover the whole duration in 30-min increments.
      for (var i = 0; i < durationBlocks; i++) {
        final seg = start.add(Duration(minutes: 30 * i));
        final exists = openingSlots.any(
          (t) => t.hour == seg.hour && t.minute == seg.minute,
        );
        if (!exists) return false;
      }

      // Reject anything that runs into a provider break (e.g. lunch).
      if (overlapsBreak(provider.availability.breaks, start, end)) {
        return false;
      }

      // If artistId specified, require that artist works then and is free.
      if (artistId != null && artistId.isNotEmpty) {
        final artist = _artistById(provider, artistId);
        if (artist != null && !artistWorksDuring(artist, start, end)) {
          return false;
        }
        return !_appointments.any((apt) {
          if (apt.status == AppointmentStatus.cancelled) return false;
          if (apt.providerId != providerId) return false;
          if (apt.artistId != artistId) return false;
          final aptStart = apt.appointmentDate;
          final aptEnd = aptStart.add(
            Duration(
              minutes: _durationMinutesFor(
                providerId: providerId,
                serviceIds: apt.serviceIds,
              ),
            ),
          );
          return _overlaps(
            start,
            end,
            aptStart.subtract(Duration(minutes: bufferMinutes)),
            aptEnd.add(Duration(minutes: bufferMinutes)),
          );
        });
      }

      // Otherwise, require at least one eligible artist free for this time.
      final eligible = _eligibleArtistIdsFor(
        provider: provider,
        serviceIds: serviceIds,
      );
      if (eligible.isEmpty) return true; // salons with no artists

      for (final aid in eligible) {
        // Skip artists who aren't working during this window.
        final artist = _artistById(provider, aid);
        if (artist != null && !artistWorksDuring(artist, start, end)) {
          continue;
        }
        final busy = _appointments.any((apt) {
          if (apt.status == AppointmentStatus.cancelled) return false;
          if (apt.providerId != providerId) return false;
          if (apt.artistId != aid) return false;
          final aptStart = apt.appointmentDate;
          final aptEnd = aptStart.add(
            Duration(
              minutes: _durationMinutesFor(
                providerId: providerId,
                serviceIds: apt.serviceIds,
              ),
            ),
          );
          return _overlaps(
            start,
            end,
            aptStart.subtract(Duration(minutes: bufferMinutes)),
            aptEnd.add(Duration(minutes: bufferMinutes)),
          );
        });
        if (!busy) return true;
      }
      return false;
    }

    final availableSlots = openingSlots.where(candidateOk).toList();

    // Sort by time
    availableSlots.sort((a, b) => a.compareTo(b));

    return ApiResponse.success(availableSlots);
  }

  Artist? _artistById(models.Provider provider, String id) {
    for (final a in provider.artists) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<String> _eligibleArtistIdsFor({
    required models.Provider provider,
    List<String>? serviceIds,
  }) {
    if (provider.artists.isEmpty) return const [];
    if (serviceIds == null || serviceIds.isEmpty) {
      return provider.artists.map((a) => a.id).toList();
    }

    final selectedServices = provider.services
        .where((s) => serviceIds.contains(s.id))
        .toList();
    if (selectedServices.isEmpty) {
      return provider.artists.map((a) => a.id).toList();
    }
    if (selectedServices.any((s) => s.artistIds.isEmpty)) {
      return provider.artists.map((a) => a.id).toList();
    }
    return selectedServices
        .map((s) => s.artistIds)
        .reduce((a, b) => a.where(b.contains).toList());
  }

  int _durationMinutesFor({
    required String providerId,
    required List<String> serviceIds,
  }) {
    final provider = MockData.providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => MockData.providers.first,
    );
    if (serviceIds.isEmpty) return 30;
    final selected = provider.services
        .where((s) => serviceIds.contains(s.id))
        .toList();
    if (selected.isEmpty) return 30;
    final sum = selected.fold<int>(0, (acc, s) => acc + s.durationMinutes);
    return sum <= 0 ? 30 : sum;
  }

  bool _overlaps(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }
}
