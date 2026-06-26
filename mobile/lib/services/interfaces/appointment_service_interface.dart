import '../../models/api_response.dart';
import '../../models/appointment.dart';

abstract class AppointmentServiceInterface {
  Future<ApiResponse<Appointment>> bookAppointment({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? artistId,
    String? notes,
    double depositAmount = 0,
    String? depositScreenshotUrl,
  });
  Future<ApiResponse<List<Appointment>>> getUserAppointments({
    AppointmentStatus? status,
  });
  Future<ApiResponse<Appointment>> getAppointmentById(String id);
  Future<ApiResponse<void>> cancelAppointment(String id);

  /// Upload a deposit-payment screenshot to **private** storage; returns the
  /// opaque object key to attach to a booking (no public URL).
  Future<ApiResponse<String>> uploadDepositScreenshot({
    required String source,
  });

  /// Attach/replace the deposit screenshot on the caller's own pending booking
  /// (pay-later). Returns the updated appointment.
  Future<ApiResponse<Appointment>> submitDeposit({
    required String appointmentId,
    required String screenshotKey,
  });

  /// A short-lived signed URL to view this booking's deposit screenshot.
  Future<ApiResponse<String>> depositScreenshotUrl({
    required String appointmentId,
  });

  /// Move an existing appointment to a new date/time. The deposit and balance
  /// carry over unchanged.
  Future<ApiResponse<Appointment>> rescheduleAppointment({
    required String id,
    required DateTime newDateTime,
  });
  Future<ApiResponse<List<DateTime>>> getAvailableTimeSlots({
    required String providerId,
    required DateTime date,
    List<String>? serviceIds,
    String? artistId,
    int? durationMinutes,
  });
}
