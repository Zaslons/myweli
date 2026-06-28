import '../../services/api/api_appointment_service.dart';
import '../../services/api/api_auth_service.dart';
import '../../services/api/api_device_registration_service.dart';
import '../../services/api/api_favorites_service.dart';
import '../../services/api/api_image_upload_service.dart';
import '../../services/api/api_notification_service.dart';
import '../../services/api/api_pro_artist_service.dart';
import '../../services/api/api_pro_kyc_service.dart';
import '../../services/api/api_pro_service.dart';
import '../../services/api/api_pro_subscription_service.dart';
import '../../services/api/api_provider_service.dart';
import '../../services/api/api_review_service.dart';
import '../../services/interfaces/appointment_service_interface.dart';
import '../../services/interfaces/auth_service_interface.dart';
import '../../services/interfaces/device_registration_service_interface.dart';
import '../../services/interfaces/favorites_service_interface.dart';
import '../../services/interfaces/image_upload_service_interface.dart';
import '../../services/interfaces/messaging_service_interface.dart';
import '../../services/interfaces/notification_service_interface.dart';
import '../../services/interfaces/pro_artist_service_interface.dart';
import '../../services/interfaces/pro_kyc_service_interface.dart';
import '../../services/interfaces/pro_service_interface.dart';
import '../../services/interfaces/provider_service_interface.dart';
import '../../services/interfaces/push_notification_service_interface.dart';
import '../../services/interfaces/review_service_interface.dart';
import '../../services/interfaces/subscription_service_interface.dart';
import '../../services/mock/mock_appointment_service.dart';
import '../../services/mock/mock_auth_service.dart';
import '../../services/mock/mock_device_registration_service.dart';
import '../../services/mock/mock_favorites_service.dart';
import '../../services/mock/mock_image_upload_service.dart';
import '../../services/mock/mock_messaging_service.dart';
import '../../services/mock/mock_notification_service.dart';
import '../../services/mock/mock_pro_artist_service.dart';
import '../../services/mock/mock_pro_kyc_service.dart';
import '../../services/mock/mock_pro_service.dart';
import '../../services/mock/mock_provider_service.dart';
import '../../services/mock/mock_push_notification_service.dart';
import '../../services/mock/mock_review_service.dart';
import '../../services/mock/mock_subscription_service.dart';
import '../../services/secure_session_store.dart';
import '../config/app_config.dart';
import '../push/push_registration.dart';

