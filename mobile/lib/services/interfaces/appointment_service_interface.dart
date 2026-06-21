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
  });
  Future<ApiResponse<List<Appointment>>> getUserAppointments({
    AppointmentStatus? status,
  });
  Future<ApiResponse<Appointment>> getAppointmentById(String id);
  Future<ApiResponse<void>> cancelAppointment(String id);

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
