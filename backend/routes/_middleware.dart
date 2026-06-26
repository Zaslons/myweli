import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_auth_repository.dart';
import 'package:myweli_backend/src/admin/admin_kyc_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_lifecycle_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/pro_appointment_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/dependencies.dart';
import 'package:myweli_backend/src/deposit_service.dart';
import 'package:myweli_backend/src/favorites_service.dart';
import 'package:myweli_backend/src/kyc_service.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/provider_dashboard_service.dart';
import 'package:myweli_backend/src/provider_earnings_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/reviews_service.dart';
import 'package:myweli_backend/src/upload_signing_service.dart';

/// Provides the process-wide singletons into every request's context, so
/// handlers share state and the repository impls can be swapped in one place
/// (the composition root) without touching routes.
Handler middleware(Handler handler) {
  return handler
      .use(provider<AuthRepository>((_) => authRepository))
      .use(provider<ProviderAuthRepository>((_) => providerAuthRepository))
      .use(provider<AppointmentRepository>((_) => appointmentRepository))
      .use(provider<BookingService>((_) => bookingService))
      .use(provider<SlotService>((_) => slotService))
      .use(
        provider<AppointmentLifecycleService>(
          (_) => appointmentLifecycleService,
        ),
      )
      .use(provider<ProAppointmentService>((_) => proAppointmentService))
      .use(provider<ProviderCatalogService>((_) => providerCatalogService))
      .use(provider<ProviderDashboardService>((_) => providerDashboardService))
      .use(provider<ProviderEarningsService>((_) => providerEarningsService))
      .use(provider<UploadSigningService>((_) => uploadSigningService))
      .use(provider<FavoritesService>((_) => favoritesService))
      .use(provider<KycService>((_) => kycService))
      .use(provider<DepositService>((_) => depositService))
      .use(provider<AdminAuthRepository>((_) => adminAuthRepository))
      .use(provider<AuditLogRepository>((_) => auditLogRepository))
      .use(provider<AdminKycService>((_) => adminKycService))
      .use(provider<ReviewsRepository>((_) => reviewsRepository))
      .use(provider<ReviewsService>((_) => reviewsService))
      .use(provider<TokenService>((_) => tokenService))
      .use(provider<ProvidersRepository>((_) => providersRepository));
}
