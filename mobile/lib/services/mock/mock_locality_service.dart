import '../../core/constants/app_constants.dart';
import '../../core/constants/communes.dart';
import '../../core/utils/salon_time.dart';
import '../../core/utils/slug.dart';
import '../../models/api_response.dart';
import '../../models/locality.dart';
import '../interfaces/locality_service_interface.dart';

/// Mock locality tree (multi-pays MP2) — mirrors the backend seed exactly:
/// CI (+225 · XOF · the 4 operators) → Abidjan (`Africa/Abidjan`) → the 11
/// communes, built from the historical [abidjanCommunes] constants (their
/// ONLY remaining consumer — the live app reads GET /localities), each id and
/// slug by the backend's `slugify` (its twin, `core/utils/slug.dart`).
class MockLocalityService implements LocalityServiceInterface {
  @override
  Future<ApiResponse<List<LocalityCountry>>> getLocalities() async {
    await Future.delayed(AppConstants.mockDelay);
    return ApiResponse.success([
      LocalityCountry(
        code: 'CI',
        name: 'Côte d’Ivoire',
        currency: 'XOF',
        phonePrefix: AppConstants.defaultCountryCode,
        operators: const [
          MomoOperatorInfo(id: 'wave', label: 'Wave', deepLinkKind: 'wave'),
          MomoOperatorInfo(id: 'orangeMoney', label: 'Orange Money'),
          MomoOperatorInfo(id: 'mtnMoMo', label: 'MTN MoMo'),
          MomoOperatorInfo(id: 'moov', label: 'Moov Money'),
        ],
        cities: [
          LocalityCity(
            id: 'abidjan',
            slug: 'abidjan',
            name: 'Abidjan',
            timezone: kSalonTz,
            lat: 5.336,
            lng: -4.026,
            areas: [
              for (final c in abidjanCommunes)
                LocalityArea(
                  id: slugify(c.name),
                  slug: slugify(c.name),
                  name: c.name,
                  labelKind: 'commune',
                  lat: c.latitude,
                  lng: c.longitude,
                ),
            ],
          ),
        ],
      ),
    ]);
  }
}
