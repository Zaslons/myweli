import 'package:flutter/foundation.dart';

import '../core/access/pro_access_guard.dart';
import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/appointment.dart';
import '../services/interfaces/pro_service_interface.dart';

class ProAppointmentProvider extends ChangeNotifier implements SalonScoped {
  final ProServiceInterface _proService = serviceLocator.proService;

  List<Appointment> _appointments = [];
  bool _isLoading = false;
  String? _error;

  List<Appointment> get appointments => _appointments;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadAppointments(
    String providerId, {
    AppointmentStatus? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _proService.getProviderAppointments(
        providerId,
        status: status,
        startDate: startDate,
        endDate: endDate,
      );
      if (response.success && response.data != null) {
        _appointments = response.data!;
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement des rendez-vous';
        ProAccessGuard.report(response.code);
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

  Future<bool> acceptAppointment(String appointmentId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _proService.acceptAppointment(appointmentId);
      if (response.success) {
        // Update local appointment
        final index = _appointments.indexWhere((a) => a.id == appointmentId);
        if (index != -1) {
          _appointments[index] = _appointments[index].copyWith(
            status: AppointmentStatus.confirmed,
          );
        }
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de l\'acceptation';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> rejectAppointment(String appointmentId, String? reason) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response =
          await _proService.rejectAppointment(appointmentId, reason);
      if (response.success) {
        final index = _appointments.indexWhere((a) => a.id == appointmentId);
        if (index != -1) {
          _appointments[index] = _appointments[index].copyWith(
            status: AppointmentStatus.cancelled,
          );
        }
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors du rejet';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> markComplete(String appointmentId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _proService.markAppointmentComplete(appointmentId);
      if (response.success) {
        final index = _appointments.indexWhere((a) => a.id == appointmentId);
        if (index != -1) {
          _appointments[index] = _appointments[index].copyWith(
            status: AppointmentStatus.completed,
          );
        }
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la mise à jour';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> markNoShow(String appointmentId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _proService.markNoShow(appointmentId);
      if (response.success) {
        final index = _appointments.indexWhere((a) => a.id == appointmentId);
        if (index != -1) {
          _appointments[index] = _appointments[index].copyWith(
            status: AppointmentStatus.noShow,
          );
        }
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la mise à jour';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> reschedule(String appointmentId, DateTime newDateTime) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response =
          await _proService.rescheduleAppointment(appointmentId, newDateTime);
      if (response.success) {
        final index = _appointments.indexWhere((a) => a.id == appointmentId);
        if (index != -1) {
          _appointments[index] = _appointments[index].copyWith(
            appointmentDate: newDateTime,
          );
        }
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors du report';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createManualBooking({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? clientName,
    String? clientPhone,
    String? notes,
    String? artistId,
    bool sendSmsInvite = false,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _proService.createManualBooking(
        providerId: providerId,
        serviceIds: serviceIds,
        appointmentDateTime: appointmentDateTime,
        clientName: clientName,
        clientPhone: clientPhone,
        notes: notes,
        artistId: artistId,
        sendSmsInvite: sendSmsInvite,
      );
      if (response.success && response.data != null) {
        _appointments = [..._appointments, response.data!]
          ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
        _error = null;
        return true;
      }
      _error = response.error ?? 'Erreur lors de la création';
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _appointments = [];
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
