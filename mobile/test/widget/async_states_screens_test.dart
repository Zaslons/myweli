import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/artist.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/models/service.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_reviews_provider.dart';
import 'package:myweli/providers/pro_service_provider.dart';
import 'package:myweli/screens/provider/artists/artist_list_screen.dart';
import 'package:myweli/screens/provider/reviews/reviews_screen.dart';
import 'package:myweli/screens/provider/services/service_list_screen.dart';
import 'package:myweli/widgets/common/app_async_view.dart';
import 'package:myweli/widgets/common/salon_unavailable_view.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

/// A list that did not load — what each Pro list said before B9.8 was its
/// EMPTY state: « Aucun avis », « Aucun service pour le moment », « Aucun
/// employé ». docs/design/hygiene-batch9.md §14.
class _FailedReviews extends ProReviewsProvider {
  @override
  List<Review> get reviews => const [];
  @override
  bool get isLoading => false;
  @override
  String? get loadError => kNoConnectionMessage;
  @override
  Future<void> loadReviews(String providerId) async {}
}

class _FailedServices extends ProServiceProvider {
  @override
  List<Service> get services => const [];
  @override
  bool get isLoading => false;
  @override
  String? get loadError => kNoConnectionMessage;
  @override
  Future<void> loadServices(String providerId) async {}
}

class _FailedArtists extends ProArtistProvider {
  @override
  List<Artist> get artists => const [];
  @override
  bool get isLoading => false;
  @override
  String? get loadError => kNoConnectionMessage;
  @override
  Future<void> loadArtists(String providerId) async {}
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    stubSecureStorage();
    setupDependencyInjection();
  });

  group('a Pro list that did not load says so, not « empty »', () {
    Future<void> pump(
      WidgetTester tester,
      Widget screen,
      SingleChildWidgetLike provider,
    ) async {
      final auth = await signInPro(tester);
      await tester.pumpWidget(
        wrapApp(
          providers: [
            ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
            provider(),
          ],
          home: screen,
        ),
      );
      await settleMocks(tester, rounds: 3);
    }

    void expectTheSharedError() {
      expect(find.byType(AppErrorView), findsOneWidget);
      expect(find.text('Chargement impossible'), findsOneWidget);
      expect(find.text(kNoConnectionMessage), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    }

    testWidgets('« Avis »', (tester) async {
      await pump(
        tester,
        const ReviewsScreen(),
        () => ChangeNotifierProvider<ProReviewsProvider>(
          create: (_) => _FailedReviews(),
        ),
      );
      expectTheSharedError();
      expect(find.text('Aucun avis'), findsNothing);
    });

    testWidgets('« Services »', (tester) async {
      await pump(
        tester,
        const ServiceListScreen(),
        () => ChangeNotifierProvider<ProServiceProvider>(
          create: (_) => _FailedServices(),
        ),
      );
      expectTheSharedError();
      expect(find.text('Aucun service pour le moment'), findsNothing);
    });

    testWidgets('« Employés »', (tester) async {
      await pump(
        tester,
        const ArtistListScreen(),
        () => ChangeNotifierProvider<ProArtistProvider>(
          create: (_) => _FailedArtists(),
        ),
      );
      expectTheSharedError();
      expect(find.text('Aucun employé'), findsNothing);
    });
  });

  group('a salon that could not be read (SalonUnavailableView)', () {
    Future<void> pump(WidgetTester tester, String? code, String? message) =>
        pumpApp(
          tester,
          home: Scaffold(
            body: SalonUnavailableView(
              errorCode: code,
              message: message,
              onRetry: () {},
            ),
          ),
        );

    testWidgets('nothing answered: the shared error, wifi-off', (tester) async {
      await pump(tester, 'network', kNoConnectionMessage);
      expect(find.byType(AppErrorView), findsOneWidget);
      expect(find.text(kNoConnectionMessage), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('the server failed: no blame on the connection', (
      tester,
    ) async {
      // « Impossible de charger ce salon. Vérifiez votre connexion. » was
      // the sentence for a 500 too.
      await pump(tester, 'server_error', kGenericErrorMessage);
      expect(find.text(kGenericErrorMessage), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsNothing);
    });

    testWidgets('the salon is gone: its state and a way elsewhere, no retry', (
      tester,
    ) async {
      await pump(tester, 'not_found', null);
      expect(find.byType(AppErrorView), findsNothing);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
      expect(find.text('Découvrir des salons'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    });
  });
}

typedef SingleChildWidgetLike =
    ChangeNotifierProvider<ChangeNotifier> Function();
