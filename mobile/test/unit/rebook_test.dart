import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/rebook.dart';

void main() {
  group('sanitizeRebookSelection', () {
    test('keeps services and stylist that still exist', () {
      final r = sanitizeRebookSelection(
        serviceIds: ['s1', 's2'],
        artistId: 'a1',
        availableServiceIds: {'s1', 's2', 's3'},
        availableArtistIds: {'a1', 'a2'},
      );
      expect(r.serviceIds, ['s1', 's2']);
      expect(r.artistId, 'a1');
    });

    test('drops services that no longer exist', () {
      final r = sanitizeRebookSelection(
        serviceIds: ['s1', 'gone'],
        artistId: null,
        availableServiceIds: {'s1'},
        availableArtistIds: const {},
      );
      expect(r.serviceIds, ['s1']);
      expect(r.artistId, isNull);
    });

    test('clears a stylist who is gone', () {
      final r = sanitizeRebookSelection(
        serviceIds: ['s1'],
        artistId: 'gone',
        availableServiceIds: {'s1'},
        availableArtistIds: {'a1'},
      );
      expect(r.artistId, isNull);
    });
  });
}
