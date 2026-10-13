import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/design/salon-rating-new-and-visits-card.md §8 — a rating is formatted
/// in ONE place (`Formatters.formatRating`, the French « 4,8 ») and drawn by
/// ONE widget (`AppRating`, « Nouveau » at 0 reviews). Before this slice eight
/// sites called `rating.toStringAsFixed(1)` — the anglophone « 4.8 » — and five
/// printed « ★ 0.0 · 0 avis » for a salon nobody had reviewed yet.
void main() {
  /// Comments are not code (salon_time_pin_test.dart's lesson): the comment
  /// that explains a removed idiom must not keep a file looking like an
  /// offender.
  String stripDartComments(String src) => src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp('//[^\n]*'), '');

  /// A line that formats a number with `toStringAsFixed(` AND names a rating
  /// (a variable, a field or a map key: `rating`, `averageRating`, `'rating'`).
  /// Line-based on purpose: one regex cannot follow `(r['rating'] as num?)?.`.
  bool formatsRatingByHand(String line) =>
      line.contains('toStringAsFixed(') &&
      line.toLowerCase().contains('rating');

  List<String> offenders() => [
    for (final e in Directory('lib').listSync(recursive: true))
      if (e is File &&
          e.path.endsWith('.dart') &&
          !e.path.endsWith('core/utils/formatters.dart') &&
          stripDartComments(
            e.readAsStringSync(),
          ).split('\n').any(formatsRatingByHand))
        e.path,
  ];

  test('no rating is formatted by hand in lib/', () {
    expect(
      offenders(),
      isEmpty,
      reason:
          'use Formatters.formatRating / AppRating — `toStringAsFixed(1)` '
          'prints « 4.8 » with a point on a French product',
    );
  });

  test('the matcher catches every shape this slice removed (not vacuous)', () {
    for (final shape in [
      'salon.rating.toStringAsFixed(1)',
      'p.rating.toStringAsFixed(1)',
      'averageRating.toStringAsFixed(1)',
      "(r['rating'] as num?)?.toStringAsFixed(1)",
      r"'${rating.toStringAsFixed(1)} / 5'",
    ]) {
      expect(formatsRatingByHand(shape), isTrue, reason: shape);
    }
    expect(
      formatsRatingByHand("'\${(v * 100).toStringAsFixed(1)}%'"),
      isFalse,
      reason: 'a percentage is not a rating',
    );
  });
}
