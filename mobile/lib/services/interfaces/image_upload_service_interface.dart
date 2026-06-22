import '../../models/api_response.dart';

abstract class ImageUploadServiceInterface {
  /// Uploads the chosen image [source] and returns the hosted URL.
  ///
  /// Progress (0..1) is reported via [onProgress]. The real implementation
  /// compresses/resizes the image and uploads it to the CDN (after a
  /// virus/content scan); the returned URL is server-authoritative.
  Future<ApiResponse<String>> uploadImage({
    required String source,
    void Function(double progress)? onProgress,
  });
}
