import '../../services/interfaces/auth_service_interface.dart';
import '../../services/interfaces/provider_service_interface.dart';
import '../../services/interfaces/appointment_service_interface.dart';
import '../../services/interfaces/favorites_service_interface.dart';
import '../../services/interfaces/pro_service_interface.dart';
import '../../services/interfaces/pro_artist_service_interface.dart';
import '../../services/mock/mock_auth_service.dart';
import '../../services/mock/mock_provider_service.dart';
import '../../services/mock/mock_appointment_service.dart';
import '../../services/mock/mock_favorites_service.dart';
import '../../services/mock/mock_pro_service.dart';
import '../../services/mock/mock_pro_artist_service.dart';

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
  late final ProServiceInterface proService;
  late final ProArtistServiceInterface proArtistService;

  void setup() {
    // Use mock services for now
    authService = MockAuthService();
    providerService = MockProviderService();
    appointmentService = MockAppointmentService();
    favoritesService = MockFavoritesService();
    proService = MockProService();
    proArtistService = MockProArtistService();
  }
}

void setupDependencyInjection() {
  ServiceLocator().setup();
}

ServiceLocator get serviceLocator => ServiceLocator();



