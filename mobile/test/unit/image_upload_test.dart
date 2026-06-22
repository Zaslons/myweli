import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/pro_gallery_provider.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

void main() {
  group('MockImageUploadService', () {
    late MockImageUploadService service;
    setUp(() => service = MockImageUploadService());

    test('reports progress up to 1.0 and returns the hosted URL', () async {
      final progress = <double>[];
      final res = await service.uploadImage(
        source: 'asset:assets/images/providers/spa_relax_photo.png',
        onProgress: progress.add,
      );

      expect(res.success, isTrue);
      expect(res.data, 'asset:assets/images/providers/spa_relax_photo.png');
      expect(progress.last, 1.0);
      expect(progress, isNotEmpty);
    });

    test('rejects an empty source', () async {
      final res = await service.uploadImage(source: '');
      expect(res.success, isFalse);
      expect(res.error, 'Image invalide');
    });
  });

  group('MockProService gallery persistence', () {
    test('updateGalleryPhotos round-trips via getGalleryPhotos', () async {
      final service = MockProService();
      await service.updateGalleryPhotos('provider3', const [
        'asset:assets/images/providers/spa_relax_photo.png',
        'asset:assets/images/providers/beaute_divine_photo.png',
      ]);

      final got = await service.getGalleryPhotos('provider3');
      expect(got.data, hasLength(2));
      expect(
          got.data!.first, 'asset:assets/images/providers/spa_relax_photo.png');
    });
  });

  group('ProGalleryProvider', () {
    setUpAll(() {
      serviceLocator.proService = MockProService();
      serviceLocator.imageUploadService = MockImageUploadService();
    });

    test('loads, uploads-and-adds, then removes a photo', () async {
      final gallery = ProGalleryProvider();
      await gallery.load('provider1');
      expect(gallery.loadFailed, isFalse);
      final initial = gallery.photos.length;

      final added = await gallery.addPhoto(
        'provider1',
        'asset:assets/images/providers/spa_relax_photo.png',
      );
      expect(added, isTrue);
      expect(gallery.photos.length, initial + 1);
      expect(gallery.isUploading, isFalse);

      final removed =
          await gallery.removePhoto('provider1', gallery.photos.length - 1);
      expect(removed, isTrue);
      expect(gallery.photos.length, initial);
    });

    test('an empty source fails the upload without adding', () async {
      final gallery = ProGalleryProvider();
      await gallery.load('provider1');
      final initial = gallery.photos.length;

      final ok = await gallery.addPhoto('provider1', '');
      expect(ok, isFalse);
      expect(gallery.photos.length, initial);
      expect(gallery.error, isNotNull);
    });
  });
}
