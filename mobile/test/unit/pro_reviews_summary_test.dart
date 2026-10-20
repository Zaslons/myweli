import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/review_card.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/models/review_summary.dart';
import 'package:myweli/providers/pro_reviews_provider.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

/// docs/design/salon-reviews-summary.md — the « Avis » card is the WHOLE
/// salon's: the server sends its average, count and 5→1 split with the page.
/// The app averaged the first 50 reviews it loaded and called that the count,
/// wrong for a salon with more.
Review _review(int i, int rating) => Review(
  id: 'r$i',
  appointmentId: 'a$i',
  providerId: 'p1',
  userId: 'u$i',
  userName: 'Awa',
  rating: rating,
  text: '',
  verified: true,
  serviceName: 'Tresses',
  photoUrls: const [],
  createdAt: DateTime.utc(2026, 10, 1),
);

const _summary = ReviewSummary(
  average: 4.2,
  count: 60,
  distribution: {5: 50, 4: 0, 3: 0, 2: 0, 1: 10},
);

class _Server extends MockProService {
  ReviewSummary? summary = _summary;

  @override
  Future<ApiResponse<MyReviews>> getMyReviews({
    int page = 1,
    int pageSize = 50,
  }) async => ApiResponse.success(
    MyReviews(
      items: [for (var i = 0; i < 50; i++) _review(i, 5)],
      total: 60,
      summary: summary,
    ),
  );
}

void main() {
  final server = _Server();
  setUpAll(() => serviceLocator.proService = server);

  group('ReviewSummary.fromJson — the wire shape', () {
    test('string star keys become ints; missing stars are 0', () {
      final s = ReviewSummary.fromJson({
        'average': 4.2,
        'count': 60,
        'distribution': {'5': 50, '1': 10},
      });
      expect(s.average, 4.2);
      expect(s.count, 60);
      expect(s.distribution, {5: 50, 4: 0, 3: 0, 2: 0, 1: 10});
    });

    test('an integer average reads as a double', () {
      expect(ReviewSummary.fromJson({'average': 4, 'count': 1}).average, 4.0);
    });
  });

  group('reviewCard — the summary when the server sends one', () {
    final fiftyFives = [for (var i = 0; i < 50; i++) _review(i, 5)];

    test('the server’s numbers, not the loaded page’s', () {
      final card = reviewCard(fiftyFives, _summary);
      expect(card.average, 4.2);
      expect(card.count, 60);
      expect(card.countFor(5), 50);
      expect(card.countFor(1), 10);
    });

    test('no summary (an older server): the loaded reviews, as before', () {
      final card = reviewCard([_review(1, 5), _review(2, 4)], null);
      expect(card.average, 4.5);
      expect(card.count, 2);
      expect(card.countFor(4), 1);
    });
  });

  group('ProReviewsProvider', () {
    test('keeps the summary with the reviews', () async {
      final p = ProReviewsProvider();
      await p.loadReviews('p1');
      expect(p.reviews, hasLength(50));
      expect(p.summary, _summary);
    });

    test('a salon switch drops it with the reviews', () async {
      final p = ProReviewsProvider();
      await p.loadReviews('p1');
      p.resetForSalonSwitch();
      expect(p.summary, isNull);
    });
  });
}
