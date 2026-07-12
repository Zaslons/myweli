import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/availability.dart';
import '../../models/before_after_pair.dart';
import '../../models/journal_day.dart';
import '../../models/payment.dart';
import '../../models/pro_membership.dart';
import '../../models/provider.dart';
import '../../models/provider_user.dart';
import '../../models/salon_membership_info.dart';
import '../../models/service.dart';

// Dashboard stats model. The revenue fields are NULLABLE: the server
// field-gates them away for callers without `finances.view` (module `access`
// R1/R4) — absence is a valid state, not an error.
class DashboardStats {
  final int todayAppointments;
  final int pendingRequests;
  final double? todayRevenue;
  final double? weekRevenue;
  final double? monthRevenue;
  final int totalAppointments;

  const DashboardStats({
    required this.todayAppointments,
    required this.pendingRequests,
    required this.totalAppointments,
    this.todayRevenue,
    this.weekRevenue,
    this.monthRevenue,
  });

  bool get hasRevenue => todayRevenue != null;

  factory DashboardStats.fromJson(Map<String, dynamic> json) => DashboardStats(
        todayAppointments: (json['todayAppointments'] as num).toInt(),
        pendingRequests: (json['pendingRequests'] as num).toInt(),
        todayRevenue: (json['todayRevenue'] as num?)?.toDouble(),
        weekRevenue: (json['weekRevenue'] as num?)?.toDouble(),
        monthRevenue: (json['monthRevenue'] as num?)?.toDouble(),
        totalAppointments: (json['totalAppointments'] as num).toInt(),
      );
}

/// GET /me/provider (team access R4b): the acting salon + the caller's
/// membership — how the app learns WHO it is inside the salon.
class MyProviderInfo {
  const MyProviderInfo({required this.salon, required this.membership});

  final Provider salon;
  final ProMembership membership;
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
  /// The acting identity (team access R4b): the salon + the caller's
  /// membership from GET /me/provider. A revoked member surfaces the
  /// machine code `not_a_member`. R6: [salonId] selects among the caller's
  /// ACTIVE memberships — an invalid selection surfaces `forbidden` (a
  /// per-salon denial, NEVER the sign-out signal).
  Future<ApiResponse<MyProviderInfo>> getMyProvider({String? salonId});

  /// « Mes salons » (module `access` R6 — GET /me/salons): every salon the
  /// account belongs to (owned first) + the server-computed add gate.
  Future<ApiResponse<MySalonsResult>> getMySalons();

  /// « Ajouter un salon » (R6 — POST /me/salons, Réseau-gated): creates an
  /// additional DRAFT salon in its own free SETUP state. Machine codes:
  /// `reseau_required` (no live Réseau offer on an owned salon) ·
  /// `salon_limit` (cap reached).
  Future<ApiResponse<SalonMembershipInfo>> addSalon({
    required String businessName,
    required BusinessType businessType,
    String? phoneNumber,
    String? address,
  });

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

  /// « Client arrivé » — confirmed → arrived (module journal J1b). Same-day,
  /// confirmed-only, idempotent (guarded server-side).
  Future<ApiResponse<bool>> markArrived(String appointmentId);

  /// Delete the signed-in provider ACCOUNT (audit 11.5 — AUTH-004 for pros).
  /// Self-scoped server-side; future pending/confirmed bookings → the
  /// `future_bookings` error code (settle the agenda first). The salon is
  /// unpublished, every session dies.
  Future<ApiResponse<void>> deleteProviderAccount();

  /// Take the salon live (docs/design/pro-salon-lifecycle.md): flips the
  /// DRAFT listing to active once the server-side go-live gate passes.
  /// Incomplete → error code `incomplete`.
  Future<ApiResponse<bool>> publishSalon(String providerId);

  /// Update the salon's editable public profile (pro-salon-lifecycle L2 —
  /// the app twin of web 7.3e-i): name/description/address/city/commune/
  /// phone/whatsapp/category + the PAIRED map pin (latitude+longitude).
  /// Returns the updated listing.
  Future<ApiResponse<Provider>> updateSalonProfile(
    String providerId,
    Map<String, dynamic> changes,
  );

  /// The salon's whole day as one payload (module journal J1) — hours,
  /// artists, and every booking (all statuses) for [date].
  Future<ApiResponse<JournalDay>> getJournalDay(
    String providerId,
    DateTime date,
  );
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
    String? artistId,
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
