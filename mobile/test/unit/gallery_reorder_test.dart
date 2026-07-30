import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/providers/pro_gallery_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';

class _MockProService extends Mock implements ProServiceInterface {}

/// Audit 3.6: photo reorder — the first photo is the listing cover.
void main() {
  final service = _MockProService();
  late ProGalleryProvider gallery;

  setUpAll(() {
    // The locator's fields are late final — register once for the file.
    serviceLocator.proService = service;
    serviceLocator.imageUploadService = MockImageUploadService();
  });

  setUp(() async {
    reset(service);
    gallery = ProGalleryProvider();
    when(
      () => service.getGalleryPhotos('p1'),
    ).thenAnswer((_) async => ApiResponse.success(['a', 'b', 'c']));
    await gallery.load('p1');
  });

  test(
    'movePhoto swaps with the neighbour and persists the new order',
    () async {
      when(
        () => service.updateGalleryPhotos('p1', ['b', 'a', 'c']),
      ).thenAnswer((_) async => ApiResponse.success(['b', 'a', 'c']));

      expect(await gallery.movePhoto('p1', 1, -1), isTrue);
      expect(gallery.photos, ['b', 'a', 'c']);
    },
  );

  test(
    'movePhoto rejects out-of-bounds moves without a network call',
    () async {
      expect(await gallery.movePhoto('p1', 0, -1), isFalse);
      expect(await gallery.movePhoto('p1', 2, 1), isFalse);
      verifyNever(() => service.updateGalleryPhotos(any(), any()));
      expect(gallery.photos, ['a', 'b', 'c']);
    },
  );

  test('movePhoto keeps the order and surfaces the error on failure', () async {
    when(
      () => service.updateGalleryPhotos('p1', any()),
    ).thenAnswer((_) async => ApiResponse.error('offline'));

    expect(await gallery.movePhoto('p1', 0, 1), isFalse);
    expect(gallery.photos, ['a', 'b', 'c']);
    expect(gallery.error, 'offline');
  });

  // ── A6, from the adversarial review ────────────────────────────────────────
  // The first Undo shipped as `restorePhotos(providerId, snapshotTakenBefore)`.
  // The service takes the WHOLE list, so restoring a snapshot rewinds the
  // gallery rather than undoing one delete: a photo uploaded during the 10s
  // window is destroyed, a reorder is reverted — silently, by the button whose
  // whole promise is that nothing was lost.
  test('restorePhotoAt re-inserts into the CURRENT list, keeping work done '
      'during the undo window', () async {
    when(
      () => service.updateGalleryPhotos('p1', ['a', 'c']),
    ).thenAnswer((_) async => ApiResponse.success(['a', 'c']));
    expect(await gallery.removePhoto('p1', 1), isTrue); // delete 'b'
    expect(gallery.photos, ['a', 'c']);

    // …the user changes the cover before tapping « Annuler ».
    when(
      () => service.updateGalleryPhotos('p1', ['c', 'a']),
    ).thenAnswer((_) async => ApiResponse.success(['c', 'a']));
    expect(await gallery.movePhoto('p1', 1, -1), isTrue);
    expect(gallery.photos, ['c', 'a']);

    when(
      () => service.updateGalleryPhotos('p1', ['c', 'b', 'a']),
    ).thenAnswer((_) async => ApiResponse.success(['c', 'b', 'a']));
    expect(await gallery.restorePhotoAt('p1', 1, 'b'), isTrue);

    // 'b' is back AND the new cover survived. The snapshot version would have
    // PUT ['a','b','c'] — silently reverting a reorder the user never asked to
    // undo, and destroying an upload the same way.
    expect(gallery.photos, ['c', 'b', 'a']);
  });

  test('restorePhotoAt reports failure instead of failing silently', () async {
    when(
      () => service.updateGalleryPhotos('p1', ['a', 'c']),
    ).thenAnswer((_) async => ApiResponse.success(['a', 'c']));
    await gallery.removePhoto('p1', 1);

    when(
      () => service.updateGalleryPhotos('p1', ['a', 'b', 'c']),
    ).thenAnswer((_) async => ApiResponse.error('Réseau indisponible'));
    expect(
      await gallery.restorePhotoAt('p1', 1, 'b'),
      isFalse,
      reason: 'the call site needs the result to tell the user',
    );
    expect(gallery.photos, ['a', 'c'], reason: 'no optimistic lie');
  });
}
