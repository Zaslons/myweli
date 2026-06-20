import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/app_button.dart';
import 'package:myweli/widgets/common/empty_state.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders the title, description and icon', (tester) async {
    await tester.pumpWidget(wrap(const EmptyState(
      icon: Icons.notifications_none,
      title: 'Aucune notification',
      description: 'Rien pour le moment.',
    )));

    expect(find.text('Aucune notification'), findsOneWidget);
    expect(find.text('Rien pour le moment.'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });

  testWidgets('hides the action button when no action is provided',
      (tester) async {
    await tester.pumpWidget(wrap(const EmptyState(
      icon: Icons.inbox,
      title: 'Vide',
    )));

    expect(find.byType(AppButton), findsNothing);
  });

  testWidgets('shows and fires the action button when provided',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(EmptyState(
      icon: Icons.inbox,
      title: 'Vide',
      actionText: 'Rafraîchir',
      onAction: () => tapped = true,
    )));

    expect(find.text('Rafraîchir'), findsOneWidget);
    await tester.tap(find.byType(AppButton));
    expect(tapped, isTrue);
  });
}
