import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_auth_repository.dart';
import 'package:myweli_backend/src/admin/admin_kyc_service.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/admin/admin_user_service.dart';
import 'package:myweli_backend/src/admin/analytics_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/admin/dispute_service.dart';
import 'package:myweli_backend/src/admin/moderation_service.dart';
import 'package:myweli_backend/src/appointments/appointment_lifecycle_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/journal_service.dart';
import 'package:myweli_backend/src/appointments/pro_appointment_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/cors.dart';
import 'package:myweli_backend/src/dependencies.dart';
import 'package:myweli_backend/src/deposit_service.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/favorites_service.dart';
import 'package:myweli_backend/src/kyc_service.dart';
import 'package:myweli_backend/src/messaging/booking_notifier.dart';
import 'package:myweli_backend/src/messaging/messaging_service.dart';
import 'package:myweli_backend/src/messaging/reminder_scheduler.dart';
import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/provider_dashboard_service.dart';
import 'package:myweli_backend/src/provider_earnings_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/reviews_service.dart';
import 'package:myweli_backend/src/upload_signing_service.dart';

/// Provides the process-wide singletons into every request's context, so
/// handlers share state and the repository impls can be swapped in one place
/// (the composition root) without touching routes.
Handler middleware(Handler handler) {
  return handler
      .use(provider<AuthRepository>((_) => authRepository))
      .use(provider<AuthMethods>((_) => authMethods))
      .use(provider<GoogleIdTokenVerifier>((_) => googleIdTokenVerifier))
      .use(provider<AppleIdTokenVerifier>((_) => appleIdTokenVerifier))
      .use(provider<EmailProvider>((_) => emailProvider))
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
      .use(provider<ClientsService>((_) => clientsService))
      .use(provider<JournalService>((_) => journalService))
      .use(provider<ProviderCatalogService>((_) => providerCatalogService))
      .use(provider<ProviderDashboardService>((_) => providerDashboardService))
      .use(provider<ProviderEarningsService>((_) => providerEarningsService))
      .use(provider<UploadSigningService>((_) => uploadSigningService))
      .use(provider<FavoritesService>((_) => favoritesService))
      .use(provider<KycService>((_) => kycService))
      .use(provider<DepositService>((_) => depositService))
      .use(provider<MessagingService>((_) => messagingService))
      .use(provider<BookingNotifier>((_) => bookingNotifier))
      .use(provider<ReminderScheduler>((_) => reminderScheduler))
      .use(provider<PushService>((_) => pushService))
      .use(provider<NotificationsRepository>((_) => notificationsRepository))
      .use(
        provider<NotificationPrefsRepository>(
          (_) => notificationPrefsRepository,
        ),
      )
      .use(provider<AdminAuthRepository>((_) => adminAuthRepository))
      .use(provider<AuditLogRepository>((_) => auditLogRepository))
      .use(provider<AdminKycService>((_) => adminKycService))
      .use(provider<ModerationService>((_) => moderationService))
      .use(provider<AdminProviderService>((_) => adminProviderService))
      .use(provider<AdminUserService>((_) => adminUserService))
      .use(provider<DisputeService>((_) => disputeService))
      .use(provider<AnalyticsService>((_) => analyticsService))
      .use(provider<ReviewsRepository>((_) => reviewsRepository))
      .use(provider<ReviewsService>((_) => reviewsService))
      .use(provider<TokenService>((_) => tokenService))
      .use(provider<ProvidersRepository>((_) => providersRepository))
      // Outermost: browser CORS for the Next.js web app(s).
      .use(corsMiddleware(webOrigins));
}
