import 'package:flutter/foundation.dart';

import '../core/access/pro_access_guard.dart';
import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/submission_key.dart';
import '../models/appointment.dart';
import '../services/interfaces/pro_service_interface.dart';

class ProAppointmentProvider extends ChangeNotifier
    implements HearsBookingChanges {
  final ProServiceInterface _proService = serviceLocator.proService;

  /// One Idempotency-Key per manual-booking submission
  /// (docs/design/write-idempotency.md §4).
  final SubmissionKey _manualBookingKey = SubmissionKey();

  List<Appointment> _appointments = [];
  bool _isLoading = false;
  String? _error;

  /// The machine code behind [_error] — row 82. `ProTeamProvider` does the
  /// same for the offer gates; without it a screen can render the sentence but
  /// not the action that goes with it.
  String? _errorCode;

  List<Appointment> get appointments => _appointments;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get errorCode => _errorCode;

  /// What [_appointments] was last asked for — « En attente » asks for one
  /// status, « Aujourd’hui » for one day, « À venir » for everything from now.
  ///
  /// Kept so that a booking created afterwards joins the list only when the
  /// list would have contained it. It used to be appended whatever the list
  /// was, and a « Confirmé » booking appeared under « En attente »
  /// (docs/design/pro-journal-shows-new-booking.md §2.6).
  AppointmentStatus? _loadedStatus;
  DateTime? _loadedFrom;
  DateTime? _loadedTo;

  /// The same test `getProviderAppointments` applies: both bounds inclusive.
  /// The salon of the loaded list — the announcement of a change names it
  /// when the row is not in the list.
  String? _loadedProviderId;

  bool _belongsToLoadedList(Appointment a) {
    final status = _loadedStatus;
    final from = _loadedFrom;
    final to = _loadedTo;
    if (status != null && a.status != status) return false;
    if (from != null && a.appointmentDate.isBefore(from)) return false;
    if (to != null && a.appointmentDate.isAfter(to)) return false;
    return true;
  }

  Future<void> loadAppointments(
    String providerId, {
    AppointmentStatus? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _loadedProviderId = providerId;
    _loadedStatus = status;
    _loadedFrom = startDate;
    _loadedTo = endDate;
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
        _announce(appointmentId, BookingChangeKind.accepted);
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de l’acceptation';
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
      final response = await _proService.rejectAppointment(
        appointmentId,
        reason,
      );
      if (response.success) {
        final index = _appointments.indexWhere((a) => a.id == appointmentId);
        if (index != -1) {
          _appointments[index] = _appointments[index].copyWith(
            status: AppointmentStatus.cancelled,
          );
        }
        _error = null;
        notifyListeners();
        _announce(appointmentId, BookingChangeKind.rejected);
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
        _announce(appointmentId, BookingChangeKind.completed);
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
        _announce(appointmentId, BookingChangeKind.noShow);
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
      final response = await _proService.rescheduleAppointment(
        appointmentId,
        newDateTime,
      );
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
      final key = _manualBookingKey.forForm({
        'providerId': providerId,
        'serviceIds': serviceIds,
        'appointmentDateTime': appointmentDateTime.toUtc().toIso8601String(),
        'clientName': clientName,
        'clientPhone': clientPhone,
        'notes': notes,
        'artistId': artistId,
        'sendSmsInvite': sendSmsInvite,
      });
      final response = await _proService.createManualBooking(
        providerId: providerId,
        serviceIds: serviceIds,
        appointmentDateTime: appointmentDateTime,
        clientName: clientName,
        clientPhone: clientPhone,
        notes: notes,
        artistId: artistId,
        sendSmsInvite: sendSmsInvite,
        idempotencyKey: key,
      );
      if (response.success && response.data != null) {
        _manualBookingKey.settle();
        final created = response.data!;
        if (_belongsToLoadedList(created)) {
          _appointments = [..._appointments, created]
            ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
        }
        _error = null;
        _errorCode = null;
        // The ONE announcement of « a booking was created »: « Ma journée »,
        // the home figures and the client card each keep their own copy of
        // the salon's bookings and are still on screen, or still cached, under
        // the form. Made here, before the form closes, so the day is already
        // right when the form slides away — and so that no opener of the form
        // has to remember whom to refresh
        // (docs/design/pro-journal-shows-new-booking.md §5).
        ProSalonScope.bookingCreated(created);
        return true;
      }
      _error = response.error ?? 'Erreur lors de la création';
      _errorCode = response.code;
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
  /// The detail's four writes, announced once the server accepted them, so
  /// « Ma journée », « Accueil » and the client card follow at once
  /// (docs/design/app-pro-home-journal-fresh.md §2.1). This list already
  /// carries the change; it is not told again.
  void _announce(String appointmentId, BookingChangeKind kind) {
    final row = _appointments.where((a) => a.id == appointmentId).firstOrNull;
    final providerId = row?.providerId ?? _loadedProviderId;
    if (providerId == null) return;
    ProSalonScope.bookingChanged(
      BookingChange(
        appointmentId: appointmentId,
        providerId: providerId,
        kind: kind,
        clientPhone: row?.clientPhone,
      ),
      except: this,
    );
  }

  /// A change made elsewhere (« Ma journée »): the row follows, with no
  /// reload. A row its new status takes out of a filtered list leaves it.
  @override
  void bookingChanged(BookingChange change) {
    final i = _appointments.indexWhere((a) => a.id == change.appointmentId);
    if (i == -1) return;
    final current = _appointments[i];
    if (current.providerId != change.providerId) return;
    final after = change.applyTo(current);
    final rows = [..._appointments];
    if (_belongsToLoadedList(after)) {
      rows[i] = after;
    } else {
      rows.removeAt(i);
    }
    _appointments = rows;
    notifyListeners();
  }

  @override
  void resetForSalonSwitch() {
    _appointments = [];
    _loadedProviderId = null;
    _loadedStatus = null;
    _loadedFrom = null;
    _loadedTo = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
