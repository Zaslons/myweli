import 'package:flutter/foundation.dart';

import '../core/access/account_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/app_clock.dart';
import '../core/utils/salon_id.dart';
import '../core/utils/submission_key.dart';
import '../core/utils/visit_history.dart' as vh;
import '../models/api_response.dart';
import '../models/appointment.dart';
import '../services/interfaces/appointment_service_interface.dart';

/// What the funnel says when it could not ASK the salon — as opposed to when
/// the salon answered « rien de libre ». French, and a sentence rather than an
/// exception's `toString()` (§14).
const String kSlotsError =
    'Impossible de charger les créneaux. Vérifiez votre connexion.';

class AppointmentProvider extends ChangeNotifier implements AccountScoped {
  final AppointmentServiceInterface _appointmentService =
      serviceLocator.appointmentService;

  /// Whose bookings these are — moved by [resetForAccountChange]. Each read
  /// and write takes it before it awaits and writes nothing when it moved
  /// meanwhile: the answer is the previous account's
  /// (docs/design/consumer-account-scope.md §2.3).
  int _account = 0;

  /// The account changed (B9.13): « Mes rendez-vous », the home strip, the
  /// detail and « Donner mon avis » all read this store, and it lives for the
  /// whole app.
  @override
  void resetForAccountChange() {
    _account++;
    _appointments = [];
    _selectedAppointment = null;
    _selectedId = null;
    _isLoading = false;
    _error = null;
    _errorCode = null;
    _listError = null;
    // The same form under the next account is another submission.
    _bookingKey.settle();
    notifyListeners();
  }

  /// One Idempotency-Key per booking submission — the same on « Réessayer »,
  /// a new one once the booking changed or after it succeeded
  /// (docs/design/write-idempotency.md §4). Held here, not by the screen, so
  /// it survives the sheet closing and opening again on the same booking.
  final SubmissionKey _bookingKey = SubmissionKey();

  List<Appointment> _appointments = [];
  Appointment? _selectedAppointment;
  String? _selectedId;
  bool _isLoading = false;
  String? _error;

  /// The machine code behind [_error], kept because a sentence alone cannot
  /// say whether the refusal has a way out (§21 row 82). Same shape as
  /// `ProTeamProvider._inviteErrorCode`, which the invite sheet reads to
  /// pick its `offer_required` sentence.
  String? _errorCode;

  /// The list's own failure. [error] belongs to every operation here — a
  /// cancel, a deposit, a booking — so « Mes rendez-vous » reading it would
  /// show « Erreur lors de l’annulation » as the reason its list is empty
  /// (B9.8). It had no error state at all: a failed load said « Aucun
  /// rendez-vous ».
  String? _listError;

  List<Appointment> get appointments => _appointments;
  Appointment? get selectedAppointment => _selectedAppointment;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get errorCode => _errorCode;
  String? get listError => _listError;

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

  bool hasCompletedBookingAt(SalonId providerId, String userId) =>
      latestCompletedAppointmentId(providerId, userId) != null;

  /// The most recent completed appointment the user had at [providerId] — the
  /// visit a "leave a review" CTA reviews. Null if there is none.
  ///
  /// Returns the whole booking, not just its id, because the review sheet
  /// shows WHO served that visit and the answer rides the appointment now
  /// (Decision C) rather than being looked up in the salon's roster.
  Appointment? latestCompletedAppointment(SalonId providerId, String userId) {
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
    return completed.isEmpty ? null : completed.first;
  }

  String? latestCompletedAppointmentId(SalonId providerId, String userId) =>
      latestCompletedAppointment(providerId, userId)?.id;

