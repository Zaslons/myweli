import '../../services/interfaces/appointment_service_interface.dart';
import '../../services/interfaces/auth_service_interface.dart';
import '../../services/interfaces/favorites_service_interface.dart';
import '../../services/interfaces/image_upload_service_interface.dart';
import '../../services/interfaces/messaging_service_interface.dart';
import '../../services/interfaces/notification_service_interface.dart';
import '../../services/interfaces/payment_service_interface.dart';
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
import '../../services/mock/mock_payment_service.dart';
import '../../services/mock/mock_pro_artist_service.dart';
import '../../services/mock/mock_pro_kyc_service.dart';
import '../../services/mock/mock_pro_service.dart';
import '../../services/mock/mock_provider_service.dart';
import '../../services/mock/mock_review_service.dart';
import '../../services/secure_session_store.dart';

/// Service Locator for Dependency Injection
/// Currently using mock services, will switch to API services when backend is ready
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
  late final PaymentServiceInterface paymentService;
  late final ProServiceInterface proService;
  late final ProArtistServiceInterface proArtistService;
  late final ProKycServiceInterface proKycService;
  late final ImageUploadServiceInterface imageUploadService;
  late final ReviewServiceInterface reviewService;
  late final MessagingServiceInterface messagingService;

  void setup() {
    // Use mock services for now
    authService = MockAuthService(sessionStore: SecureSessionStore());
    providerService = MockProviderService();
    appointmentService = MockAppointmentService();
    favoritesService = MockFavoritesService();
    notificationService = MockNotificationService();
    paymentService = MockPaymentService();
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
