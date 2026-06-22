import '../../models/api_response.dart';
import '../interfaces/image_upload_service_interface.dart';

class MockImageUploadService implements ImageUploadServiceInterface {
  @override
  Future<ApiResponse<String>> uploadImage({
    required String source,
    void Function(double progress)? onProgress,
  }) async {
    if (source.trim().isEmpty) {
      return ApiResponse.error('Image invalide');
    }

    // Simulate a chunked upload so the UI can show progress.
    for (final p in const [0.25, 0.5, 0.75, 1.0]) {
      await Future.delayed(const Duration(milliseconds: 150));
      onProgress?.call(p);
    }

    // The real backend compresses + scans + stores on the CDN and returns the
    // hosted URL; the mock echoes the chosen source so it renders through
    // TimedCachedImage.
    return ApiResponse.success(source);
  }
}