  Future<void> loadAppointments({AppointmentStatus? status}) async {
    final account = _account;
    _isLoading = true;
    _error = null;
    notifyListeners();

    List<Appointment>? loaded;
    String? error;
    try {
      final response = await _appointmentService.getUserAppointments(
        status: status,
      );
      if (response.success && response.data != null) {
        loaded = response.data!;
      } else {
        error = response.error ?? kGenericErrorMessage;
      }
    } catch (e) {
      error = kGenericErrorMessage;
    }
    if (account != _account) return;
    _appointments = loaded ?? [];
    _error = error;
    _listError = error;
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> bookAppointment({
    required SalonId providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? artistId,
    String? notes,
    double depositAmount = 0,
    String? depositScreenshotUrl,
  }) async {
    final account = _account;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();

    ApiResponse<Appointment>? response;
    try {
      final key = _bookingKey.forForm({
        'providerId': providerId,
        'serviceIds': serviceIds,
        'appointmentDateTime': appointmentDateTime.toUtc().toIso8601String(),
        'artistId': artistId,
        'notes': notes,
        'depositScreenshotUrl': depositScreenshotUrl,
      });
      response = await _appointmentService.bookAppointment(
        providerId: providerId,
        serviceIds: serviceIds,
        appointmentDateTime: appointmentDateTime,
        artistId: artistId,
        notes: notes,
        depositAmount: depositAmount,
        depositScreenshotUrl: depositScreenshotUrl,
        idempotencyKey: key,
      );
    } catch (e) {
      response = null;
    }
    final made = response != null && response.success && response.data != null;
    // Made on the previous account, which is right — and not added to the
    // next one's list.
    if (account != _account) return made;
    if (made) {
      _bookingKey.settle();
      _appointments.add(response.data!);
      _error = null;
      _errorCode = null;
    } else if (response != null) {
      _error = response.error ?? 'Erreur lors de la réservation';
      _errorCode = response.code;
    } else {
      _error = kGenericErrorMessage;
      _errorCode = null;
    }
    _isLoading = false;
    notifyListeners();
    return made;
  }

  /// Pay-later: attach a deposit screenshot (already uploaded → [screenshotKey])
  /// to an existing pending booking, then refresh it in the list.
  Future<bool> submitDeposit({
    required String appointmentId,
    required String screenshotKey,
  }) async {
    final account = _account;
    _isLoading = true;
    _error = null;
    notifyListeners();
    ApiResponse<Appointment>? response;
    try {
      response = await _appointmentService.submitDeposit(
        appointmentId: appointmentId,
        screenshotKey: screenshotKey,
      );
    } catch (e) {
      response = null;
    }
    final sent = response != null && response.success && response.data != null;
    if (account != _account) return sent;
    if (sent) {
      final i = _appointments.indexWhere((a) => a.id == appointmentId);
      if (i != -1) _appointments[i] = response.data!;
      _error = null;
    } else {
      _error = response == null
          ? kGenericErrorMessage
          : response.error ?? 'Erreur lors de l’envoi de l’acompte';
    }
    _isLoading = false;
    notifyListeners();
    return sent;
  }

  Future<void> loadAppointmentById(String id) async {
    // The selection is app-wide and outlives the detail screen: kept, the way
    // to B showed A's details — and A's actions — until B answered (B9.8).
    if (_selectedAppointment?.id != id) _selectedAppointment = null;
    final account = _account;
    _selectedId = id;
    _isLoading = true;
    _error = null;
    notifyListeners();

    Appointment? found;
    String? error;
    try {
      final response = await _appointmentService.getAppointmentById(id);
      if (response.success && response.data != null) {
        found = response.data;
      } else {
        error = response.error ?? 'Rendez-vous non trouvé';
      }
    } catch (e) {
      error = kGenericErrorMessage;
    }
    // Another booking was opened while this read was out: its answer is no
    // longer anybody's (`ProviderProvider.loadProviderById`'s guard) — nor is
    // it when the account changed, even for the same id: a push of A's
    // replayed under B opens A's id (consumer-account-scope.md §9).
    if (_selectedId != id || account != _account) return;
    _selectedAppointment = found;
    _error = error;
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> cancelAppointment(String id) async {
    final account = _account;
    _isLoading = true;
    _error = null;
    notifyListeners();

    ApiResponse<void>? response;
    try {
      response = await _appointmentService.cancelAppointment(id);
    } catch (e) {
      response = null;
    }
    final cancelled = response != null && response.success;
    if (account != _account) return cancelled;
    if (cancelled) {
      final index = _appointments.indexWhere((a) => a.id == id);
      if (index != -1) {
        _appointments[index] = _appointments[index].copyWith(
          status: AppointmentStatus.cancelled,
        );
      }
      _error = null;
    } else {
      _error = response == null
          ? kGenericErrorMessage
          : response.error ?? 'Erreur lors de l’annulation';
    }
    _isLoading = false;
    notifyListeners();
    return cancelled;
  }

  Future<bool> rescheduleAppointment({
    required String id,
    required DateTime newDateTime,
  }) async {
    final account = _account;
    _isLoading = true;
    _error = null;
    notifyListeners();

    ApiResponse<Appointment>? response;
    try {
      response = await _appointmentService.rescheduleAppointment(
        id: id,
        newDateTime: newDateTime,
      );
    } catch (e) {
      response = null;
    }
    final moved = response != null && response.success && response.data != null;
    if (account != _account) return moved;
    if (moved) {
      final updated = response.data!;
      final index = _appointments.indexWhere((a) => a.id == id);
      if (index != -1) {
        _appointments[index] = updated;
      }
      if (_selectedAppointment?.id == id) {
        _selectedAppointment = updated;
      }
      _error = null;
    } else {
      _error = response == null
          ? kGenericErrorMessage
          : response.error ?? 'Erreur lors du report';
    }
    _isLoading = false;
    notifyListeners();
    return moved;
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
  Future<({List<DateTime> slots, String? error, String? code})>
  getAvailableTimeSlots({
    required SalonId providerId,
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
        return (slots: response.data!, error: null, code: null);
      }
      return (
        slots: const <DateTime>[],
        error: response.error ?? kSlotsError,
        code: response.code,
      );
    } catch (e) {
      // The message is deliberately NOT `e.toString()`: a socket exception is
      // not a sentence a client should read, and §14 wants copy, not a stack.
      return (slots: const <DateTime>[], error: kSlotsError, code: 'network');
    }
  }
}
