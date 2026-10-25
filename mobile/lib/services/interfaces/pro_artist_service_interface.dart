import '../../core/utils/salon_id.dart';
import '../../models/api_response.dart';
import '../../models/artist.dart';

abstract class ProArtistServiceInterface {
  Future<ApiResponse<List<Artist>>> getArtists(SalonId providerId);
  Future<ApiResponse<Artist>> createArtist(
    SalonId providerId,
    Map<String, dynamic> data,
  );
  Future<ApiResponse<Artist>> updateArtist(
    String artistId,
    Map<String, dynamic> data,
  );
  Future<ApiResponse<bool>> deleteArtist(String artistId);
}