/// Service Locator for Dependency Injection.
///
/// Services are mock by default. When `AppConfig.useApiBackend` is on, the
/// interfaces that have a backend slice are wired to their `Api*` impl instead;
/// everything else stays mock. The swap is purely here — callers are unchanged.
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  // Services
  late final AuthServiceInterface authService;
  late final ProviderServiceInterface providerService;
  late final AppointmentServiceInterface appointmentService;
  late final FavoritesServiceInterface favoritesService;
  late final NotificationServiceInterface notificationService;
  late final ProServiceInterface proService;
  late final ProArtistServiceInterface proArtistService;
  late final ProKycServiceInterface proKycService;
  late final SubscriptionServiceInterface subscriptionService;
  late final ImageUploadServiceInterface imageUploadService;
  late final ReviewServiceInterface reviewService;
  late final MessagingServiceInterface messagingService;
  late final PushNotificationServiceInterface pushNotificationService;
  late final DeviceRegistrationServiceInterface deviceRegistrationService;
  late final PushRegistration pushRegistration;
  late final DeviceRegistrationServiceInterface proDeviceRegistrationService;
  late final PushRegistration proPushRegistration;

  void setup() {
    // Consumer auth (B2) + provider auth (B-prov), each on the real backend.
    // The provider session lives under its own secure key so it never
    // overwrites the consumer session on a shared device.
    authService = AppConfig.useApiBackend
        ? ApiAuthService(
            sessionStore: SecureSessionStore(),
            providerSessionStore:
                SecureSessionStore(key: 'myweli_provider_session'),
          )
        : MockAuthService(sessionStore: SecureSessionStore());
    // Provider reads are the first slice swapped to the real backend (B1).
    providerService =
        AppConfig.useApiBackend ? ApiProviderService() : MockProviderService();
    // Appointments (book/list/cancel/reschedule/slots) — B-appt slice.
    appointmentService = AppConfig.useApiBackend
        ? ApiAppointmentService(sessionStore: SecureSessionStore())
        : MockAppointmentService();
    // Favorites move from on-device prefs to the account (consumer session +
    // silent refresh) when the backend is on.
    favoritesService = AppConfig.useApiBackend
        ? ApiFavoritesService(sessionStore: SecureSessionStore())
        : MockFavoritesService();
    notificationService = AppConfig.useApiBackend
        ? ApiNotificationService(sessionStore: SecureSessionStore())
        : MockNotificationService();
    // Pro appointment surface (list + accept/reject/complete/no-show) on the
    // real backend with provider silent refresh; the rest delegates to mock.
    proService = AppConfig.useApiBackend
        ? ApiProService(
            providerSessionStore:
                SecureSessionStore(key: 'myweli_provider_session'),
          )
        : MockProService();
    // Staff (artists) CRUD on the real backend (provider session + silent
    // refresh) when the backend is on.
    proArtistService = AppConfig.useApiBackend
        ? ApiProArtistService(
            providerSessionStore:
                SecureSessionStore(key: 'myweli_provider_session'),
          )
        : MockProArtistService();
    // KYC on the real backend: docs upload to private storage, submit + status
    // (provider session + silent refresh).
    proKycService = AppConfig.useApiBackend
        ? ApiProKycService(
            providerSessionStore:
                SecureSessionStore(key: 'myweli_provider_session'),
          )
        : MockProKycService();
    // Provider plan & trial status (read-only; derived server-side).
    subscriptionService = AppConfig.useApiBackend
        ? ApiProSubscriptionService(
            providerSessionStore:
                SecureSessionStore(key: 'myweli_provider_session'),
          )
        : MockSubscriptionService();
    // Real upload pipeline (compress → presigned direct-to-R2) with provider
    // silent refresh; mock echoes the source in demo mode.
    imageUploadService = AppConfig.useApiBackend
        ? ApiImageUploadService(
            providerSessionStore:
                SecureSessionStore(key: 'myweli_provider_session'),
          )
        : MockImageUploadService();
    // Reviews on the real backend (consumer session for submit; the list is
    // public) when the backend is on.
    reviewService = AppConfig.useApiBackend
        ? ApiReviewService(sessionStore: SecureSessionStore())
        : MockReviewService();
    messagingService = MockMessagingService();
    // Push (FR-NOTIF-001, app side). The FCM token/permission seam stays on the
    // mock until the real FcmPushNotificationService + Firebase config land in
    // the accounts phase (docs/design/push-notifications-app.md); only this line
    // changes then. Device registration (/me/devices) is real when the backend
    // is on, scoped to the consumer session.
    pushNotificationService = MockPushNotificationService();
    deviceRegistrationService = AppConfig.useApiBackend
        ? ApiDeviceRegistrationService(sessionStore: SecureSessionStore())
        : MockDeviceRegistrationService();
    pushRegistration = PushRegistration(
      push: pushNotificationService,
      devices: deviceRegistrationService,
    );
    // Pro app: same device token, but registered under the PROVIDER session so
    // /me/devices is scoped to the provider principal (#2b).
    proDeviceRegistrationService = AppConfig.useApiBackend
        ? ApiDeviceRegistrationService(
            sessionStore: SecureSessionStore(key: 'myweli_provider_session'),
          )
        : MockDeviceRegistrationService();
    proPushRegistration = PushRegistration(
      push: pushNotificationService,
      devices: proDeviceRegistrationService,
    );
  }
}

void setupDependencyInjection() {
  ServiceLocator().setup();
}

ServiceLocator get serviceLocator => ServiceLocator();
