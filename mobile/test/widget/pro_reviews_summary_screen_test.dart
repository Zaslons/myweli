import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
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

/// docs/design/salon-reviews-summary.md — the card on « Avis » is the WHOLE
/// salon's: 60 reviews, of which the 50 loaded are all 5★, read « 4,2 » and
/// « 60 avis », never « 5,0 » and « 50 avis ».
class _Loaded extends ProReviewsProvider {
  _Loaded(this._items, this._fixed);

  final List<Review> _items;
  final ReviewSummary? _fixed;

  @override
  List<Review> get reviews => _items;
  @override
  ReviewSummary? get summary => _fixed;
  @override
  bool get isLoading => false;
  @override
  Future<void> loadReviews(String providerId) async {}
}

Review _five(int i) => Review(
  id: 'r$i',
  providerId: 'p1',
  userId: 'u$i',
  userName: 'Awa',
  rating: 5,
  text: '',
  createdAt: DateTime.utc(2026, 10, 1),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    stubSecureStorage();
    setupDependencyInjection();
  });

  Future<void> pump(WidgetTester tester, ReviewSummary? summary) async {
    final auth = await signInPro(tester);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider<ProReviewsProvider>(
            create: (_) =>
                _Loaded([for (var i = 0; i < 50; i++) _five(i)], summary),
          ),
        ],
        home: const ReviewsScreen(),
      ),
    );
    await settleMocks(tester, rounds: 3);
  }

  testWidgets('the server’s card: « 4,2 », « 60 avis »', (tester) async {
    await pump(
      tester,
      const ReviewSummary(
        average: 4.2,
        count: 60,
        distribution: {5: 50, 4: 0, 3: 0, 2: 0, 1: 10},
      ),
    );
    expect(find.text('60 avis'), findsOneWidget);
    expect(find.textContaining('4,2'), findsOneWidget);
    expect(find.textContaining('5,0'), findsNothing);
  });

  testWidgets('no summary (an older server): the loaded reviews', (
    tester,
  ) async {
    await pump(tester, null);
    expect(find.text('50 avis'), findsOneWidget);
    expect(find.textContaining('5,0'), findsOneWidget);
  });
}
