import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../core/utils/app_clock.dart';
import '../core/utils/visit_history.dart' as vh;
import '../models/appointment.dart';
import '../services/interfaces/appointment_service_interface.dart';

/// What the funnel says when it could not ASK the salon — as opposed to when
/// the salon answered « rien de libre ». French, and a sentence rather than an
/// exception's `toString()` (§14).
const String kSlotsError =
    'Impossible de charger les créneaux. Vérifiez votre connexion.';

class AppointmentProvider extends ChangeNotifier {
  final AppointmentServiceInterface _appointmentService =
      serviceLocator.appointmentService;

  List<Appointment> _appointments = [];
  Appointment? _selectedAppointment;
  bool _isLoading = false;
  String? _error;

  /// The machine code behind [_error], kept because a sentence alone cannot
  /// say whether the refusal has a way out (§21 row 82). Same shape as
  /// `ProTeamProvider._inviteErrorCode`, which the offer CTAs already use.
  String? _errorCode;

  List<Appointment> get appointments => _appointments;
  Appointment? get selectedAppointment => _selectedAppointment;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get errorCode => _errorCode;

  List<Appointment> get upcomingAppointments {
    final now = AppClock.now();
    return _appointments
        .where(
          (a) =>
              a.appointmentDate.isAfter(now) &&
              a.status != AppointmentStatus.cancelled,
        )
        .toList()
      ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
  }

  List<Appointment> get pastAppointments {
    final now = AppClock.now();
    return _appointments.where((a) => a.appointmentDate.isBefore(now)).toList()
      ..sort((a, b) => b.appointmentDate.compareTo(a.appointmentDate));
  }

  List<Appointment> get cancelledAppointments {
    return _appointments
        .where((a) => a.status == AppointmentStatus.cancelled)
        .toList()
      ..sort((a, b) => b.appointmentDate.compareTo(a.appointmentDate));
  }

  /// Completed past visits (effective status), newest first.
  List<Appointment> get visitHistory =>
      vh.visitHistory(_appointments, AppClock.now());

  bool hasCompletedBookingAt(String providerId, String userId) =>
      latestCompletedAppointmentId(providerId, userId) != null;

  /// The most recent completed appointment id the user had at [providerId] — the
  /// visit a "leave a review" CTA reviews. Null if there is none.
  String? latestCompletedAppointmentId(String providerId, String userId) {
    final completed =
        _appointments
            .where(
              (a) =>
                  a.providerId == providerId &&
                  a.userId == userId &&
                  a.status == AppointmentStatus.completed,
            )
            .toList()
          ..sort((a, b) => b.appointmentDate.compareTo(a.appointmentDate));
    return completed.isEmpty ? null : completed.first.id;
  }

  Future<void> loadAppointments({AppointmentStatus? status}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _appointmentService.getUserAppointments(
        status: status,
      );
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
    double depositAmount = 0,
    String? depositScreenshotUrl,
  }) async {
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();

    try {
      final response = await _appointmentService.bookAppointment(
        providerId: providerId,
        serviceIds: serviceIds,
        appointmentDateTime: appointmentDateTime,
        artistId: artistId,
        notes: notes,
        depositAmount: depositAmount,
        depositScreenshotUrl: depositScreenshotUrl,
      );
      if (response.success && response.data != null) {
        _appointments.add(response.data!);
        _error = null;
        _errorCode = null;
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la réservation';
        _errorCode = response.code;
        return false;
      }
    } catch (e) {
      _error = e.toString();
      _errorCode = null;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pay-later: attach a deposit screenshot (already uploaded → [screenshotKey])
  /// to an existing pending booking, then refresh it in the list.
  Future<bool> submitDeposit({
    required String appointmentId,
    required String screenshotKey,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await _appointmentService.submitDeposit(
        appointmentId: appointmentId,
        screenshotKey: screenshotKey,
      );
      if (response.success && response.data != null) {
        final i = _appointments.indexWhere((a) => a.id == appointmentId);
        if (i != -1) _appointments[i] = response.data!;
        _error = null;
        return true;
      }
      _error = response.error ?? 'Erreur lors de l’envoi de l’acompte';
      return false;
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
        _error = response.error ?? 'Erreur lors de l’annulation';
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

  Future<bool> rescheduleAppointment({
    required String id,
    required DateTime newDateTime,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _appointmentService.rescheduleAppointment(
        id: id,
        newDateTime: newDateTime,
      );
      if (response.success && response.data != null) {
        final updated = response.data!;
        final index = _appointments.indexWhere((a) => a.id == id);
        if (index != -1) {
          _appointments[index] = updated;
        }
        if (_selectedAppointment?.id == id) {
          _selectedAppointment = updated;
        }
        _error = null;
        return true;
      } else {
        _error = response.error ?? 'Erreur lors du report';
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

  /// The salon's free starts on [date], **and why the list is empty when it is**.
  ///
  /// **This returned a bare `List<DateTime>` and swallowed every failure into
  /// `return []`** (A14c §19). So « Aucun créneau disponible » was the sentence
  /// for a fully-booked Saturday *and* for a dead network — the screen had
  /// three states where §14 requires four, and the missing one was the only
  /// one a user can act on.
  ///
  /// The layer below always knew: `ApiResponse` carries `error` and `code`.
  /// Only this method threw it away. A record rather than the raw
  /// `ApiResponse` because callers want *"here are the slots, here is why there
  /// are none"* and never the envelope's other fields.
  Future<({List<DateTime> slots, String? error})> getAvailableTimeSlots({
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
        return (slots: response.data!, error: null);
      }
      return (slots: const <DateTime>[], error: response.error ?? kSlotsError);
    } catch (e) {
      // The message is deliberately NOT `e.toString()`: a socket exception is
      // not a sentence a client should read, and §14 wants copy, not a stack.
      return (slots: const <DateTime>[], error: kSlotsError);
    }
  }
}
