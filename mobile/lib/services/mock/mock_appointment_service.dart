import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
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
    final resolvedArtistId = artistId ??
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
      status: depositAmount > 0
          ? AppointmentStatus.confirmed
          : AppointmentStatus.pending,
      totalPrice: totalPrice,
      depositAmount: depositAmount,
      balanceDue:
          (totalPrice - depositAmount).clamp(0.0, totalPrice).toDouble(),
      cancellationWindowHours: provider.cancellationWindowHours,
      notes: notes,
      createdAt: DateTime.now(),
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

    final eligible =
        _eligibleArtistIdsFor(provider: provider, serviceIds: serviceIds);
    if (eligible.isEmpty) return null;

    final duration =
        _durationMinutesFor(providerId: providerId, serviceIds: serviceIds);
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
                  providerId: providerId, serviceIds: apt.serviceIds)),
        );
        return _overlaps(start, end, aptStart, aptEnd);
      });
      if (!busy) return aid;
    }

    return null;
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

    return ApiResponse.success(appointments);
  }

  @override
  Future<ApiResponse<Appointment>> getAppointmentById(String id) async {
    await Future.delayed(AppConstants.mockDelay);

    try {
      final appointment = _appointments.firstWhere((a) => a.id == id);
      return ApiResponse.success(appointment);
    } catch (e) {
      return ApiResponse.error('Rendez-vous non trouvé');
    }
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
    if (newDateTime.isBefore(DateTime.now())) {
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

    // Normalize date to start of day
    final selectedDate = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Skip past dates
    if (selectedDate.isBefore(today)) {
      return ApiResponse.success([]);
    }

    final provider = MockData.providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => MockData.providers.first,
    );

    // Respect blocked dates from provider availability.
    final blocked = provider.availability.blockedDates.any((d) =>
        d.year == selectedDate.year &&
        d.month == selectedDate.month &&
        d.day == selectedDate.day);
    if (blocked) return ApiResponse.success([]);

    // Determine base opening slots from weekly schedule (30min slots).
    final weekdayIndex = selectedDate.weekday - 1; // Mon=1..Sun=7 -> 0..6
    final templateSlots =
        provider.availability.weeklySchedule[weekdayIndex] ?? const [];
    final openingSlots = templateSlots
        .where((s) => s.isAvailable)
        .map((s) => DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
              s.startTime.hour,
              s.startTime.minute,
            ))
        .toList()
      ..sort((a, b) => a.compareTo(b));

    if (openingSlots.isEmpty) return ApiResponse.success([]);

    // For today, skip slots in the past (start 1 hour from now).
    final minStart = selectedDate.isAtSameMomentAs(today)
        ? now.add(const Duration(hours: 1))
        : null;

    final duration = durationMinutes ??
        (serviceIds == null
            ? 30
            : _durationMinutesFor(
                providerId: providerId, serviceIds: serviceIds));
    final durationBlocks = (duration / 30).ceil().clamp(1, 48);

    // Keep a gap between appointments (cleanup/setup) by padding each existing
    // booking's busy window on both sides.
    final bufferMinutes = provider.availability.bufferMinutes;

    bool candidateOk(DateTime start) {
      if (minStart != null && start.isBefore(minStart)) return false;
      final end = start.add(Duration(minutes: duration));

      // Ensure provider opening slots cover the whole duration in 30-min increments.
      for (var i = 0; i < durationBlocks; i++) {
        final seg = start.add(Duration(minutes: 30 * i));
        final exists = openingSlots
            .any((t) => t.hour == seg.hour && t.minute == seg.minute);
        if (!exists) return false;
      }

      // If artistId specified, require that artist is free.
      if (artistId != null && artistId.isNotEmpty) {
        return !_appointments.any((apt) {
          if (apt.status == AppointmentStatus.cancelled) return false;
          if (apt.providerId != providerId) return false;
          if (apt.artistId != artistId) return false;
          final aptStart = apt.appointmentDate;
          final aptEnd = aptStart.add(
            Duration(
                minutes: _durationMinutesFor(
                    providerId: providerId, serviceIds: apt.serviceIds)),
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
      final eligible =
          _eligibleArtistIdsFor(provider: provider, serviceIds: serviceIds);
      if (eligible.isEmpty) return true; // salons with no artists

      for (final aid in eligible) {
        final busy = _appointments.any((apt) {
          if (apt.status == AppointmentStatus.cancelled) return false;
          if (apt.providerId != providerId) return false;
          if (apt.artistId != aid) return false;
          final aptStart = apt.appointmentDate;
          final aptEnd = aptStart.add(
            Duration(
                minutes: _durationMinutesFor(
                    providerId: providerId, serviceIds: apt.serviceIds)),
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

  List<String> _eligibleArtistIdsFor({
    required models.Provider provider,
    List<String>? serviceIds,
  }) {
    if (provider.artists.isEmpty) return const [];
    if (serviceIds == null || serviceIds.isEmpty) {
      return provider.artists.map((a) => a.id).toList();
    }

    final selectedServices =
        provider.services.where((s) => serviceIds.contains(s.id)).toList();
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
    final selected =
        provider.services.where((s) => serviceIds.contains(s.id)).toList();
    if (selected.isEmpty) return 30;
    final sum = selected.fold<int>(0, (acc, s) => acc + s.durationMinutes);
    return sum <= 0 ? 30 : sum;
  }

  bool _overlaps(
      DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }
}
