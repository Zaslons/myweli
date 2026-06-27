import 'dart:io';

import 'package:postgres/postgres.dart';

import 'admin/admin_auth_repository.dart';
import 'admin/admin_kyc_service.dart';
import 'admin/admin_provider_service.dart';
import 'admin/admin_user_service.dart';
import 'admin/analytics_service.dart';
import 'admin/audit_log_repository.dart';
import 'admin/dispute_service.dart';
import 'admin/disputes_repository.dart';
import 'admin/moderation_service.dart';
import 'appointments/appointment_lifecycle_service.dart';
import 'appointments/appointment_repository.dart';
import 'appointments/booking_service.dart';
import 'appointments/pro_appointment_service.dart';
import 'appointments/slot_service.dart';
import 'auth/auth_repository.dart';
import 'auth/provider_auth_repository.dart';
import 'auth/tokens.dart';
import 'db/database.dart';
import 'db/migrations.dart';
import 'db/postgres_admin_auth_repository.dart';
import 'db/postgres_appointment_repository.dart';
import 'db/postgres_audit_log_repository.dart';
import 'db/postgres_auth_repository.dart';
import 'db/postgres_device_token_repository.dart';
import 'db/postgres_disputes_repository.dart';
import 'db/postgres_favorites_repository.dart';
import 'db/postgres_messaging_outbox_repository.dart';
import 'db/postgres_messaging_prefs_repository.dart';
import 'db/postgres_notification_prefs_repository.dart';
import 'db/postgres_notifications_repository.dart';
import 'db/postgres_provider_auth_repository.dart';
import 'db/postgres_providers_repository.dart';
import 'db/postgres_reminder_log_repository.dart';
import 'db/postgres_reviews_repository.dart';
import 'deposit_service.dart';
import 'favorites_repository.dart';
import 'favorites_service.dart';
import 'kyc_service.dart';
import 'messaging/booking_notifier.dart';
import 'messaging/messaging_outbox_repository.dart';
import 'messaging/messaging_prefs_repository.dart';
import 'messaging/messaging_provider.dart';
import 'messaging/messaging_service.dart';
import 'messaging/reminder_log_repository.dart';
import 'messaging/reminder_scheduler.dart';
import 'messaging/twilio_messaging_provider.dart';
import 'notifications/notification_prefs_repository.dart';
import 'notifications/notifications_repository.dart';
import 'provider_catalog_service.dart';
import 'provider_dashboard_service.dart';
import 'provider_earnings_service.dart';
import 'providers_repository.dart';
import 'push/access_token_source.dart';
import 'push/device_token_repository.dart';
import 'push/fcm_v1_push_provider.dart';
import 'push/push_provider.dart';
import 'push/push_service.dart';
import 'reviews_repository.dart';
import 'reviews_service.dart';
import 'storage/storage_service.dart';
import 'upload_signing_service.dart';

/// Composition root: process-wide singletons built from env
/// (docs/BACKEND.md §3.5), provided into request context by
/// `routes/_middleware.dart`. When `DATABASE_URL` is set the repositories are
/// Postgres-backed; otherwise they are in-memory — so local/dev/CI without a
/// database (and the app's tests) are unchanged.

bool get _isProd => (Platform.environment['ENV'] ?? 'dev') == 'prod';

String _resolveSecret() {
  final secret = Platform.environment['JWT_SECRET'];
  if (secret != null && secret.isNotEmpty) return secret;
  if (_isProd) {
    throw StateError('JWT_SECRET must be set in production');
  }
  // Dev-only fallback so local runs work without setup; never used in prod.
  return 'dev-insecure-secret-change-me';
}

final String? _databaseUrl = () {
  final url = Platform.environment['DATABASE_URL'];
  return (url == null || url.isEmpty) ? null : url;
}();

final Pool<void>? _pool = _databaseUrl == null
    ? null
    : createPool(_databaseUrl!);

