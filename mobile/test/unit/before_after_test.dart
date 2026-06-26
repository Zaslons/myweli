import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/before_after_pair.dart';
import 'package:myweli/providers/pro_before_after_provider.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

void main() {
  group('BeforeAfterPair', () {
    test('round-trips JSON; omits an empty caption', () {
      const withCaption = BeforeAfterPair(
        before: 'b.jpg',
        after: 'a.jpg',
        caption: 'Tresses',
      );
      expect(BeforeAfterPair.fromJson(withCaption.toJson()), withCaption);

      const noCaption = BeforeAfterPair(before: 'b.jpg', after: 'a.jpg');
      expect(noCaption.toJson().containsKey('caption'), isFalse);
      // A blank caption decodes to null (not '').
      final blank = BeforeAfterPair.fromJson(
        const {'before': 'b.jpg', 'after': 'a.jpg', 'caption': '   '},
      );
      expect(blank.caption, isNull);
    });
  });

  group('MockProService before/after persistence', () {
    test('updateBeforeAfters round-trips via getBeforeAfters', () async {
      final service = MockProService();
      await service.updateBeforeAfters('provider3', const [
        BeforeAfterPair(before: 'b.jpg', after: 'a.jpg', caption: 'X'),
      ]);
      final got = await service.getBeforeAfters('provider3');
      expect(got.data, hasLength(1));
      expect(got.data!.first.caption, 'X');
    });
  });

  group('ProBeforeAfterProvider', () {
    setUpAll(() {
      serviceLocator.proService = MockProService();
      serviceLocator.imageUploadService = MockImageUploadService();
    });

    test('loads, adds a pair (two uploads), then removes it', () async {
      final p = ProBeforeAfterProvider();
      await p.load('provider1');
      expect(p.loadFailed, isFalse);
      final initial = p.pairs.length;

      final added = await p.addPair(
        'provider1',
        beforeSource: 'asset:assets/images/providers/spa_relax_photo.png',
        afterSource: 'asset:assets/images/providers/beaute_divine_photo.png',
        caption: 'Soin visage',
      );
      expect(added, isTrue);
      expect(p.pairs.length, initial + 1);
      expect(p.pairs.last.caption, 'Soin visage');
      expect(p.isUploading, isFalse);

      final removed = await p.removePair('provider1', p.pairs.length - 1);
      expect(removed, isTrue);
      expect(p.pairs.length, initial);
    });

    test('an empty image source fails the add without persisting', () async {
      final p = ProBeforeAfterProvider();
      await p.load('provider1');
      final initial = p.pairs.length;

      final ok = await p.addPair(
        'provider1',
        beforeSource: '',
        afterSource: 'asset:assets/images/providers/spa_relax_photo.png',
      );
      expect(ok, isFalse);
      expect(p.pairs.length, initial);
      expect(p.error, isNotNull);
    });
  });
}
