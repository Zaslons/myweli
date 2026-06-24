import '../../services/api/api_appointment_service.dart';
import '../../services/api/api_auth_service.dart';
import '../../services/api/api_provider_service.dart';
import '../../services/interfaces/appointment_service_interface.dart';
import '../../services/interfaces/auth_service_interface.dart';
import '../../services/interfaces/favorites_service_interface.dart';
import '../../services/interfaces/image_upload_service_interface.dart';
import '../../services/interfaces/messaging_service_interface.dart';
import '../../services/interfaces/notification_service_interface.dart';
import '../../services/interfaces/pro_artist_service_interface.dart';
import '../../services/interfaces/pro_kyc_service_interface.dart';
import '../../services/interfaces/pro_service_interface.dart';
import '../../services/interfaces/provider_service_interface.dart';
import '../../services/interfaces/review_service_interface.dart';
import '../../services/mock/mock_appointment_service.dart';
import '../../services/mock/mock_auth_service.dart';
import '../../services/mock/mock_favorites_service.dart';
import '../../services/mock/mock_image_upload_service.dart';
import '../../services/mock/mock_messaging_service.dart';
import '../../services/mock/mock_notification_service.dart';
import '../../services/mock/mock_pro_artist_service.dart';
import '../../services/mock/mock_pro_kyc_service.dart';
import '../../services/mock/mock_pro_service.dart';
import '../../services/mock/mock_provider_service.dart';
import '../../services/mock/mock_review_service.dart';
import '../../services/secure_session_store.dart';
import '../config/app_config.dart';

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
  late final ImageUploadServiceInterface imageUploadService;
  late final ReviewServiceInterface reviewService;
  late final MessagingServiceInterface messagingService;

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
    favoritesService = MockFavoritesService();
    notificationService = MockNotificationService();
    proService = MockProService();
    proArtistService = MockProArtistService();
    proKycService = MockProKycService();
    imageUploadService = MockImageUploadService();
    reviewService = MockReviewService();
    messagingService = MockMessagingService();
  }
}

void setupDependencyInjection() {
  ServiceLocator().setup();
}

ServiceLocator get serviceLocator => ServiceLocator();
