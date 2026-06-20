import '../../models/api_response.dart';
import '../../models/artist.dart';
import '../../core/constants/app_constants.dart';
import '../interfaces/pro_artist_service_interface.dart';
import 'mock_data.dart';

class MockProArtistService implements ProArtistServiceInterface {
  final Map<String, List<Artist>> _store = {};

  List<Artist> _getOrInit(String providerId) {
    if (!_store.containsKey(providerId)) {
      _store[providerId] = List.from(MockData.getArtistsForProvider(providerId));
    }
    return _store[providerId]!;
  }

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
    final artists = _getOrInit(providerId);
    final id = 'artist_${DateTime.now().millisecondsSinceEpoch}';
    final artist = Artist(
      id: id,
      name: data['name'] as String,
      imageUrl: data['imageUrl'] as String?,
      providerId: providerId,
      specialization: data['specialization'] as String?,
      rating: null,
      reviewCount: null,
    );
    artists.add(artist);
    return ApiResponse.success(artist);
  }

  @override
  Future<ApiResponse<Artist>> updateArtist(
    String artistId,
    Map<String, dynamic> data,
  ) async {
    await Future.delayed(AppConstants.mockDelay);
    Artist? found;
    for (final entry in _store.entries) {
      final idx = entry.value.indexWhere((a) => a.id == artistId);
      if (idx != -1) {
        final a = entry.value[idx];
        found = a.copyWith(
          name: data['name'] as String? ?? a.name,
          imageUrl: data['imageUrl'] as String? ?? a.imageUrl,
          specialization: data['specialization'] as String? ?? a.specialization,
        );
        entry.value[idx] = found;
        break;
      }
    }
    if (found == null) {
      return ApiResponse.error('Artiste non trouvé');
    }
    return ApiResponse.success(found);
  }

  @override
  Future<ApiResponse<bool>> deleteArtist(String artistId) async {
    await Future.delayed(AppConstants.mockDelay);
    for (final artists in _store.values) {
      final idx = artists.indexWhere((a) => a.id == artistId);
      if (idx != -1) {
        artists.removeAt(idx);
        return ApiResponse.success(true);
      }
    }
    return ApiResponse.error('Artiste non trouvé');
  }
}
