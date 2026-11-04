import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/models/review_summary.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_reviews_provider.dart';
import 'package:myweli/screens/provider/reviews/reviews_screen.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

/// One review, and what « Signaler » sent.
class _Loaded extends ProReviewsProvider {
  _Loaded({this.answer = true});

  final bool answer;
  final reported = <(String, String?)>[];

  @override
  List<Review> get reviews => [
    Review(
      id: 'r1',
      providerId: SalonId('p1'),
      userId: 'u1',
      userName: 'Kouassi',
      rating: 1,
      text: 'Injurieux',
      createdAt: DateTime.utc(2026, 10, 1),
    ),
  ];
  @override
  ReviewSummary? get summary => null;
  @override
  bool get isLoading => false;
  @override
  Future<void> loadReviews(String providerId) async {}

  @override
  Future<bool> reportReview(String reviewId, {String? reason}) async {
    reported.add((reviewId, reason));
    return answer;
  }
}

/// A member without `profile.manage` (Réception, Collaborateur).
class _NoReport extends ProAuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  bool can(String capability) => false;
}

/// docs/design/backend-integrity-batch6.md §2.6 (B6.6, decision 20): the
/// salon reports a review of its own salon — App Store 1.2. The client's
/// dialog and words; the Propriétaire and the Gérant only.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    stubSecureStorage();
    setupDependencyInjection();
  });

  Future<_Loaded> pump(
    WidgetTester tester, {
    ProAuthProvider? auth,
    bool answer = true,
  }) async {
    final reviews = _Loaded(answer: answer);
    final who = auth ?? await signInPro(tester);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: who),
          ChangeNotifierProvider<ProReviewsProvider>.value(value: reviews),
        ],
        home: const ReviewsScreen(),
      ),
    );
    await settleMocks(tester, rounds: 3);
    return reviews;
  }

  Future<void> report(WidgetTester tester, {String? reason}) async {
    await tester.tap(find.widgetWithText(TextButton, 'Signaler'));
    await tester.pumpAndSettle();
    expect(find.text('Signaler cet avis ?'), findsOneWidget);
    if (reason != null) {
      await tester.enterText(find.byType(TextField).last, reason);
    }
    await tester.tap(find.widgetWithText(TextButton, 'Signaler').last);
    await tester.pumpAndSettle();
  }

  testWidgets('the owner reports a review: the reason crosses, « Merci. '
      'Notre équipe va examiner cet avis. »', (tester) async {
    final reviews = await pump(tester);
    await report(tester, reason: 'Insultes');

    expect(reviews.reported, [('r1', 'Insultes')]);
    expect(
      find.text('Merci. Notre équipe va examiner cet avis.'),
      findsOneWidget,
    );
  });

  testWidgets('a refusal → « Le signalement a échoué. Réessayez. »', (
    tester,
  ) async {
    await pump(tester, answer: false);
    await report(tester);
    expect(find.text('Le signalement a échoué. Réessayez.'), findsOneWidget);
  });

  testWidgets('a member without profile.manage sees no « Signaler »', (
    tester,
  ) async {
    await pump(tester, auth: _NoReport());
    expect(find.text('Injurieux'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Signaler'), findsNothing);
  });
}
