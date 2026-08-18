import 'dart:io';

import 'package:postgres/postgres.dart';

import 'access/membership_repository.dart';
import 'access/membership_service.dart';
import 'access/salon_directory_service.dart';
import 'access/team_service.dart';
import 'admin/admin_auth_repository.dart';
import 'admin/admin_client_version_service.dart';
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
import 'appointments/journal_service.dart';
import 'appointments/pro_appointment_service.dart';
import 'appointments/slot_service.dart';
import 'auth/auth_methods.dart';
import 'auth/auth_repository.dart';
import 'auth/id_token_verifier.dart';
import 'auth/provider_auth_repository.dart';
import 'auth/smoke_seam.dart';
import 'auth/tokens.dart';
import 'boot_config.dart';
import 'client_version/client_version_repository.dart';
import 'client_version/client_version_service.dart';
import 'clients/clients_repository.dart';
import 'clients/clients_service.dart';
import 'clients/provider_audit_log.dart';
import 'cron_auth.dart';
import 'db/database.dart';
import 'db/migrations.dart';
import 'db/postgres_admin_auth_repository.dart';
import 'db/postgres_appointment_repository.dart';
import 'db/postgres_audit_log_repository.dart';
import 'db/postgres_auth_repository.dart';
import 'db/postgres_client_version_repository.dart';
import 'db/postgres_clients_repository.dart';
import 'db/postgres_device_token_repository.dart';
import 'db/postgres_disputes_repository.dart';
import 'db/postgres_favorites_repository.dart';
import 'db/postgres_membership_repository.dart';
import 'db/postgres_messaging_outbox_repository.dart';
import 'db/postgres_messaging_prefs_repository.dart';
import 'db/postgres_notification_prefs_repository.dart';
import 'db/postgres_notifications_repository.dart';
import 'db/postgres_provider_audit_repository.dart';
import 'db/postgres_provider_auth_repository.dart';
import 'db/postgres_providers_repository.dart';
import 'db/postgres_reminder_log_repository.dart';
import 'db/postgres_reviews_repository.dart';
import 'db/postgres_salon_subscription_repository.dart';
import 'deposit_service.dart';
import 'email/email_provider.dart';
import 'email/resend_email_provider.dart';
import 'favorites_repository.dart';
import 'favorites_service.dart';
import 'kyc_service.dart';
import 'localities/localities_repository.dart';
import 'localities/localities_service.dart';
import 'messaging/booking_notifier.dart';
import 'messaging/messaging_outbox_repository.dart';
import 'messaging/messaging_prefs_repository.dart';
import 'messaging/messaging_provider.dart';
import 'messaging/messaging_service.dart';
import 'messaging/reminder_log_repository.dart';
import 'messaging/reminder_scheduler.dart';
import 'messaging/salon_notifier.dart';
import 'messaging/termii_messaging_provider.dart';
import 'messaging/twilio_messaging_provider.dart';
import 'messaging/webhook_auth.dart';
import 'notifications/notification_prefs_repository.dart';
import 'notifications/notifications_repository.dart';
import 'observability/error_reporter.dart';
import 'privacy/user_erasure_service.dart';
import 'provider_account_service.dart';
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
import 'salon_provisioning_service.dart';
import 'storage/storage_service.dart';
import 'subscription/salon_subscription_repository.dart';
import 'subscription/salon_subscription_service.dart';
import 'subscription/subscription_scheduler.dart';
import 'upload_signing_service.dart';
import 'upload_verification_service.dart';

/// Composition root: process-wide singletons built from env
/// (docs/BACKEND.md §3.5), provided into request context by
/// `routes/_middleware.dart`. When `DATABASE_URL` is set the repositories are
/// Postgres-backed; otherwise they are in-memory — so local/dev/CI without a
/// database (and the app's tests) are unchanged.

/// Which deployment this is (`ENV`), parsed once. An unrecognised value throws
/// here rather than silently meaning `dev` — see [Env.parse].
final Env _env = Env.parse(Platform.environment['ENV']);

/// Which deployment this is, for anything that needs to *state* it rather than
/// branch on it — `/health` reports it so a caller can ask the target what it is
/// instead of inferring it from the hostname it typed.
Env get env => _env;

