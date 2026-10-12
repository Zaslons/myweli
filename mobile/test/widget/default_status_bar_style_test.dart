import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/widgets/common/default_status_bar_style.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';
import '../support/surface.dart';

/// The status bar after BACK from the salon cover (salon-cover-photo.md
/// §2.1; `DefaultStatusBarStyle`).
///
/// The cover sends LIGHT icons. The consumer home has no `AppBar` and so no
/// `AnnotatedRegion` of its own, and Flutter sends nothing when no region sits
/// under the status bar — so after home → salon → back the white icons stayed
/// on the near-white home. The app roots now install a dark default under
/// every route; these hold the leak, the fix, and the installation.
///
/// `SystemChrome.latestStyle` is what the framework actually SENT, not what a
/// widget declares — the same reading `salon_cover_test.dart` takes. The app
/// starts dark either way (`MaterialApp` sends dark once, for its light theme,
/// and never again on a route change), so only the style AFTER back tells the
/// two apart.
void main() {
  setUpAll(() {
    // `ProviderProvider` takes its service at construction. The preview never
    // calls it (salon_preview_test.dart holds that); this only lets it exist.
    serviceLocator.providerService = MockProviderService();
  });

  // provider1 has photos, so its page is the COVER header — light icons.
  final salon = MockData.providers.firstWhere((p) => p.id == 'provider1');

  Brightness? statusIcons() =>
      SystemChrome.latestStyle?.statusBarIconBrightness;

  /// The consumer home's shape — a `Scaffold` with NO `AppBar` — with or
  /// without the app roots' builder above it.
  Future<void> pumpHome(
    WidgetTester tester, {
    required bool rootDefault,
  }) async {
    pinSurface(tester, size: const Size(390, 844));
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider.value(
            value: ProviderProvider()..showPreloaded(salon),
          ),
        ],
        builder: rootDefault
            ? (context, child) =>
                  DefaultStatusBarStyle(child: child ?? const SizedBox.shrink())
            : null,
        home: const Scaffold(
          backgroundColor: AppColors.background,
          body: SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// home → the salon page (the owner preview: seeded, fetches nothing — the
  /// same `ProviderDetailScreen` the client opens) → back.
  Future<void> openSalon(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(Scaffold))).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const ProviderDetailScreen(providerId: 'provider1', preview: true),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(ProviderDetailScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ProviderDetailScreen), findsNothing);
  }

  testWidgets('C: without a root default, the cover\'s light icons outlive '
      'the cover', (tester) async {
    // The defect, reproduced — so the test below cannot pass for want of a
    // harness that shows it.
    await pumpHome(tester, rootDefault: false);
    await openSalon(tester);
    expect(statusIcons(), Brightness.light, reason: 'over the cover');
    await back(tester);
    expect(
      statusIcons(),
      Brightness.light,
      reason:
          'C: no region under the status bar on a screen without an AppBar, '
          'so nothing is sent and the light icons stay',
    );
  });

  testWidgets('with the root default: dark on the home, light over the cover, '
      'dark again after back', (tester) async {
    await pumpHome(tester, rootDefault: true);
    // Not the guard: `MaterialApp` itself sends dark once, when it builds its
    // light theme (material/app.dart, `_themeBuilder`) — which is why the
    // leak only shows AFTER a light screen. The guard is the last assertion.
    expect(statusIcons(), Brightness.dark, reason: 'a home without an AppBar');

    await openSalon(tester);
    expect(
      statusIcons(),
      Brightness.light,
      reason: 'the deepest region wins: the cover keeps its light icons',
    );

    await back(tester);
    expect(
      statusIcons(),
      Brightness.dark,
      reason:
          'back on the near-white home, the icons must be dark again — not '
          'the cover\'s white ones',
    );
  });

  // Discovered, not listed — the shape `content_width_test.dart` uses for
  // `ContentWidthCap`: a fourth phone root is covered the day it lands.
  test('both phone app roots install the default; admin is not a phone', () {
    final roots = Directory('lib')
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'(^|/)main(_\w+)?\.dart$').hasMatch(f.path))
        .where((f) => !f.path.endsWith('main_admin.dart'))
        .toList();
    expect(
      roots.map((f) => f.path.split('/').last),
      containsAll(['main.dart', 'main_pro.dart']),
      reason:
          'the consumer and pro roots must be found, or the check below is '
          'empty-set-true',
    );

    // Whole-line comments removed: a paragraph naming the widget must not
    // satisfy the pin that asks for the widget.
    String codeOf(File f) => f
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    final missing = roots
        .where((f) => !codeOf(f).contains('DefaultStatusBarStyle('))
        .map((f) => f.path)
        .toList();
    expect(
      missing,
      isEmpty,
      reason:
          'a root without it leaves every screen without an AppBar to '
          'whatever style was sent last — the consumer home after the salon '
          'cover or a story; in the pro app, any such screen « Aperçu » is '
          'opened from',
    );
  });
}
