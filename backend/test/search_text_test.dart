import 'package:myweli_backend/src/search_fold_table.dart';
import 'package:myweli_backend/src/search_text.dart';
import 'package:test/test.dart';

/// The cleaning and the fold both twins share
/// (docs/design/consumer-search.md §3, A4-api). The fold is held to
/// PostgreSQL's own `lower(unaccent(…))` by the Postgres suite, on every
/// character; these are the cases a person types.
void main() {
  group('cleanSearchText', () {
    test('no text, an empty one or a blank one is no filter', () {
      expect(cleanSearchText(null), isNull);
      expect(cleanSearchText(''), isNull);
      expect(cleanSearchText('  \t '), isNull);
    });

    test('trims, and turns every run of spaces into one', () {
      expect(cleanSearchText('  tresses   à  Cocody '), 'tresses à Cocody');
    });

    test('keeps the first 100 characters, counted as characters', () {
      final t = 'a' * 150;
      expect(cleanSearchText(t), 'a' * 100);
      expect(cleanSearchText('a' * 100), 'a' * 100);
      // 99 letters and an emoji (two UTF-16 units): kept whole at the cut.
      final emoji = '${'a' * 99}😀${'b' * 10}';
      expect(cleanSearchText(emoji), '${'a' * 99}😀');
    });

    test('a space left at the cut is trimmed', () {
      expect(cleanSearchText('${'a' * 99} b'), 'a' * 99);
    });
  });

  group('foldSearchText', () {
    test('lower case, without accents', () {
      expect(foldSearchText('Beauté DIVINE'), 'beaute divine');
      expect(foldSearchText('Ça coûte'), 'ca coute');
    });

    test('ligatures and the apostrophe a phone types', () {
      expect(foldSearchText('Sœurs Cæsar'), 'soeurs caesar');
      expect(foldSearchText('L’Atelier'), "l'atelier");
    });

    test('a decomposed accent is dropped, as unaccent drops it', () {
      expect(foldSearchText('Café'), 'cafe');
    });

    test('full-width forms become the ASCII they look like', () {
      expect(foldSearchText('＿％＼'), r'_%\');
    });

    test('folds before lower-casing, as lower(unaccent()) does', () {
      // unaccent turns « Ɩ » (U+0196) into « I »; lower-cased first, it
      // would be « ɩ », which unaccent leaves alone. One of four such
      // letters in the swept ranges, all found by trying both orders.
      expect(foldSearchText('Ɩ'), 'i');
    });

    test('the table is not empty', () {
      expect(kUnaccentFold.length, greaterThan(1000));
    });
  });

  group('salonMatchesSearch', () {
    test('a service with no active flag is active', () {
      expect(
        salonMatchesSearch({
          'services': [
            {'name': 'Tresses'},
          ],
        }, 'tresses'),
        isTrue,
      );
    });

    test('a field that is not text matches nothing', () {
      expect(salonMatchesSearch({'name': 42, 'commune': null}, '42'), isFalse);
      expect(salonMatchesSearch({'commune': null}, 'null'), isFalse);
    });
  });
}