/// **Fail fast on missing configuration.** True for staging AND prod: staging
/// exists to rehearse production, and an environment whose guards are off
/// rehearses nothing. Every `must be set in production` throw below hangs off
/// this.
bool get _guardsOn => _env.guardsOn;

/// **This is the real thing.** True for prod ONLY — and today it has exactly
/// **one** use: the smoke-seam disclosure warning below.
///
/// It used to have two, and the second was the OTP dev-code echo, justified
/// here as "staging has no SMS channel, so without it nobody can sign in".
/// That moved to [_echoesOtpDevCode] on 2026-08-18 because staging is public,
/// and the sentence is recorded rather than deleted: it was the argument that
/// kept the hole open, and it sat four lines above the getter that closes it.
bool get _isProd => _env.isProd;

/// Whether an OTP may be handed back in an HTTP response — `dev` only.
/// Deliberately NOT `!_isProd`: staging is reachable from the internet.
/// docs/design/backend-staging-otp-disclosure.md.
bool get _echoesOtpDevCode => _env.echoesOtpDevCode;

String _resolveSecret() =>
    resolveJwtSecret(Platform.environment['JWT_SECRET'], guardsOn: _guardsOn);

/// G1: **throws in production when unset**, where before it returned null and
/// every repository quietly became its `InMemory` variant — a green API that
/// loses every booking on restart. See `boot_config.dart`.
final String? _databaseUrl = resolveDatabaseUrl(
  Platform.environment['DATABASE_URL'],
  guardsOn: _guardsOn,
);

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
    final origins = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (origins.isNotEmpty) return origins;
  }
  // Deny-by-default is the right posture for an unknown origin, but it is the
  // wrong posture for an unset variable: an empty allowlist rejects the web app
  // and the admin console from a service that is otherwise perfectly healthy,
  // and it does it with a CORS failure in the browser rather than anything
  // visible server-side. Fail at boot instead, where it is one log line.
  if (_guardsOn) {
    throw StateError(
      'WEB_ORIGINS must be set in staging and production — an empty allowlist '
      'blocks every browser call from the web app and the admin console, and '
      'shows up only as an opaque CORS error in the client.',
    );
  }
  return const ['http://localhost:3000'];
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

/// Consumer sign-in methods (`AUTH_METHODS`, comma-separated; unset → all).
/// Launch config: `google,apple,email` — the SMS path stays dormant until
/// cheap CI SMS unlocks. Design: docs/design/auth-social-email.md §14.
final AuthMethods authMethods = AuthMethods.parse(_envOrNull('AUTH_METHODS'));

/// The production OTP-disclosure seam (Q1b) — absent unless `SMOKE_OTP_SECRET`
/// is set. See `auth/smoke_seam.dart` and docs/design/backend-q1b-smoke-seam.md.
final SmokeSeam smokeSeam = SmokeSeam(_envOrNull('SMOKE_OTP_SECRET'));

List<String> _csvEnv(String key) =>
    _envOrNull(
      key,
    )?.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList() ??
    const [];

/// Google Sign-In ID-token verifier. `GOOGLE_CLIENT_IDS` = the OAuth client-ID
/// allowlist (web + Android + iOS). Unconfigured → the verifier rejects every
/// token (fail closed); prod fails fast when the method is enabled.
final GoogleIdTokenVerifier googleIdTokenVerifier = () {
  final ids = _csvEnv('GOOGLE_CLIENT_IDS');
  if (_guardsOn &&
      authMethods.explicit &&
      authMethods.contains('google') &&
      ids.isEmpty) {
    throw StateError(
      'GOOGLE_CLIENT_IDS must be set in staging and production while the '
      '"google" auth '
      'method is enabled (AUTH_METHODS).',
    );
  }
  return GoogleIdTokenVerifier(clientIds: ids);
}();

/// Sign in with Apple verifier. `APPLE_CLIENT_IDS` = iOS bundle id + the web
/// Service ID. Same fail-closed/fail-fast posture as Google.
final AppleIdTokenVerifier appleIdTokenVerifier = () {
  final ids = _csvEnv('APPLE_CLIENT_IDS');
  if (_guardsOn &&
      authMethods.explicit &&
      authMethods.contains('apple') &&
      ids.isEmpty) {
    throw StateError(
      'APPLE_CLIENT_IDS must be set in staging and production while the '
      '"apple" auth '
      'method is enabled (AUTH_METHODS).',
    );
  }
  return AppleIdTokenVerifier(clientIds: ids);
}();

