import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/availability.dart';
import '../../models/before_after_pair.dart';
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

  factory DashboardStats.fromJson(Map<String, dynamic> json) => DashboardStats(
        todayAppointments: (json['todayAppointments'] as num).toInt(),
        pendingRequests: (json['pendingRequests'] as num).toInt(),
        todayRevenue: (json['todayRevenue'] as num).toDouble(),
        weekRevenue: (json['weekRevenue'] as num).toDouble(),
        monthRevenue: (json['monthRevenue'] as num).toDouble(),
        totalAppointments: (json['totalAppointments'] as num).toInt(),
      );
}

// Earnings data model
class EarningsData {
  final double totalEarnings;
  final List<EarningsTransaction> transactions;

  const EarningsData({
    required this.totalEarnings,
    required this.transactions,
  });

  factory EarningsData.fromJson(Map<String, dynamic> json) => EarningsData(
        totalEarnings: (json['totalEarnings'] as num).toDouble(),
        transactions: ((json['transactions'] as List?) ?? const [])
            .map((e) => EarningsTransaction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
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

  factory EarningsTransaction.fromJson(Map<String, dynamic> json) =>
      EarningsTransaction(
        id: json['id'] as String,
        appointmentId: json['appointmentId'] as String,
        amount: (json['amount'] as num).toDouble(),
        date: DateTime.parse(json['date'] as String),
        status: json['status'] as String,
      );
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
  Future<ApiResponse<bool>> markNoShow(String appointmentId);
  Future<ApiResponse<bool>> rescheduleAppointment(
    String appointmentId,
    DateTime newDateTime,
  );

  /// Create a walk-in / phone booking entered by the pro (no app account).
  /// Confirmed immediately, no online deposit. [sendSmsInvite] requests a
  /// confirmation SMS with an app link (handled by the notifications backend).
  Future<ApiResponse<Appointment>> createManualBooking({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? clientName,
    String? clientPhone,
    String? notes,
    bool sendSmsInvite = false,
  });

  // Services
  Future<ApiResponse<List<Service>>> getProviderServices(String providerId);
  Future<ApiResponse<Service>> createService(
      String providerId, Map<String, dynamic> serviceData);
  Future<ApiResponse<Service>> updateService(
      String serviceId, Map<String, dynamic> serviceData);
  Future<ApiResponse<bool>> deleteService(String serviceId);

  /// Enable/disable a service (`active`). A disabled service is hidden from
  /// booking and rejected server-side.
  Future<ApiResponse<bool>> setServiceActive(String serviceId, bool active);

  // Gallery photos
  Future<ApiResponse<List<String>>> getGalleryPhotos(String providerId);
  Future<ApiResponse<List<String>>> updateGalleryPhotos(
    String providerId,
    List<String> imageUrls,
  );

  // Before/after showcase (FR-DISC-006)
  Future<ApiResponse<List<BeforeAfterPair>>> getBeforeAfters(String providerId);
  Future<ApiResponse<List<BeforeAfterPair>>> updateBeforeAfters(
    String providerId,
    List<BeforeAfterPair> pairs,
  );

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
    required int cancellationWindowHours,
    MobileMoneyOperator? mobileMoneyOperator,
    String? mobileMoneyNumber,
  });

  /// A short-lived signed URL to view a booking's deposit screenshot (the salon
  /// is authorized to see proof for its own bookings).
  Future<ApiResponse<String>> depositScreenshotUrl(String appointmentId);
}
