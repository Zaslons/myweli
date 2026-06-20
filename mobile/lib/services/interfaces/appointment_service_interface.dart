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
  Future<ApiResponse<List<DateTime>>> getAvailableTimeSlots({
    required String providerId,
    required DateTime date,
    List<String>? serviceIds,
    String? artistId,
    int? durationMinutes,
  });
}