/// Outbound email (the OTP channel). Configured → Resend; else a no-network
/// log provider for dev/CI (devCode is echoed inline off-prod). Production
/// must configure it while the "email" method is enabled (fail-fast).
final EmailProvider emailProvider = () {
  final apiKey = _envOrNull('RESEND_API_KEY');
  final from = _envOrNull('EMAIL_FROM') ?? 'MyWeli <no-reply@myweli.com>';
  if (apiKey != null) return ResendEmailProvider(apiKey: apiKey, from: from);
  if (_guardsOn && authMethods.explicit && authMethods.contains('email')) {
    throw StateError(
      'RESEND_API_KEY must be set in staging and production while the '
      '"email" auth '
      'method is enabled (AUTH_METHODS).',
    );
  }
  return LogEmailProvider();
}();

final AuthRepository authRepository = _pool == null
    ? InMemoryAuthRepository(
        tokens: tokenService,
        echoDevCode: _echoesOtpDevCode,
      )
    : PostgresAuthRepository(
        _pool!,
        tokens: tokenService,
        echoDevCode: _echoesOtpDevCode,
      );

final ProvidersRepository providersRepository = _pool == null
    ? InMemoryProvidersRepository()
    : PostgresProvidersRepository(_pool!);

/// Multi-pays MP1 — the locality reference tree
/// (docs/design/multi-pays-end-version.md §2).
final LocalitiesRepository localitiesRepository = _pool == null
    ? InMemoryLocalitiesRepository()
    : PostgresLocalitiesRepository(_pool!);

final LocalitiesService localitiesService = LocalitiesService(
  localitiesRepository,
);

