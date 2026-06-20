import 'package:flutter/foundation.dart';
import '../models/appointment.dart';
import '../core/di/dependency_injection.dart';
import '../services/interfaces/appointment_service_interface.dart';

class AppointmentProvider extends ChangeNotifier {
  final AppointmentServiceInterface _appointmentService = serviceLocator.appointmentService;

  List<Appointment> _appointments = [];
  Appointment? _selectedAppointment;
  bool _isLoading = false;
  String? _error;

  List<Appointment> get appointments => _appointments;
  Appointment? get selectedAppointment => _selectedAppointment;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Appointment> get upcomingAppointments {
    final now = DateTime.now();
    return _appointments
        .where((a) =>
            a.appointmentDate.isAfter(now) &&
            a.status != AppointmentStatus.cancelled)
        .toList()
      ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
  }

  List<Appointment> get pastAppointments {
    final now = DateTime.now();
    return _appointments
        .where((a) => a.appointmentDate.isBefore(now))
        .toList()
      ..sort((a, b) => b.appointmentDate.compareTo(a.appointmentDate));
  }

  List<Appointment> get cancelledAppointments {
    return _appointments
        .where((a) => a.status == AppointmentStatus.cancelled)
        .toList()
      ..sort((a, b) => b.appointmentDate.compareTo(a.appointmentDate));
  }

  bool hasCompletedBookingAt(String providerId, String userId) {
    return _appointments.any((a) =>
        a.providerId == providerId &&
        a.userId == userId &&
        a.status == AppointmentStatus.completed);
  }

  Future<void> loadAppointments({AppointmentStatus? status}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _appointmentService.getUserAppointments(status: status);
      if (response.success && response.data != null) {
        _appointments = response.data!;
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement';
        _appointments = [];
      }
    } catch (e) {
      _error = e.toString();
      _appointments = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> bookAppointment({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? artistId,
    String? notes,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _appointmentService.bookAppointment(
        providerId: providerId,
        serviceIds: serviceIds,
        appointmentDateTime: appointmentDateTime,
        artistId: artistId,
        notes: notes,
      );
      if (response.success && response.data != null) {
        _appointments.add(response.data!);
        _error = null;
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la réservation';
        return false;
      }
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAppointmentById(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _appointmentService.getAppointmentById(id);
      if (response.success && response.data != null) {
        _selectedAppointment = response.data;
        _error = null;
      } else {
        _error = response.error ?? 'Rendez-vous non trouvé';
        _selectedAppointment = null;
      }
    } catch (e) {
      _error = e.toString();
      _selectedAppointment = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> cancelAppointment(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _appointmentService.cancelAppointment(id);
      if (response.success) {
        final index = _appointments.indexWhere((a) => a.id == id);
        if (index != -1) {
          _appointments[index] = _appointments[index].copyWith(
            status: AppointmentStatus.cancelled,
          );
        }
        _error = null;
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de l\'annulation';
        return false;
      }
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<DateTime>> getAvailableTimeSlots({
    required String providerId,
    required DateTime date,
    List<String>? serviceIds,
    String? artistId,
    int? durationMinutes,
  }) async {
    try {
      final response = await _appointmentService.getAvailableTimeSlots(
        providerId: providerId,
        date: date,
        serviceIds: serviceIds,
        artistId: artistId,
        durationMinutes: durationMinutes,
      );
      if (response.success && response.data != null) {
        return response.data!;
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}



