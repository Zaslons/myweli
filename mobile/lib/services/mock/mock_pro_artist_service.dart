import '../../core/constants/app_constants.dart';
import '../../core/constants/failure_messages.dart';
import '../../models/api_response.dart';
import '../../models/artist.dart';
import '../../models/availability.dart';
import '../../models/pro_membership.dart';
import '../interfaces/pro_artist_service_interface.dart';
import 'mock_data.dart';
import 'mock_ids.dart';
import 'mock_session.dart';

class MockProArtistService implements ProArtistServiceInterface {
  final Map<String, List<Artist>> _store = {};

  List<Artist> _getOrInit(String providerId) {
    if (!_store.containsKey(providerId)) {
      _store[providerId] = List.from(
        MockData.getArtistsForProvider(providerId),
      );
    }
    return _store[providerId]!;
  }

  /// Mirror the edited roster into MockData.providers so consumer slot
  /// computation (which reads provider.artists) sees per-staff hours.
  void _syncProvider(String providerId) {
    final i = MockData.providers.indexWhere((p) => p.id == providerId);
    if (i != -1 && _store.containsKey(providerId)) {
      MockData.providers[i] = MockData.providers[i].copyWith(
        artists: List.from(_store[providerId]!),
      );
    }
  }

  /// The server's refusal in the words `ApiProArtistService` gives it
  /// (`errorFromResponse` with no words of its own: the generic sentence).
  ApiResponse<T> _refused<T>(String code) =>
      ApiResponse.error(kGenericErrorMessage, code: code);

  @override
  Future<ApiResponse<List<Artist>>> getArtists(String providerId) async {
    await Future.delayed(AppConstants.mockDelay);
    final artists = _getOrInit(providerId);
    return ApiResponse.success(artists);
  }

  @override
  Future<ApiResponse<Artist>> createArtist(
    String providerId,
    Map<String, dynamic> data,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    if (!await mockCan(providerId, ProCap.catalogueManage)) {
      return _refused('forbidden');
    }
    final artists = _getOrInit(providerId);
    final id = MockIds.next('artist');
    final artist = Artist(
      id: id,
      name: data['name'] as String,
      imageUrl: data['imageUrl'] as String?,
      providerId: providerId,
      specialization: data['specialization'] as String?,
      rating: null,
      reviewCount: null,
      workingHours:
          (data['workingHours'] as Map<int, List<TimeSlot>>?) ?? const {},
    );
    artists.add(artist);
    _syncProvider(providerId);
    return ApiResponse.success(artist);
  }

  @override
  Future<ApiResponse<Artist>> updateArtist(
    String artistId,
    Map<String, dynamic> data,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    // In the salon the session acts in, as the server's path says
    // (`ApiProArtistService` sends the acting salon): another salon's artist
    // is `not_found` there. It searched every salon, so a bare manager could
    // rename anyone's (docs/design/hygiene-batch9.md §2.5).
    final salonId = await mockActingSalonId();
    if (!await mockCan(salonId, ProCap.catalogueManage)) {
      return _refused('forbidden');
    }
    final artists = _getOrInit(salonId);
    final idx = artists.indexWhere((a) => a.id == artistId);
    if (idx == -1) return _refused('not_found');
    final a = artists[idx];
    final found = a.copyWith(
      name: data['name'] as String? ?? a.name,
      imageUrl: data['imageUrl'] as String? ?? a.imageUrl,
      specialization: data['specialization'] as String? ?? a.specialization,
      workingHours:
          data['workingHours'] as Map<int, List<TimeSlot>>? ?? a.workingHours,
    );
    artists[idx] = found;
    _syncProvider(salonId);
    return ApiResponse.success(found);
  }

  @override
  Future<ApiResponse<bool>> deleteArtist(String artistId) async {
    await Future.delayed(AppConstants.mockDelay);
    final salonId = await mockActingSalonId();
    if (!await mockCan(salonId, ProCap.catalogueManage)) {
      return _refused('forbidden');
    }
    final artists = _getOrInit(salonId);
    final idx = artists.indexWhere((a) => a.id == artistId);
    if (idx == -1) return _refused('not_found');
    artists.removeAt(idx);
    // The client's reads follow, as they do a create or an update (a deleted
    // artist stayed bookable in the mock).
    _syncProvider(salonId);
    return ApiResponse.success(true);
  }
}