final ProviderAuthRepository providerAuthRepository = _pool == null
    ? InMemoryProviderAuthRepository(
        tokens: tokenService,
        echoDevCode: _echoesOtpDevCode,
      )
    : PostgresProviderAuthRepository(
        _pool!,
        tokens: tokenService,
        echoDevCode: _echoesOtpDevCode,
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

final ClientsRepository clientsRepository = _pool == null
    ? InMemoryClientsRepository()
    : PostgresClientsRepository(_pool!);

final ProviderAuditLogRepository providerAuditLogRepository = _pool == null
    ? InMemoryProviderAuditLogRepository()
    : PostgresProviderAuditLogRepository(_pool!);

/// Module `clients` C1 (docs/design/clients-c1.md).
final ClientsService clientsService = ClientsService(
  providerAuthRepository,
  membershipService,
  authRepository,
  clientsRepository,
  appointmentRepository,
  providerAuditLogRepository,
);

final BookingService bookingService = BookingService(
  providersRepository,
  appointmentRepository,
  slotService,
  clients: clientsService,
  // T61 + ownership for a deposit screenshot attached inline at booking. Absent
  // here, `book` stores whatever string arrived — which is what it used to do.
  verifier: uploadVerificationService,
);

final AppointmentLifecycleService appointmentLifecycleService =
    AppointmentLifecycleService(
      appointmentRepository,
      slotService,
      providersRepository,
    );

final ProAppointmentService proAppointmentService = ProAppointmentService(
  membershipService,
  appointmentRepository,
  clients: clientsService,
  providers: providersRepository,
);

/// Journal day view (module journal J1 — docs/design/journal-j1-grid.md).
final JournalService journalService = JournalService(
  membershipService,
  providersRepository,
  appointmentRepository,
  clientsService,
);

/// Object storage for image uploads. Configured → R2 (S3-compatible); else a
/// no-network Fake for dev/CI. Production must configure it (fail-fast, like
/// `JWT_SECRET`) so we never issue fake URLs in prod.
final StorageService storageService = () {
  // The supported way to run a guarded environment with no object storage —
  // the same escape hatch `MESSAGING_PROVIDER` and `PUSH_PROVIDER` already
  // have, and storage was the only one of the three without it. Until now
  // "nothing configured" and "deliberately off" were indistinguishable here,
  // which is precisely the ambiguity the other two were given a value to
  // remove.
  //
  // Checked ABOVE the build, for the same reason theirs are: it must be a
  // deliberate choice and never a fall-through, so "nothing configured" still
  // reaches the fail-fast below. Never auto-detected.
  //
  // The Fake's URLs are visibly fake (`fake-storage.local`), so nothing here
  // can be mistaken for real delivery — and `galleryOriginsFor` keeps the
  // gallery's origin check switched on when it is selected.
  if (_envOrNull('STORAGE_PROVIDER')?.toLowerCase() == 'disabled') {
    return FakeStorageService();
  }
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
  if (_guardsOn) {
    throw StateError(
      'Object storage must be configured in staging and production: set '
      'R2_ENDPOINT (or '
      'R2_ACCOUNT_ID), R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, '
      'R2_PUBLIC_BASE_URL, R2_KYC_BUCKET and R2_DEPOSIT_BUCKET (two separate '
      'private buckets) — or set STORAGE_PROVIDER=disabled to run deliberately '
      'without object storage.',
    );
  }
  return FakeStorageService();
}();

/// Which origins the gallery accepts an image URL from — derived from the
/// storage service actually in use, never from a second read of
/// `R2_PUBLIC_BASE_URL`. See `galleryOriginsFor`.
final List<String> _galleryAllowedOrigins = galleryOriginsFor(
  storageService,
  guardsOn: _guardsOn,
);

/// The authoritative upload size cap (T61) — R2 ignores a signed
/// `content-length`, so the limit declared at signing time is advisory and this
/// is where it holds. docs/design/backend-upload-size-verification.md.
final UploadVerificationService uploadVerificationService =
    UploadVerificationService(storage: storageService);

/// Base for deriving an object key from a public delivery URL. Null in dev/Fake,
/// which is why every claim path treats a null verifier/base as "skip". Read off
/// the storage service for the same reason the allowlist above is.
final String? _r2PublicBase = storageService.publicBaseUrl;

final ProviderCatalogService providerCatalogService = ProviderCatalogService(
  providersRepository,
  providerAuthRepository,
  membershipService,
  allowedImageOrigins: _galleryAllowedOrigins,
  localities: localitiesService,
  verifier: uploadVerificationService,
  publicBaseUrl: _r2PublicBase,
);

final UploadSigningService uploadSigningService = UploadSigningService(
  providerAuthRepository,
  membershipService,
  storageService,
);

final KycService kycService = KycService(
  providerAuthRepository,
  verifier: uploadVerificationService,
);

/// Salon lifecycle (docs/design/pro-salon-lifecycle.md): draft creation at
/// registration + the /me/provider self-heal + the publish gate.
/// Module `access` (R1): membership rows + the per-request capability
/// resolver every tenant-authz decision now goes through.
final MembershipRepository membershipRepository = _pool == null
    ? InMemoryMembershipRepository()
    : PostgresMembershipRepository(_pool!);

final MembershipService membershipService = MembershipService(
  membershipRepository,
  providerAuthRepository,
);

final ProviderAccountService providerAccountService = ProviderAccountService(
  providerAuthRepository,
  providersRepository,
  appointmentRepository,
  storageService,
  membershipRepository,
  // L1/T59 — a deleted salon owner's phone must stop ringing too.
  devices: deviceTokenRepository,
  notifications: notificationsRepository,
);

/// The pricing pivot (R2a): salon offers + the daily warning/enforcement
/// walk. Enforcement is config-driven (SUBSCRIPTION_ENFORCEMENT, default
/// off — cold-start leniency).
final SalonSubscriptionRepository salonSubscriptionRepository = _pool == null
    ? InMemorySalonSubscriptionRepository()
    : PostgresSalonSubscriptionRepository(_pool!);

final SalonSubscriptionService salonSubscriptionService =
    SalonSubscriptionService(
      salonSubscriptionRepository,
      membershipService,
      membershipRepository,
      providersRepository,
      providerAuthRepository,
    );

/// R6 — « Mes salons »: the multi-salon directory + « Ajouter un salon ».
final SalonDirectoryService salonDirectoryService = SalonDirectoryService(
  membershipRepository,
  membershipService,
  providersRepository,
  salonSubscriptionService,
  providerAuthRepository,
);

final bool subscriptionEnforcement =
    (_envOrNull('SUBSCRIPTION_ENFORCEMENT') ?? 'off').toLowerCase() == 'on';

final SubscriptionScheduler subscriptionScheduler = SubscriptionScheduler(
  salonSubscriptionRepository,
  membershipRepository,
  providersRepository,
  emailProvider,
  pushService,
  enforce: subscriptionEnforcement,
);

/// Module `access` R2b: invitations + Equipe mutations (owner-gated,
/// audited, offer/seat-gated).
final TeamService teamService = TeamService(
  membershipRepository,
  membershipService,
  providersRepository,
  salonSubscriptionService,
  emailProvider,
  providerAuditLogRepository,
);

final SalonProvisioningService salonProvisioningService =
    SalonProvisioningService(
      providersRepository,
      providerAuthRepository,
      membershipRepository,
      subscriptions: salonSubscriptionService,
    );

final DepositService depositService = DepositService(
  appointmentRepository,
  membershipService,
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
  providersRepository,
  membershipRepository,
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
  salonSubscriptionService,
);

/// The client version floors — Postgres in a real deployment, in-memory
/// otherwise, exactly like every other repository here.
final ClientVersionRepository clientVersionRepository = _pool == null
    ? InMemoryClientVersionRepository()
    : PostgresClientVersionRepository(_pool!);

final ClientVersionService clientVersionService = ClientVersionService(
  clientVersionRepository,
);

final AdminClientVersionService adminClientVersionService =
    AdminClientVersionService(clientVersionRepository, auditLogRepository);

final AdminUserService adminUserService = AdminUserService(
  authRepository,
  appointmentRepository,
  auditLogRepository,
  userErasureService,
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
    ProviderDashboardService(
      membershipService,
      appointmentRepository,
      providers: providersRepository,
    );

final ProviderEarningsService providerEarningsService = ProviderEarningsService(
  membershipService,
  appointmentRepository,
  providers: providersRepository,
);

final ReviewsService reviewsService = ReviewsService(
  reviewsRepository,
  appointmentRepository,
  providersRepository,
  authRepository,
  allowedImageOrigins: _galleryAllowedOrigins,
  verifier: uploadVerificationService,
  publicBaseUrl: _r2PublicBase,
);

/// Outbound messaging (SMS, + WhatsApp later). The provider is chosen by
/// `MESSAGING_PROVIDER` (`termii` | `twilio` | `log`); unset → auto-detect from
/// whichever credentials are present, preferring **Termii** (~14 FCFA/SMS to
/// Côte d'Ivoire vs Twilio's ~$0.49). Production must configure one (fail-fast,
/// like `JWT_SECRET`/storage). Switching is a one-env-var flip with no code
/// change, and the other provider's config can stay for instant rollback.
/// Design: docs/design/messaging-termii.md + messaging-notifications.md.
final MessagingProvider messagingProvider = () {
  TermiiMessagingProvider? buildTermii() {
    final apiKey = _envOrNull('TERMII_API_KEY');
    final sender = _envOrNull('TERMII_SENDER_ID');
    if (apiKey == null || sender == null) return null;
    return TermiiMessagingProvider(
      apiKey: apiKey,
      senderId: sender,
      baseUrl: _envOrNull('TERMII_BASE_URL') ?? 'https://api.ng.termii.com',
      route: _envOrNull('TERMII_CHANNEL') ?? 'generic',
    );
  }

  TwilioMessagingProvider? buildTwilio() {
    final sid = _envOrNull('TWILIO_ACCOUNT_SID');
    final token = _twilioAuthToken;
    final smsFrom = _envOrNull('TWILIO_SMS_FROM');
    if (sid == null || token == null || smsFrom == null) return null;
    // Per-message delivery-status callback → the status webhook, which advances
    // the outbox. Attached whenever the public base URL is known.
    //
    // **No `?secret=`.** It used to carry `MESSAGING_WEBHOOK_SECRET` in the query
    // string, which put a credential into Cloud Run request logs, load-balancer
    // logs and anything else that records a URL — the exact weakness BACKEND.md
    // T21 records as removed from the cron routes. Twilio authenticates itself
    // with `X-Twilio-Signature`, so there was never anything for the secret to
    // add here; see `messaging/webhook_auth.dart`.
    //
    // Dropping it also removes a coupling that made no sense: delivery tracking
    // was previously off unless a shared secret happened to be configured.
    final publicBase = _envOrNull('PUBLIC_BASE_URL');
    final statusCallback = publicBase == null
        ? null
        : '${publicBase.endsWith('/') ? publicBase.substring(0, publicBase.length - 1) : publicBase}'
              '/webhooks/messaging/status';
    return TwilioMessagingProvider(
      accountSid: sid,
      authToken: token,
      smsFrom: smsFrom,
      // WhatsApp is optional (SMS-first launch): until a sender is approved,
      // WhatsApp sends fall back to SMS. SMS stays mandatory in production.
      whatsAppFrom: _envOrNull('TWILIO_WHATSAPP_FROM'),
      statusCallback: statusCallback,
    );
  }

  final selector = _envOrNull('MESSAGING_PROVIDER')?.toLowerCase();

  // **`log` is refused in production, and this guard sits ABOVE the switch on
  // purpose.** Written the obvious way — `'log' => LogMessagingProvider()` in
  // the switch — it yields a non-null `chosen`, so `if (chosen != null) return`
  // fires and the `_isProd` fail-fast below is never reached. A leftover
  // staging value or a typo in the Render dashboard would then boot production
  // with a no-op provider: every OTP, booking confirmation and reminder
  // silently swallowed, while the outbox happily records them as `sent`.
  //
  // The fail-fast below was written for "nothing configured". This is the other
  // way to have nothing configured, and it looks deliberate, which is worse.
  if (_guardsOn && selector == 'log') {
    throw StateError(
      'MESSAGING_PROVIDER=log is a no-op provider and must never run in '
      'staging or production — every message would be dropped while the outbox '
      'recorded '
      'it as sent. Set MESSAGING_PROVIDER to termii or twilio, with the '
      'matching credentials.',
    );
  }

  final MessagingProvider? chosen = switch (selector) {
    'termii' => buildTermii(),
    'twilio' => buildTwilio(),
    'log' => LogMessagingProvider(),
    // The supported way to run production with no SMS channel at all (G1).
    // Explicit by design: it is never auto-detected, so "nothing configured"
    // still hits the fail-fast below. Unlike `log`, it reports ok: false, so
    // the outbox records the truth rather than a phantom `sent`.
    'disabled' => DisabledMessagingProvider(),
    // Unset → auto-detect: prefer Termii (CI cost), then Twilio.
    _ => buildTermii() ?? buildTwilio(),
  };
  if (chosen != null) return chosen;

  if (_guardsOn) {
    throw StateError(
      'Messaging (SMS) must be configured in staging and production: set '
      'MESSAGING_PROVIDER '
      'and the matching credentials — Termii (TERMII_API_KEY + TERMII_SENDER_ID) '
      'or Twilio (TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN + TWILIO_SMS_FROM).',
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

/// Transitional shared secret for the delivery-status webhook, sent as the
/// **`X-Messaging-Secret` header** — never in the URL, which is what it used to
/// be. See `messaging/webhook_auth.dart` for why Twilio cannot use it and what
/// authenticates Twilio instead.
final String? messagingWebhookSecret = _envOrNull('MESSAGING_WEBHOOK_SECRET');

/// The Twilio auth token, hoisted to the top level because it is now read by two
/// things: the provider that sends messages, and the webhook auth that verifies
/// Twilio's signature on the way back.
final String? _twilioAuthToken = _envOrNull('TWILIO_AUTH_TOKEN');

/// Authenticates `POST /webhooks/messaging/status` — the Twilio request
/// signature first, the shared-secret header as the transitional fallback,
/// 404 when neither is configured. See `messaging/webhook_auth.dart`.
final MessagingWebhookAuth messagingWebhookAuth = MessagingWebhookAuth(
  twilioAuthToken: _twilioAuthToken,
  sharedSecret: messagingWebhookSecret,
  publicBaseUrl: _envOrNull('PUBLIC_BASE_URL'),
);

/// Push (FCM). Configured → FCM HTTP v1; else a no-network log provider for
/// dev/CI. Production must configure it (fail-fast). Design:
/// docs/design/push-notifications-fcm.md.
final PushProvider pushProvider = () {
  // `disabled` is the supported way to run a guarded environment with no push
  // channel — staging, whose Firebase project does not exist until the app gets
  // its own bundle ids (docs/design/infra-staging.md §4). Checked ABOVE the FCM
  // build for the same reason `MESSAGING_PROVIDER=log` is checked above its
  // switch: it must be a deliberate choice, never a fall-through, so that
  // "nothing configured" still reaches the fail-fast below.
  if (_envOrNull('PUSH_PROVIDER')?.toLowerCase() == 'disabled') {
    return DisabledPushProvider();
  }
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
  if (_guardsOn) {
    throw StateError(
      'Push must be configured in staging and production: set FCM_PROJECT_ID, '
      'FCM_CLIENT_EMAIL and FCM_PRIVATE_KEY (service account) — or set '
      'PUSH_PROVIDER=disabled to run deliberately without a push channel.',
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

/// Consumer account erasure (L1, threat T59 — docs/design/account-deletion-erasure.md).
/// Declared here rather than beside `clientsService` because it needs the
/// notification stack, which is defined further down this file.
final UserErasureService userErasureService = UserErasureService(
  authRepository,
  deviceTokenRepository,
  notificationsRepository,
  notificationPrefsRepository,
  favoritesRepository,
  reviewsRepository,
  appointmentRepository,
  clientsService,
  storageService,
);

/// The provider-directed sibling: turns client-driven booking events into
/// SALON-team notifications (push + in-app feed), scoped by team capabilities.
/// Design: docs/design/push-notifications-fcm.md §10.
final SalonNotifier salonNotifier = SalonNotifier(
  membershipRepository,
  pushService,
  notificationsRepository,
  notificationPrefsRepository,
  providersRepository,
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
/// Where unhandled errors go (docs/design/observability-error-reporting.md).
///
/// Mutable and defaulted to the no-op, because the middleware chain is built
/// BEFORE this is configured — dart_frog's generated `server.dart` calls
/// `buildRootHandler()` and only then `entrypoint.run()`, which is where
/// `initializeDatabase()` runs. `errorMiddleware` therefore takes a callback and
/// reads this per error; capturing it would freeze the no-op and silently
/// report nothing.
ErrorReporter errorReporter = const NoopErrorReporter();

/// `SENTRY_DSN` unset → reporting stays a no-op. Deliberately NOT part of the
/// `guardsOn` fail-fast set: an unreportable error is bad, but a backend that
/// refuses to boot because its telemetry is unconfigured is worse than both.
final String? _sentryDsn = _envOrNull('SENTRY_DSN');

/// The deployed image tag, which is what makes Sentry's release health mean
/// anything — errors group by the exact artifact that produced them.
final String? _release = _envOrNull('RELEASE');

/// Authenticates `/internal/cron/*` — the Google-signed OIDC token Cloud
/// Scheduler already sends. The transitional `X-Cron-Secret` fallback was
/// retired on 2026-08-18; see `cron_auth.dart` for the evidence that preceded
/// it.
///
/// `CRON_OIDC_AUDIENCE` must equal the `audience` on the Scheduler job
/// (`https://api.myweli.com`), and `CRON_SERVICE_ACCOUNT` the job's
/// `serviceAccountEmail` — without the second, the audience is just a public
/// string any Google account can mint a token for.
final CronAuth cronAuth = () {
  final audience = _envOrNull('CRON_OIDC_AUDIENCE');
  final serviceAccount = _envOrNull('CRON_SERVICE_ACCOUNT');
  return CronAuth(
    oidcVerifier: (audience == null || serviceAccount == null)
        ? null
        : GoogleIdTokenVerifier(clientIds: [audience]),
    schedulerServiceAccount: serviceAccount,
  );
}();

/// Force every configuration-derived singleton to resolve **at boot**.
///
/// `assertProductionBootConfig` above forces two values. Everything else in this
/// file is a lazy `final` handed to routes through `provider<T>((_) => x)`, and
/// a lambda is not an evaluation — so each of these guards first runs on the
/// first request that reaches a route needing it. `/health` needs none of them
/// and `/providers` needs only the repository and the slot service, which is why
/// **a service missing every secret below still passes the deploy workflow's
/// verify step** and is promoted to serve traffic.
///
/// This is the list that makes the deploy the check. It is maintained by hand
/// because Dart offers no way to enumerate a library's top-level finals; the
/// enforcement is that a staging deploy — which is a fresh environment where
/// something is always missing — fails loudly the first time one is forgotten.
///
/// **Add an entry whenever a new singleton reads configuration.** Only the ones
/// that can *fail* matter: a plain `String?` env read has nothing to prove.
void _assertConfiguredDependenciesResolve() {
  // Dev deliberately runs with almost nothing configured — that is the whole
  // point of the in-memory fallbacks — so there is nothing here to assert.
  if (!_guardsOn) return;
  assertEveryDependencyResolves({
    'webOrigins': () => webOrigins,
    'tokenService': () => tokenService,
    'authMethods': () => authMethods,
    'smokeSeam': () => smokeSeam,
    'googleIdTokenVerifier': () => googleIdTokenVerifier,
    'appleIdTokenVerifier': () => appleIdTokenVerifier,
    'emailProvider': () => emailProvider,
    'messagingProvider': () => messagingProvider,
    'pushProvider': () => pushProvider,
    // Also covers `_galleryAllowedOrigins`, `_r2PublicBase` and
    // `uploadVerificationService`, which are all derived from it.
    'storageService': () => storageService,
    'cronAuth': () => cronAuth,
  });
}

/// Server-startup hook (called from the custom entrypoint `main.dart`): applies
/// migrations and seeds providers when a database is configured. No-op for
/// in-memory mode.
Future<void> initializeDatabase() async {
  // Before anything that can fail, so a failure during boot is itself reported.
  errorReporter = await initErrorReporter(
    dsn: _sentryDsn,
    environment: _env,
    release: _release,
  );

  // Fail before the port is bound, not on the first request (G1). `main.dart`
  // awaits this ahead of `serve()`, so a misconfigured revision dies during
  // startup rather than going green and then failing every call.
  // A disclosure path left switched on by accident is the failure mode this
  // seam is most likely to produce, and the deploy log is where an operator
  // would notice it. Announced at boot rather than on first use.
  if (_isProd && smokeSeam.isActive) {
    // ignore: avoid_print — boot diagnostics go to the container log.
    print(
      'WARNING: SMOKE_OTP_SECRET is set — the OTP disclosure seam is ACTIVE in '
      'production for *.test identities. Unset it once the cutover gate has '
      'run (docs/design/backend-q1b-smoke-seam.md).',
    );
  }
  assertProductionBootConfig(
    databaseUrl: Platform.environment['DATABASE_URL'],
    jwtSecret: Platform.environment['JWT_SECRET'],
    guardsOn: _guardsOn,
  );
  _assertConfiguredDependenciesResolve();

  final pool = _pool;
  if (pool != null) {
    // Serialised across processes (G1) — see `withSchemaLock`. Every call below
    // is a migration or a check-then-act seed, and Cloud Run boots cold
    // instances in parallel where Render never did.
    await withSchemaLock(pool, () async {
      await runMigrations(pool);
      // **Demo salons are dev-only, and the gate is `ENV`, not emptiness.**
      // `seedProvidersIfEmpty` asks one question — is the `providers` table
      // empty? — so purging the fictional salons from production and deploying
      // simply re-created them, as would any cold start once `minScale`
      // recycled an instance. That made docs/LAUNCH.md §5.1 impossible to
      // satisfy rather than merely unfinished.
      //
      // Staging is excluded too: it gets deliberately seeded data with
      // namespaced ids (docs/design/infra-staging.md §2.1), because these rows
      // carry FIXED ids and identical primary keys across environments make
      // every later log line ambiguous about where it came from.
      if (_env == Env.dev) await seedProvidersIfEmpty(pool, env: _env);
      // Move services/availability out of the provider JSONB into the
      // normalized catalogue tables (single source of truth). Migration 0005.
      await backfillCatalogueIfNeeded(pool);
      // Multi-pays MP1: seed the locality reference tree, then stamp the salon
      // market fields onto pre-MP1 provider documents
      // (docs/design/multi-pays-end-version.md §2).
      await seedLocalitiesIfEmpty(pool);
      await backfillSalonMarketIfNeeded(pool);
    });
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
