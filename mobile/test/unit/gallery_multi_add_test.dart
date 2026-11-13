import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/gallery_batch.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/providers/pro_gallery_provider.dart';
import 'package:myweli/services/interfaces/image_upload_service_interface.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';

class _MockProService extends Mock implements ProServiceInterface {}

class _MockUpload extends Mock implements ImageUploadServiceInterface {}

/// docs/design/gallery-multi-select.md — « Galerie » takes several photos:
/// the first ones up to the room left under 20, one after another, each saved
/// as it lands with the list the server STORED, one summary at the end.
void main() {
  late _MockProService pro;
  late _MockUpload upload;
  const id = SalonId('provider1');
  const cdn = 'https://cdn.myweli.com';

  /// What the server holds; a pending url is moved ONCE, sent again it is
  /// refused — production before #784.
  late List<String> stored;
  late Set<String> consumed;
  late List<List<String>> saves;
  late List<String> uploads;
  late Map<String, Completer<void>> holds;
  late Set<String> failUpload;

  setUpAll(() {
    pro = _MockProService();
    upload = _MockUpload();
    serviceLocator.proService = pro;
    serviceLocator.imageUploadService = upload;
  });

  setUp(() {
    reset(pro);
    reset(upload);
    stored = ['$cdn/gallery/p1/a.jpg'];
    consumed = {};
    saves = [];
    uploads = [];
    holds = {};
    failUpload = {};
    when(
      () => pro.getGalleryPhotos(any()),
    ).thenAnswer((_) async => ApiResponse.success(List.of(stored)));
    when(() => pro.updateGalleryPhotos(any(), any())).thenAnswer((inv) async {
      final sent = inv.positionalArguments[1] as List<String>;
      saves.add(List.of(sent));
      final out = <String>[];
      for (final u in sent) {
        if (stored.contains(u)) {
          out.add(u);
        } else if (u.contains('/pending/') && !consumed.contains(u)) {
          out.add(u.replaceFirst('pending/', ''));
        } else {
          return ApiResponse.error('upload_not_found');
        }
      }
      consumed.addAll(sent.where((u) => u.contains('/pending/')));
      stored = out;
      return ApiResponse.success(List.of(out));
    });
    when(
      () => upload.uploadImage(
        source: any(named: 'source'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((inv) async {
      final source = inv.namedArguments[#source] as String;
      uploads.add(source);
      final hold = holds[source];
      if (hold != null) await hold.future;
      if (failUpload.contains(source)) {
        return ApiResponse.error('Échec de l’envoi');
      }
      return ApiResponse.success('$cdn/pending/gallery/p1/$source');
    });
  });

  Future<ProGalleryProvider> loaded() async {
    final g = ProGalleryProvider();
    await g.load(id);
    return g;
  }

  group('addPhotos', () {
    test('one after another, in the order picked, each saved with the '
        'stored addresses', () async {
      final g = await loaded();
      final r = await g.addPhotos(id, ['b.jpg', 'c.jpg', 'd.jpg']);
      expect(r.total, 3);
      expect(r.added, 3);
      expect(r.dropped, 0);
      expect(uploads, ['b.jpg', 'c.jpg', 'd.jpg']);
      expect(saves[1], [
        '$cdn/gallery/p1/a.jpg',
        '$cdn/gallery/p1/b.jpg', // stored, never the pending one
        '$cdn/pending/gallery/p1/c.jpg',
      ]);
      expect(g.photos, [
        '$cdn/gallery/p1/a.jpg',
        '$cdn/gallery/p1/b.jpg',
        '$cdn/gallery/p1/c.jpg',
        '$cdn/gallery/p1/d.jpg',
      ]);
      expect(g.isUploading, isFalse);
    });

    test(
      'never two at once, busy throughout, and it says where it is',
      () async {
        final g = await loaded();
        holds['c.jpg'] = Completer<void>();
        final run = g.addPhotos(id, ['b.jpg', 'c.jpg', 'd.jpg']);
        await pumpEventQueue();
        expect(uploads, ['b.jpg', 'c.jpg'], reason: 'd waits for c');
        expect(g.isUploading, isTrue);
        expect((g.batchAt, g.batchOf), (2, 3));
        expect(g.photos, contains('$cdn/gallery/p1/b.jpg'));
        holds['c.jpg']!.complete();
        await run;
        expect((g.batchAt, g.batchOf), (0, 0));
      },
    );

    test('more than the room left: the first ones, and how many were left '
        'out', () async {
      stored = [for (var i = 0; i < 18; i++) '$cdn/gallery/p1/s$i.jpg'];
      final g = await loaded();
      final r = await g.addPhotos(id, ['w', 'x', 'y', 'z']);
      expect((r.total, r.added, r.dropped), (2, 2, 2));
      expect(uploads, ['w', 'x']);
      expect(g.photos, hasLength(kMaxGalleryPhotos));
    });

    test('a failed photo is skipped; the others go on', () async {
      failUpload = {'c.jpg'};
      final g = await loaded();
      final r = await g.addPhotos(id, ['b.jpg', 'c.jpg', 'd.jpg']);
      expect((r.total, r.added), (3, 2));
      expect(uploads, ['b.jpg', 'c.jpg', 'd.jpg']);
      expect(saves, hasLength(2));
    });

    test('the screen left mid-way: the photo on its way finishes, the rest '
        'are not sent', () async {
      final g = await loaded();
      holds['c.jpg'] = Completer<void>();
      final run = g.addPhotos(id, ['b.jpg', 'c.jpg', 'd.jpg']);
      await pumpEventQueue();
      g.stopBatch();
      holds['c.jpg']!.complete();
      final r = await run;
      expect(r.stopped, isTrue);
      expect(uploads, ['b.jpg', 'c.jpg']);
      expect(g.photos, hasLength(3));
      expect(g.isUploading, isFalse);
    });

    test('a salon switch stops it too', () async {
      final g = await loaded();
      holds['c.jpg'] = Completer<void>();
      final run = g.addPhotos(id, ['b.jpg', 'c.jpg', 'd.jpg']);
      await pumpEventQueue();
      g.resetForSalonSwitch();
      holds['c.jpg']!.complete();
      await run;
      expect(uploads, ['b.jpg', 'c.jpg']);
      expect(g.isUploading, isFalse);
      expect((g.batchAt, g.batchOf), (0, 0));
    });
  });

  group('the pure rules', () {
    test('fitInGallery keeps the first ones up to 20', () {
      // A record holding a List compares the List by identity: field by field.
      void fits(List<int> picked, int current, List<int> kept, int dropped) {
        final f = fitInGallery(picked, current);
        expect(f.kept, kept, reason: '$picked at $current');
        expect(f.dropped, dropped, reason: '$picked at $current');
      }

      fits([1, 2, 3, 4], 18, [1, 2], 2);
      fits([1, 2], 0, [1, 2], 0);
      fits([1], 20, [], 1);
      fits([1, 2, 3], 17, [1, 2, 3], 0);
    });

    test('overCapMessage agrees with the count', () {
      expect(
        overCapMessage(1),
        '20 photos maximum : 1 photo n’a pas été ajoutée.',
      );
      expect(
        overCapMessage(3),
        '20 photos maximum : 3 photos n’ont pas été ajoutées.',
      );
    });

    test('gallerySummary — the website\'s sentences', () {
      expect(gallerySummary(total: 1, added: 1), isNull);
      expect(gallerySummary(total: 1, added: 0), isNull);
      expect(gallerySummary(total: 1, added: 1, dropped: 2), (
        message: '20 photos maximum : 2 photos n’ont pas été ajoutées.',
        isError: false,
      ));
      expect(gallerySummary(total: 2, added: 2), (
        message: '2 photos ajoutées.',
        isError: false,
      ));
      expect(gallerySummary(total: 3, added: 1), (
        message: '1 photo ajoutée sur 3. 2 n’ont pas pu être envoyées.',
        isError: true,
      ));
      expect(gallerySummary(total: 5, added: 4, dropped: 1), (
        message:
            '4 photos ajoutées sur 5. 1 n’a pas pu être envoyée. '
            '20 photos maximum : 1 photo n’a pas été ajoutée.',
        isError: true,
      ));
      expect(gallerySummary(total: 2, added: 0), (
        message: 'Aucune photo n’a pu être envoyée.',
        isError: true,
      ));
    });
  });
}
