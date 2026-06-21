import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/availability.dart';
import '../../models/payment.dart';
import '../../models/service.dart';

// Dashboard stats model
class DashboardStats {
  final int todayAppointments;
  final int pendingRequests;
  final double todayRevenue;
  final double weekRevenue;
  final double monthRevenue;
  final int totalAppointments;

  const DashboardStats({
    required this.todayAppointments,
    required this.pendingRequests,
    required this.todayRevenue,
    required this.weekRevenue,
    required this.monthRevenue,
    required this.totalAppointments,
  });
}

// Earnings data model
class EarningsData {
  final double totalEarnings;
  final List<EarningsTransaction> transactions;

  const EarningsData({
    required this.totalEarnings,
    required this.transactions,
  });
}

class EarningsTransaction {
  final String id;
  final String appointmentId;
  final double amount;
  final DateTime date;
  final String status; // 'pending', 'completed', 'cancelled'

  const EarningsTransaction({
    required this.id,
    required this.appointmentId,
    required this.amount,
    required this.date,
    required this.status,
  });
}

abstract class ProServiceInterface {
  // Dashboard
  Future<ApiResponse<DashboardStats>> getDashboardStats(String providerId);

  // Appointments
  Future<ApiResponse<List<Appointment>>> getProviderAppointments(
    String providerId, {
    AppointmentStatus? status,
    DateTime? startDate,
    DateTime? endDate,
  });
  Future<ApiResponse<bool>> acceptAppointment(String appointmentId);
  Future<ApiResponse<bool>> rejectAppointment(
      String appointmentId, String? reason);
  Future<ApiResponse<bool>> markAppointmentComplete(String appointmentId);
  Future<ApiResponse<bool>> rescheduleAppointment(
    String appointmentId,
    DateTime newDateTime,
  );

  // Services
  Future<ApiResponse<List<Service>>> getProviderServices(String providerId);
  Future<ApiResponse<Service>> createService(
      String providerId, Map<String, dynamic> serviceData);
  Future<ApiResponse<Service>> updateService(
      String serviceId, Map<String, dynamic> serviceData);
  Future<ApiResponse<bool>> deleteService(String serviceId);
  Future<ApiResponse<bool>> toggleServiceAvailability(String serviceId);

  // Availability
  Future<ApiResponse<Availability>> getProviderAvailability(String providerId);
  Future<ApiResponse<Availability>> updateAvailability(
    String providerId,
    Availability availability,
  );

  // Earnings
  Future<ApiResponse<EarningsData>> getEarnings(
    String providerId, {
    DateTime? startDate,
    DateTime? endDate,
  });

  // Deposit policy
  Future<ApiResponse<DepositPolicy>> getDepositPolicy(String providerId);
  Future<ApiResponse<DepositPolicy>> updateDepositPolicy(
    String providerId, {
    required bool depositRequired,
    required double depositPercentage,
  });
}
