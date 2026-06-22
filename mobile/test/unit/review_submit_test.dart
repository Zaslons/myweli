import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/services/mock/mock_review_service.dart';

Review _review({required String providerId, int rating = 5}) => Review(
      id: 'r_${DateTime.now().microsecondsSinceEpoch}',
      providerId: providerId,
      userId: 'u1',
      userName: 'Ama',
      rating: rating,
      text: 'Très satisfaite',
      verified: true,
      photoUrls: const ['asset:assets/images/providers/spa_relax_photo.png'],
      createdAt: DateTime(2026),
    );

void main() {
  group('MockReviewService', () {
    test('persists a valid review and rejects an invalid rating', () async {
      final service = MockReviewService();

      final ok = await service.submitReview(_review(providerId: 'provider1'));
      expect(ok.success, isTrue);
      expect(ok.data!.rating, 5);

      final bad = await service
          .submitReview(_review(providerId: 'provider1', rating: 0));
      expect(bad.success, isFalse);
    });
  });

  group('ProviderProvider review flow', () {
    setUpAll(() {
      serviceLocator.providerService = MockProviderService();
      serviceLocator.reviewService = MockReviewService();
      serviceLocator.imageUploadService = MockImageUploadService();
    });

    test('submitReview adds the review to the selected provider', () async {
      final provider = ProviderProvider();
      await provider.loadProviderById('provider1');
      expect(provider.selectedProvider, isNotNull);
      final before = provider.selectedProvider!.reviews.length;

      final ok = await provider.submitReview(_review(providerId: 'provider1'));

      expect(ok, isTrue);
      expect(provider.isSubmittingReview, isFalse);
      expect(provider.selectedProvider!.reviews.length, before + 1);
      expect(provider.selectedProvider!.reviews.last.photoUrls, isNotEmpty);
    });

    test('uploadReviewPhoto returns a hosted URL', () async {
      final provider = ProviderProvider();
      final url = await provider.uploadReviewPhoto('asset:x.png');
      expect(url, 'asset:x.png');
    });
  });
}
