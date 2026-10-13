import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_favorites_service.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/services/mock/mock_review_service.dart';
import 'package:myweli/widgets/review/submit_review_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/sign_in.dart';

/// « Donner mon avis » → « Publier », and what the FAVOURITES show afterwards
/// (docs/design/amounts-that-fit.md §2 « Reviews »).
///
/// The favourites are a fourth copy of a salon, in another notifier, loaded
/// once per session: the home « Mes favoris » cards kept « Nouveau » — or the
/// old count — until the app was restarted. The sheet is the one place that
/// has both notifiers in hand, so it is the sheet these tests drive.
void main() {
  final salons = _Salons();
  final favoritesService = _Favorites();

  final salon = MockData.providers
      .firstWhere((p) => p.id == 'provider1')
      .copyWith(rating: 4.5, reviewCount: 2, reviews: const []);
  // What the server holds after the review: the true average, which the
  // app’s estimate — (4,5 × 2 + 5) / 3, « 4,7 » — cannot know.
  final stored = salon.copyWith(rating: 4.6, reviewCount: 3);

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    serviceLocator.authService = MockAuthService();
    serviceLocator.providerService = salons;
    serviceLocator.reviewService = _Reviews();
    serviceLocator.favoritesService = favoritesService;
    serviceLocator.reviewImageUploadService = MockImageUploadService();
  });

  setUp(() {
    salons
      ..list = const []
      ..asked = null;
    favoritesService.salons = [salon];
  });

  /// A screen with the entry point, as the salon page and the appointment
  /// screen have it. [favorites] null: a tree that registers none.
  Future<void> pumpEntry(
    WidgetTester tester, {
    required AuthProvider auth,
    required ProviderProvider providers,
    FavoritesProvider? favorites,
  }) async {
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: providers),
          if (favorites != null) ChangeNotifierProvider.value(value: favorites),
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const SubmitReviewSheet(
                    providerId: 'provider1',
                    appointmentId: 'apt-1',
                  ),
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> publish(WidgetTester tester, {required int stars}) async {
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Noter $stars étoiles'));
    await tester.pump();
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();
  }

  (double, int) figures(models.Provider p) => (p.rating, p.reviewCount);

  testWidgets('the favourites carry the salon’s new figures at once, then the '
      'server’s', (tester) async {
    final auth = await signInConsumer(tester);
    final providers = ProviderProvider()..showPreloaded(salon);
    final favorites = FavoritesProvider();
    await favorites.loadFavorites(auth.user!.id);
    expect(figures(favorites.favoriteProviders.single), (4.5, 2));
    await pumpEntry(
      tester,
      auth: auth,
      providers: providers,
      favorites: favorites,
    );

    await publish(tester, stars: 5);

    // The re-read is still out: the sheet did not wait for it.
    expect(find.text('Merci pour votre avis'), findsOneWidget);
    expect(find.text('Publier'), findsNothing);
    expect(figures(providers.selectedProvider!), (4.7, 3));
    expect(figures(favorites.favoriteProviders.single), (4.7, 3));

    salons.asked!.complete(ApiResponse.success(stored));
    await tester.pump();

    expect(figures(providers.selectedProvider!), (4.6, 3));
    expect(figures(favorites.favoriteProviders.single), (4.6, 3));
  });

  testWidgets('from the appointment screen — no salon page — the favourites '
      'move with the list', (tester) async {
    salons.list = [salon];
    final auth = await signInConsumer(tester);
    final providers = ProviderProvider();
    await providers.loadProviders();
    final favorites = FavoritesProvider();
    await favorites.loadFavorites(auth.user!.id);
    await pumpEntry(
      tester,
      auth: auth,
      providers: providers,
      favorites: favorites,
    );

    await publish(tester, stars: 5);

    expect(figures(providers.providers.single), (4.7, 3));
    expect(figures(favorites.favoriteProviders.single), (4.7, 3));

    salons.asked!.complete(ApiResponse.success(stored));
    await tester.pump();

    expect(figures(providers.providers.single), (4.6, 3));
    expect(figures(favorites.favoriteProviders.single), (4.6, 3));
    expect(providers.selectedProvider, isNull);
  });

  testWidgets('a tree with no favourites above the sheet still publishes', (
    tester,
  ) async {
    final auth = await signInConsumer(tester);
    final providers = ProviderProvider()..showPreloaded(salon);
    await pumpEntry(tester, auth: auth, providers: providers);

    await publish(tester, stars: 4);

    expect(tester.takeException(), isNull);
    expect(find.text('Merci pour votre avis'), findsOneWidget);
    expect(providers.selectedProvider!.reviewCount, 3);
    expect(salons.asked, isNotNull, reason: 'the re-read was sent');

    salons.asked!.complete(ApiResponse.success(stored));
    await tester.pump();
    expect(figures(providers.selectedProvider!), (4.6, 3));
  });
}

/// The public salon reads: the list as given, and the salon held until the
/// test answers [asked].
class _Salons extends MockProviderService {
  List<models.Provider> list = const [];

  /// The re-read that is out — null while none was sent. Made at the call,
  /// so INSIDE the test's fake-async zone: a completer made in `setUp`
  /// completes on the real event loop, after the test body has moved on.
  Completer<ApiResponse<models.Provider>>? asked;

  @override
  Future<ApiResponse<models.Provider>> getProviderById(String id) =>
      (asked = Completer()).future;

  @override
  Future<ApiResponse<List<models.Provider>>> getProviders({
    String? category,
    String? searchQuery,
    String? commune,
    ProviderSort sort = ProviderSort.relevance,
    bool availableToday = false,
    int page = 1,
    int limit = 20,
  }) async => ApiResponse.success(List.of(list));
}

/// The 201 of `POST /appointments/{id}/review`, with no latency to pump.
class _Reviews extends MockReviewService {
  @override
  Future<ApiResponse<Review>> submitReview(Review review) async =>
      ApiResponse.success(review);
}

/// `GET /me/favorites`, hydrated.
class _Favorites extends MockFavoritesService {
  List<models.Provider> salons = const [];

  @override
  Future<ApiResponse<List<models.Provider>>> getFavoriteProviders(
    String userId,
  ) async => ApiResponse.success(List.of(salons));
}
