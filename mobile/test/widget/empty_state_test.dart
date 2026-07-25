import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/widgets/common/app_button.dart';
import 'package:myweli/widgets/common/empty_state.dart';

import '../support/pump_app.dart';

void main() {
  Widget wrap(Widget child) => wrapApp(home: Scaffold(body: child));

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

  testWidgets('the body reads at 16 — bodyLarge, not the workhorse (§21 row 27)',
      (tester) async {
    // §4 declares bodyLarge "Default reading text"; the empty-state body is
    // reading copy. This pin goes red if it slips back to bodyMedium (14).
    await tester.pumpWidget(wrap(const EmptyState(
      icon: Icons.inbox,
      title: 'Vide',
      description: 'Rien pour le moment.',
    )));

    final body = tester.widget<Text>(find.text('Rien pour le moment.'));
    expect(body.style!.fontSize, AppTextStyles.bodyLarge.fontSize);
    expect(body.style!.fontSize, 16);
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
