import '../../core/constants/app_constants.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/availability.dart';
import '../../models/payment.dart';
import '../../models/service.dart';
import '../interfaces/pro_service_interface.dart';
import 'mock_data.dart';

class MockProService implements ProServiceInterface {
  @override
  Future<ApiResponse<DashboardStats>> getDashboardStats(
      String providerId) async {
    await Future.delayed(AppConstants.mockDelay);

    final appointments =
        MockData.appointments.where((a) => a.providerId == providerId).toList();

    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final todayAppointments = appointments.where((a) {
      final appDate = a.appointmentDate;
      return appDate.isAfter(todayStart) && appDate.isBefore(todayEnd);
    }).length;

    final pendingRequests =
        appointments.where((a) => a.status == AppointmentStatus.pending).length;

    final todayRevenue = appointments.where((a) {
      final appDate = a.appointmentDate;
      return appDate.isAfter(todayStart) &&
          appDate.isBefore(todayEnd) &&
          a.status == AppointmentStatus.confirmed;
    }).fold<double>(0, (sum, a) => sum + a.totalPrice);

    final weekStart = todayStart.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final weekRevenue = appointments.where((a) {
      final appDate = a.appointmentDate;
      return appDate.isAfter(weekStart) &&
          appDate.isBefore(weekEnd) &&
          a.status == AppointmentStatus.confirmed;
    }).fold<double>(0, (sum, a) => sum + a.totalPrice);

    final monthStart = DateTime(today.year, today.month, 1);
    final monthEnd = DateTime(today.year, today.month + 1, 1);
    final monthRevenue = appointments.where((a) {
      final appDate = a.appointmentDate;
      return appDate.isAfter(monthStart) &&
          appDate.isBefore(monthEnd) &&
          a.status == AppointmentStatus.confirmed;
    }).fold<double>(0, (sum, a) => sum + a.totalPrice);

    final stats = DashboardStats(
      todayAppointments: todayAppointments,
      pendingRequests: pendingRequests,
      todayRevenue: todayRevenue,
      weekRevenue: weekRevenue,
      monthRevenue: monthRevenue,
      totalAppointments: appointments.length,
    );

    return ApiResponse.success(stats);
  }

  @override
  Future<ApiResponse<List<Appointment>>> getProviderAppointments(
    String providerId, {
    AppointmentStatus? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    var appointments =
        MockData.appointments.where((a) => a.providerId == providerId).toList();

    if (status != null) {
      appointments = appointments.where((a) => a.status == status).toList();
    }

    if (startDate != null) {
      appointments = appointments
          .where((a) =>
              a.appointmentDate.isAfter(startDate) ||
              a.appointmentDate.isAtSameMomentAs(startDate))
          .toList();
    }

    if (endDate != null) {
      appointments = appointments
          .where((a) =>
              a.appointmentDate.isBefore(endDate) ||
              a.appointmentDate.isAtSameMomentAs(endDate))
          .toList();
    }

    appointments.sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));

