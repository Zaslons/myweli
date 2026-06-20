import '../../models/api_response.dart';
import '../../models/artist.dart';

abstract class ProArtistServiceInterface {
  Future<ApiResponse<List<Artist>>> getArtists(String providerId);
  Future<ApiResponse<Artist>> createArtist(
    String providerId,
    Map<String, dynamic> data,
  );
  Future<ApiResponse<Artist>> updateArtist(
    String artistId,
    Map<String, dynamic> data,
  );
  Future<ApiResponse<bool>> deleteArtist(String artistId);
}
