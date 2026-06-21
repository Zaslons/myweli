import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/review.dart';

void main() {
  test('round-trips through JSON with the upgraded fields', () {
    final review = Review(
      id: 'r1',
      providerId: 'p1',
      userId: 'u1',
      userName: 'Marie',
      rating: 5,
      text: 'Super',
      verified: true,
      artistId: 'a1',
      artistName: 'Kouassi Jean',
      photoUrls: const ['asset:x.png'],
      createdAt: DateTime(2025, 2, 4),
    );

    final back = Review.fromJson(review.toJson());

    expect(back, review);
    expect(back.verified, isTrue);
    expect(back.artistName, 'Kouassi Jean');
    expect(back.photoUrls, ['asset:x.png']);
  });

  test('fromJson defaults the new fields when absent', () {
    final review = Review.fromJson({
      'id': 'r1',
      'providerId': 'p1',
      'userId': 'u1',
      'userName': 'Marie',
      'rating': 4,
      'text': 'ok',
      'createdAt': DateTime(2025).toIso8601String(),
    });

    expect(review.verified, isFalse);
    expect(review.artistName, isNull);
    expect(review.photoUrls, isEmpty);
  });
}