    return ApiResponse.success(appointments);
  }

  @override
  Future<ApiResponse<bool>> acceptAppointment(String appointmentId) async {
    await Future.delayed(AppConstants.mockDelay);
    // In real implementation, update appointment status
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> rejectAppointment(
      String appointmentId, String? reason) async {
    await Future.delayed(AppConstants.mockDelay);
    // In real implementation, update appointment status
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> markAppointmentComplete(
      String appointmentId) async {
    await Future.delayed(AppConstants.mockDelay);
    // In real implementation, update appointment status
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> rescheduleAppointment(
    String appointmentId,
    DateTime newDateTime,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    // In real implementation, update appointment date
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<List<Service>>> getProviderServices(
      String providerId) async {
    await Future.delayed(AppConstants.mockDelay);
    final services = MockData.getServicesForProvider(providerId);
    return ApiResponse.success(services);
  }

  @override
  Future<ApiResponse<Service>> createService(
    String providerId,
    Map<String, dynamic> serviceData,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    // In real implementation, create service
    final service = Service(
      id: 'service_${DateTime.now().millisecondsSinceEpoch}',
      name: serviceData['name'] as String,
      description: serviceData['description'] as String? ?? '',
      price: (serviceData['price'] as num).toDouble(),
      durationMinutes: serviceData['durationMinutes'] as int,
      providerId: providerId,
    );
    return ApiResponse.success(service);
  }

  @override
  Future<ApiResponse<Service>> updateService(
    String serviceId,
    Map<String, dynamic> serviceData,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    // In real implementation, update service
    final service = Service(
      id: serviceId,
      name: serviceData['name'] as String,
      description: serviceData['description'] as String? ?? '',
      price: (serviceData['price'] as num).toDouble(),
      durationMinutes: serviceData['durationMinutes'] as int,
      providerId: serviceData['providerId'] as String,
    );
    return ApiResponse.success(service);
  }

  @override
  Future<ApiResponse<bool>> deleteService(String serviceId) async {
    await Future.delayed(AppConstants.mockDelay);
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> toggleServiceAvailability(String serviceId) async {
    await Future.delayed(AppConstants.mockDelay);
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<Availability>> getProviderAvailability(
      String providerId) async {
    await Future.delayed(AppConstants.mockDelay);
    final provider = MockData.providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => MockData.providers.first,
    );
    return ApiResponse.success(provider.availability);
  }

  @override
  Future<ApiResponse<Availability>> updateAvailability(
    String providerId,
    Availability availability,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    return ApiResponse.success(availability);
  }

  @override
  Future<ApiResponse<EarningsData>> getEarnings(
    String providerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    var appointments =
        MockData.appointments.where((a) => a.providerId == providerId).toList();

    if (startDate != null) {
      appointments = appointments
          .where((a) =>
              a.appointmentDate.isAfter(startDate) ||
              a.appointmentDate.isAtSameMomentAs(startDate))
          .toList();
    }

    if (endDate != null) {
      appointments = appointments
          .where((a) =>
              a.appointmentDate.isBefore(endDate) ||
              a.appointmentDate.isAtSameMomentAs(endDate))
          .toList();
    }

    final totalEarnings = appointments
        .where((a) => a.status == AppointmentStatus.completed)
        .fold<double>(0, (sum, a) => sum + a.totalPrice);

    final transactions = appointments
        .where((a) => a.status == AppointmentStatus.completed)
        .map((a) => EarningsTransaction(
              id: 'transaction_${a.id}',
              appointmentId: a.id,
              amount: a.totalPrice,
              date: a.appointmentDate,
              status: 'completed',
            ))
        .toList();

    return ApiResponse.success(EarningsData(
      totalEarnings: totalEarnings,
      transactions: transactions,
    ));
  }

  @override
  Future<ApiResponse<DepositPolicy>> getDepositPolicy(String providerId) async {
    await Future.delayed(AppConstants.mockDelay);
    final provider = MockData.providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => MockData.providers.first,
    );
    return ApiResponse.success(
      DepositPolicy(
        depositRequired: provider.depositRequired,
        depositPercentage: provider.depositPercentage,
      ),
    );
  }

  @override
  Future<ApiResponse<DepositPolicy>> updateDepositPolicy(
    String providerId, {
    required bool depositRequired,
    required double depositPercentage,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    final index = MockData.providers.indexWhere((p) => p.id == providerId);
    if (index == -1) {
      return ApiResponse.error('Prestataire introuvable');
    }
    MockData.providers[index] = MockData.providers[index].copyWith(
      depositRequired: depositRequired,
      depositPercentage: depositPercentage,
    );
    return ApiResponse.success(
      DepositPolicy(
        depositRequired: depositRequired,
        depositPercentage: depositPercentage,
      ),
    );
  }
}
