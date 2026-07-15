import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:provider/provider.dart';

import 'pump_app.dart';

/// `wrapApp` is what makes the 34 widget tests render the REAL design system
/// (SYSTEM.md §21 row 21). This asserts that it actually injects
/// `AppTheme.lightTheme` — the tests own "the harness wraps the real theme"; the
/// goldens own "the theme renders correctly". Widget tests assert on finders, not
/// colours, so without this the migration's whole point would be unverifiable.
void main() {
  testWidgets('wrapApp renders under the real AppTheme', (tester) async {
    late ThemeData theme;
    await pumpApp(
      tester,
      home: Builder(
        builder: (context) {
          theme = Theme.of(context);
          return const SizedBox.shrink();
        },
      ),
    );

    // The brand black, the ink, and the completed scheme (A3) — not Material's
    // purple defaults.
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.onSurfaceVariant, AppColors.textSecondary);
    // The control-boundary token A1 put on inputs.
    final border =
        theme.inputDecorationTheme.enabledBorder as OutlineInputBorder;
    expect(border.borderSide.color, AppColors.borderStrong);
  });

  testWidgets('providers are wired and the router branch renders',
      (tester) async {
    await pumpApp(
      tester,
      providers: [ChangeNotifierProvider(create: (_) => _Counter())],
      home: Builder(
        builder: (context) => Text('${context.watch<_Counter>().value}'),
      ),
    );
    expect(find.text('0'), findsOneWidget);
  });
}

class _Counter extends ChangeNotifier {
  int value = 0;
}
