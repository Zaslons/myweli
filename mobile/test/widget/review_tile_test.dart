import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/widgets/review/review_tile.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Review review({bool verified = false, String? artistName}) => Review(
        id: 'r1',
        providerId: 'p1',
        userId: 'u1',
        userName: 'Marie Diallo',
        rating: 5,
        text: 'Super service',
        verified: verified,
        artistName: artistName,
        createdAt: DateTime(2025, 2, 4),
      );

  testWidgets('shows the verified badge and stylist when present',
      (tester) async {
    await tester.pumpWidget(
      wrap(ReviewTile(
        review: review(verified: true, artistName: 'Kouassi Jean'),
      )),
    );

    expect(find.text('Réservation vérifiée'), findsOneWidget);
    expect(find.text('avec Kouassi Jean'), findsOneWidget);
    expect(find.text('Marie Diallo'), findsOneWidget);
  });

  testWidgets('hides the verified badge when not verified', (tester) async {
    await tester.pumpWidget(wrap(ReviewTile(review: review())));

    expect(find.text('Réservation vérifiée'), findsNothing);
  });

  testWidgets('« Signaler » shows only with the callback and taps through',
      (tester) async {
    // Read-only (pro Avis screen): no action.
    await tester.pumpWidget(wrap(ReviewTile(review: review())));
    expect(find.text('Signaler'), findsNothing);

    var reported = false;
    await tester.pumpWidget(
      wrap(ReviewTile(review: review(), onReport: () => reported = true)),
    );
    await tester.tap(find.text('Signaler'));
    expect(reported, isTrue);
  });
}
