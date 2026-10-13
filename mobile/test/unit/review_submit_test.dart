import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/app_constants.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/services/mock/mock_review_service.dart';

Review _review({
  required String providerId,
  int rating = 5,
  String appointmentId = '',
  String? id,
  DateTime? createdAt,
}) => Review(
  id: id ?? 'r_${DateTime.now().microsecondsSinceEpoch}',
  appointmentId: appointmentId,
  providerId: providerId,
  userId: 'u1',
  userName: 'Ama',
  rating: rating,
  text: 'Très satisfaite',
  verified: true,
  photoUrls: const ['asset:assets/images/providers/spa_relax_photo.png'],
  createdAt: createdAt ?? DateTime(2026),
);

/// The mock salon reads, counted.
class _CountedSalons extends MockProviderService {
  int byIdCalls = 0;

  @override
  Future<ApiResponse<Provider>> getProviderById(String id) {
    byIdCalls++;
    return super.getProviderById(id);
  }
}

void main() {
  // Read before any test posts: `MockData` is this isolate's, and the mock
  // service writes to it — as the server writes to its tables.
  final seededFigures = {
    for (final p in MockData.providers) p.id: (p.rating, p.reviewCount),
  };
  final seededReviews = [for (final r in MockData.reviews) r.id];

  group('MockReviewService', () {
    test('persists a valid review and rejects an invalid rating', () async {
      final service = MockReviewService();

      final ok = await service.submitReview(_review(providerId: 'provider1'));
      expect(ok.success, isTrue);
      expect(ok.data!.rating, 5);

      final bad = await service.submitReview(
        _review(providerId: 'provider1', rating: 0),
      );
      expect(bad.success, isFalse);
    });

    /// The goldens and the mock-mode store screenshots read these: the mock
    /// moves a salon's figures when a review is POSTED, never before.
    test('no seeded figure and no seeded review changed', () {
      expect(seededFigures, {
        'provider1': (4.5, 120),
        'provider2': (4.8, 89),
        'provider3': (4.7, 156),
        'provider4': (4.6, 203),
      });
      expect(seededReviews, [
        'review1',
        'review2',
        'review3',
        'review4',
        'review5',
        'review6',
        'review7',
      ]);
    });

    test('a visit reviewed again replaces the stored review — the server '
        'keeps one per appointment', () async {
      final service = MockReviewService();
      addTearDown(
        () => MockData.reviews.removeWhere((r) => r.appointmentId == 'twice'),
      );

      await service.submitReview(
        _review(providerId: 'provider2', appointmentId: 'twice', rating: 5),
      );
      await service.submitReview(
        _review(providerId: 'provider2', appointmentId: 'twice', rating: 1),
      );

      final stored = MockData.reviews.where((r) => r.appointmentId == 'twice');
      expect(stored, hasLength(1));
      expect(stored.single.rating, 1);
    });

    test('reviews that name no appointment are stored side by side: an '
        'empty id is no key — every seeded review carries one', () async {
      final i = MockData.providers.indexWhere((p) => p.id == 'provider4');
      final seeded = MockData.providers[i];
      addTearDown(() {
        MockData.providers[i] = seeded;
        MockData.reviews.removeWhere((r) => r.id.startsWith('unkeyed'));
      });
      final held = [for (final r in MockData.reviews) r.id];
      expect(
        [
          for (final r in MockData.reviews)
            if (r.appointmentId.isEmpty) r.id,
        ],
        containsAll(seededReviews),
        reason: 'what this guard stands on: no seeded review names a visit',
      );
      final service = MockReviewService();

      await service.submitReview(
        _review(providerId: 'provider4', id: 'unkeyed1'),
      );
      await service.submitReview(
        _review(providerId: 'provider4', id: 'unkeyed2'),
      );

      // Matched on '', the first would have taken `review1`'s place and the
      // second `review2`'s — and the salon's count would not have moved.
      expect(
        [for (final r in MockData.reviews) r.id],
        [...held, 'unkeyed1', 'unkeyed2'],
      );
      expect(MockData.providers[i].reviewCount, seeded.reviewCount + 2);
    });

    test('the salon’s figures move with the write: one more for a new '
        'visit, none for a visit reviewed again', () async {
      final i = MockData.providers.indexWhere((p) => p.id == 'provider3');
      final seeded = MockData.providers[i];
      addTearDown(() {
        MockData.providers[i] = seeded;
        MockData.reviews.removeWhere((r) => r.appointmentId == 'figures');
      });
      // Small figures, so that one review shows in the average.
      MockData.providers[i] = seeded.copyWith(rating: 4.0, reviewCount: 1);
      final service = MockReviewService();
      (double, int) figures() =>
          (MockData.providers[i].rating, MockData.providers[i].reviewCount);

      await service.submitReview(
        _review(providerId: 'provider3', appointmentId: 'figures', rating: 2),
      );
      expect(figures(), (3.0, 2));

      await service.submitReview(
        _review(providerId: 'provider3', appointmentId: 'figures', rating: 5),
      );
      expect(figures(), (4.5, 2)); // (3,0 × 2 − 2 + 5) / 2
    });
  });

  group('ProviderProvider review flow', () {
    final salons = _CountedSalons();

    setUpAll(() {
      serviceLocator.providerService = salons;
      serviceLocator.reviewService = MockReviewService();
      serviceLocator.imageUploadService = MockImageUploadService();
      serviceLocator.reviewImageUploadService = MockImageUploadService();
    });

    test('submitReview adds the review to the selected provider', () async {
      final provider = ProviderProvider();
      await provider.loadProviderById('provider1');
      expect(provider.selectedProvider, isNotNull);
      final before = provider.selectedProvider!.reviews.length;

      final mine = _review(providerId: 'provider1');
      final ok = await provider.submitReview(mine);

      expect(ok, isTrue);
      expect(provider.isSubmittingReview, isFalse);
      expect(provider.selectedProvider!.reviews.length, before + 1);
      // First, not last: the page shows the five newest (this read
      // `reviews.last.photoUrls`, which pinned the append that hid a sixth
      // review).
      expect(provider.selectedProvider!.reviews.first, same(mine));
      expect(provider.selectedProvider!.reviews.first.photoUrls, isNotEmpty);
    });

    /// The mock salon read answers from `MockData`, like the server from its
    /// tables: a review the mock did not STORE is erased by the next read.
    test('a reload keeps the review: first, and counted', () async {
      final provider = ProviderProvider();
      await provider.loadProviderById('provider1');
      final before = provider.selectedProvider!;

      final ok = await provider.submitReview(
        _review(
          providerId: 'provider1',
          appointmentId: 'reload',
          createdAt: DateTime(2026, 10, 12),
        ),
      );
      expect(ok, isTrue);
      await provider.loadProviderById('provider1');

      final after = provider.selectedProvider!;
      expect(after.reviews.first.appointmentId, 'reload');
      expect(after.reviews, hasLength(before.reviews.length + 1));
      expect(after.reviewCount, before.reviewCount + 1);
    });

    test('the re-read after « Publier » does not erase the review under the '
        'mocks', () async {
      final provider = ProviderProvider();
      await provider.loadProviderById('provider1');
      final before = provider.selectedProvider!;
      final reads = salons.byIdCalls;

      final ok = await provider.submitReview(
        _review(
          providerId: 'provider1',
          appointmentId: 'reread',
          createdAt: DateTime(2026, 10, 13),
        ),
      );
      expect(ok, isTrue);
      // One mock round trip, and room for it.
      await Future<void>.delayed(AppConstants.mockDelay * 2);

      expect(salons.byIdCalls, reads + 1, reason: 'the re-read answered');
      final after = provider.selectedProvider!;
      expect(after.reviews.first.appointmentId, 'reread');
      expect(
        after.reviews.where((r) => r.appointmentId == 'reread'),
        hasLength(1),
      );
      expect(after.reviews, hasLength(before.reviews.length + 1));
      expect(after.reviewCount, before.reviewCount + 1);
    });

    test('uploadReviewPhoto returns a hosted URL', () async {
      final provider = ProviderProvider();
      final url = await provider.uploadReviewPhoto('asset:x.png');
      expect(url, 'asset:x.png');
    });
  });
}