String? _envOrNull(String key) {
  final v = Platform.environment[key]?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// Browser origins allowed to call the API (CORS) — the Next.js web app(s).
/// Comma-separated `WEB_ORIGINS`; dev defaults to the Next dev server, prod is
/// empty until configured (deny-by-default — no `*`). Design:
/// docs/design/web-m1-backend-glue.md.
final List<String> webOrigins = () {
  final raw = _envOrNull('WEB_ORIGINS');
  if (raw != null) {
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return _isProd ? const <String>[] : const ['http://localhost:3000'];
}();

/// R2 API endpoint: explicit `R2_ENDPOINT` wins, else derived from
/// `R2_ACCOUNT_ID` (so AWS S3 / Supabase / MinIO can drop in via `R2_ENDPOINT`).
String? get _r2Endpoint {
  final explicit = _envOrNull('R2_ENDPOINT');
  if (explicit != null) return explicit;
  final account = _envOrNull('R2_ACCOUNT_ID');
  return account == null ? null : 'https://$account.r2.cloudflarestorage.com';
}

final TokenService tokenService = TokenService(secret: _resolveSecret());

final AuthRepository authRepository = _pool == null
    ? InMemoryAuthRepository(tokens: tokenService, isProd: _isProd)
    : PostgresAuthRepository(_pool!, tokens: tokenService, isProd: _isProd);

final ProvidersRepository providersRepository = _pool == null
    ? InMemoryProvidersRepository()
    : PostgresProvidersRepository(_pool!);

final ProviderAuthRepository providerAuthRepository = _pool == null
    ? InMemoryProviderAuthRepository(tokens: tokenService, isProd: _isProd)
    : PostgresProviderAuthRepository(
        _pool!,
        tokens: tokenService,
        isProd: _isProd,
      );

final AppointmentRepository appointmentRepository = _pool == null
    ? InMemoryAppointmentRepository()
    : PostgresAppointmentRepository(_pool!);

final FavoritesRepository favoritesRepository = _pool == null
    ? InMemoryFavoritesRepository()
    : PostgresFavoritesRepository(_pool!);

final FavoritesService favoritesService = FavoritesService(
  favoritesRepository,
  providersRepository,
);

final ReviewsRepository reviewsRepository = _pool == null
    ? InMemoryReviewsRepository()
    : PostgresReviewsRepository(_pool!);

final SlotService slotService = SlotService(
  providersRepository,
  appointmentRepository,
);

final BookingService bookingService = BookingService(
  providersRepository,
  appointmentRepository,
  slotService,
);

final AppointmentLifecycleService appointmentLifecycleService =
    AppointmentLifecycleService(appointmentRepository, slotService);

final ProAppointmentService proAppointmentService = ProAppointmentService(
  providerAuthRepository,
  appointmentRepository,
);

/// Object storage for image uploads. Configured → R2 (S3-compatible); else a
/// no-network Fake for dev/CI. Production must configure it (fail-fast, like
/// `JWT_SECRET`) so we never issue fake URLs in prod.
final StorageService storageService = () {
  final endpoint = _r2Endpoint;
  final bucket = _envOrNull('R2_BUCKET');
  final keyId = _envOrNull('R2_ACCESS_KEY_ID');
  final secret = _envOrNull('R2_SECRET_ACCESS_KEY');
  final publicBase = _envOrNull('R2_PUBLIC_BASE_URL');
  final kycBucket = _envOrNull('R2_KYC_BUCKET');
  final depositBucket = _envOrNull('R2_DEPOSIT_BUCKET');
  if (endpoint != null &&
      bucket != null &&
      keyId != null &&
      secret != null &&
      publicBase != null &&
      kycBucket != null &&
      depositBucket != null) {
    return R2StorageService(
      endpoint: endpoint,
      bucket: bucket,
      accessKeyId: keyId,
      secretAccessKey: secret,
      publicBaseUrl: publicBase,
      kycBucket: kycBucket,
      depositBucket: depositBucket,
    );
  }
  if (_isProd) {
    throw StateError(
      'Object storage must be configured in production: set R2_ENDPOINT (or '
      'R2_ACCOUNT_ID), R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, '
      'R2_PUBLIC_BASE_URL, R2_KYC_BUCKET and R2_DEPOSIT_BUCKET (two separate '
      'private buckets).',
    );
  }
  return const FakeStorageService();
}();

/// When public delivery is configured, the gallery accepts only URLs from our
/// own origin (anti-SSRF / hotlink) plus `asset:` seed placeholders; empty in
/// dev/Fake (accept anything for local work).
final List<String> _galleryAllowedOrigins = () {
  final base = _envOrNull('R2_PUBLIC_BASE_URL');
  return base == null ? const <String>[] : <String>[base, 'asset:'];
}();

final ProviderCatalogService providerCatalogService = ProviderCatalogService(
  providersRepository,
  providerAuthRepository,
  allowedImageOrigins: _galleryAllowedOrigins,
);

final UploadSigningService uploadSigningService = UploadSigningService(
  providerAuthRepository,
  storageService,
);

final KycService kycService = KycService(providerAuthRepository);

final DepositService depositService = DepositService(
  appointmentRepository,
  providerAuthRepository,
  storageService,
);

final AdminAuthRepository adminAuthRepository = _pool == null
    ? InMemoryAdminAuthRepository(tokens: tokenService)
    : PostgresAdminAuthRepository(_pool!, tokens: tokenService);

final AuditLogRepository auditLogRepository = _pool == null
    ? InMemoryAuditLogRepository()
    : PostgresAuditLogRepository(_pool!);

final AdminKycService adminKycService = AdminKycService(
  providerAuthRepository,
  storageService,
  auditLogRepository,
);

final ModerationService moderationService = ModerationService(
  reviewsRepository,
  reviewsService,
  auditLogRepository,
);

final AdminProviderService adminProviderService = AdminProviderService(
  providersRepository,
  appointmentRepository,
  auditLogRepository,
);

final AdminUserService adminUserService = AdminUserService(
  authRepository,
  appointmentRepository,
  auditLogRepository,
);

final DisputesRepository disputesRepository = _pool == null
    ? InMemoryDisputesRepository()
    : PostgresDisputesRepository(_pool!);

final DisputeService disputeService = DisputeService(
  disputesRepository,
  appointmentRepository,
  depositService,
  auditLogRepository,
);

final AnalyticsService analyticsService = AnalyticsService(
  appointmentRepository,
  providersRepository,
  authRepository,
  providerAuthRepository,
  disputesRepository,
  reviewsRepository,
);

final ProviderDashboardService providerDashboardService =
    ProviderDashboardService(providerAuthRepository, appointmentRepository);

final ProviderEarningsService providerEarningsService = ProviderEarningsService(
  providerAuthRepository,
  appointmentRepository,
);

final ReviewsService reviewsService = ReviewsService(
  reviewsRepository,
  appointmentRepository,
  providersRepository,
  authRepository,
  allowedImageOrigins: _galleryAllowedOrigins,
);

/// Outbound messaging (WhatsApp + SMS). Configured → Twilio; else a no-network
/// log provider for dev/CI. Production must configure it (fail-fast, like
/// `JWT_SECRET`/storage). Design: docs/design/messaging-notifications.md.
final MessagingProvider messagingProvider = () {
  final sid = _envOrNull('TWILIO_ACCOUNT_SID');
  final token = _envOrNull('TWILIO_AUTH_TOKEN');
  final smsFrom = _envOrNull('TWILIO_SMS_FROM');
  final waFrom = _envOrNull('TWILIO_WHATSAPP_FROM');
  if (sid != null && token != null && smsFrom != null && waFrom != null) {
    return TwilioMessagingProvider(
      accountSid: sid,
      authToken: token,
      smsFrom: smsFrom,
      whatsAppFrom: waFrom,
    );
  }
  if (_isProd) {
    throw StateError(
      'Messaging must be configured in production: set TWILIO_ACCOUNT_SID, '
      'TWILIO_AUTH_TOKEN, TWILIO_SMS_FROM and TWILIO_WHATSAPP_FROM.',
    );
  }
  return LogMessagingProvider();
}();

final MessagingOutboxRepository messagingOutboxRepository = _pool == null
    ? InMemoryMessagingOutboxRepository()
    : PostgresMessagingOutboxRepository(_pool!);

final MessagingPrefsRepository messagingPrefsRepository = _pool == null
    ? InMemoryMessagingPrefsRepository()
    : PostgresMessagingPrefsRepository(_pool!);

final MessagingService messagingService = MessagingService(
  messagingProvider,
  messagingOutboxRepository,
  messagingPrefsRepository,
);

/// Shared secret guarding the delivery-status webhook (the BSP appends it as a
/// `?secret=` query param). When set, mismatches are rejected (deny-by-default);
/// unset (dev) → the webhook is open. Real Twilio signature validation is a
/// follow-up. Design: docs/design/messaging-notifications.md §5.
final String? messagingWebhookSecret = _envOrNull('MESSAGING_WEBHOOK_SECRET');

/// Push (FCM). Configured → FCM HTTP v1; else a no-network log provider for
/// dev/CI. Production must configure it (fail-fast). Design:
/// docs/design/push-notifications-fcm.md.
final PushProvider pushProvider = () {
  final projectId = _envOrNull('FCM_PROJECT_ID');
  final clientEmail = _envOrNull('FCM_CLIENT_EMAIL');
  // Render-style env often escapes newlines in the PEM — unescape them.
  final privateKey = _envOrNull('FCM_PRIVATE_KEY')?.replaceAll(r'\n', '\n');
  if (projectId != null && clientEmail != null && privateKey != null) {
    return FcmV1PushProvider(
      projectId: projectId,
      tokenSource: ServiceAccountTokenSource(
        clientEmail: clientEmail,
        privateKeyPem: privateKey,
      ),
    );
  }
  if (_isProd) {
    throw StateError(
      'Push must be configured in production: set FCM_PROJECT_ID, '
      'FCM_CLIENT_EMAIL and FCM_PRIVATE_KEY (service account).',
    );
  }
  return LogPushProvider();
}();

final DeviceTokenRepository deviceTokenRepository = _pool == null
    ? InMemoryDeviceTokenRepository()
    : PostgresDeviceTokenRepository(_pool!);

final PushService pushService = PushService(
  pushProvider,
  deviceTokenRepository,
);

final NotificationsRepository notificationsRepository = _pool == null
    ? InMemoryNotificationsRepository()
    : PostgresNotificationsRepository(_pool!);

final NotificationPrefsRepository notificationPrefsRepository = _pool == null
    ? InMemoryNotificationPrefsRepository()
    : PostgresNotificationPrefsRepository(_pool!);

/// Turns booking transitions into notifications (recipient + params resolution),
/// across WhatsApp/SMS + push + the in-app feed — honouring per-user prefs.
final BookingNotifier bookingNotifier = BookingNotifier(
  messagingService,
  authRepository,
  providersRepository,
  pushService,
  notificationsRepository,
  notificationPrefsRepository,
);

final ReminderLogRepository reminderLogRepository = _pool == null
    ? InMemoryReminderLogRepository()
    : PostgresReminderLogRepository(_pool!);

/// The 24h/2h reminder scheduler (driven by the internal cron route).
final ReminderScheduler reminderScheduler = ReminderScheduler(
  appointmentRepository,
  reminderLogRepository,
  bookingNotifier,
);

/// Shared secret guarding the internal reminder-cron route (deny-by-default when
/// set; unset → the route is unavailable). Design:
/// docs/design/messaging-notifications.md §PR-B.
final String? cronSecret = _envOrNull('CRON_SECRET');

/// Server-startup hook (called from the custom entrypoint `main.dart`): applies
/// migrations and seeds providers when a database is configured. No-op for
/// in-memory mode.
Future<void> initializeDatabase() async {
  final pool = _pool;
  if (pool != null) {
    await runMigrations(pool);
    await seedProvidersIfEmpty(pool);
    // Move services/availability out of the provider JSONB into the normalized
    // catalogue tables (single source of truth). See migration 0005.
    await backfillCatalogueIfNeeded(pool);
  }
  // Seed the super-admin from env (idempotent), after migrations so the table
  // exists. Runs in both modes; no-op when ADMIN_EMAIL/ADMIN_PASSWORD are unset.
  final adminEmail = _envOrNull('ADMIN_EMAIL');
  final adminPassword = _envOrNull('ADMIN_PASSWORD');
  if (adminEmail != null && adminPassword != null) {
    await adminAuthRepository.ensureSeedAdmin(
      email: adminEmail,
      password: adminPassword,
    );
  }
}
