import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:myweli/widgets/common/timed_cached_image.dart';
import 'package:provider/provider.dart';

import '../a11y/_a11y.dart';
import '../support/fonts.dart';
import '../support/frozen_clock.dart';
import '../support/secure_storage.dart';
import '../support/sign_in.dart';

/// The salon photo lightbox — the first test this dialog has ever had.
///
/// ## Why this file exists
///
/// The owner opened a salon photo full screen during the demo-salon curation
/// and saw a zoomed slice instead of the photo: the dialog rendered with
/// `BoxFit.cover` at viewport size, which CROPS every image whose aspect
/// differs from the screen's. It was the sole `cover` among the app's six
/// lightboxes — the other five (deposit proof ×2, admin ×2, review photos)
/// already used `contain`, as does the web's Lightbox — and no test or golden
/// photographed the open dialog, which is why it survived.
///
/// Three assertions, three regressions this pins:
/// - `contain` (the crop coming back),
/// - the semantic label (the photo used to be excluded from semantics),
/// - the light status-bar region (the dialog is one of three full-bleed dark
///   surfaces; with the bar unhidden on 2026-08-27, dark icons over an
///   arbitrary photo would be the new invisibility).
void main() {
  setUpAll(() async {
    // The a11y harness's bootstrap, verbatim (layout_test.dart): clock frozen
    // BEFORE the locator (mocks seed clock-relative data at construction),
    // real fonts so text measures as text, stubbed storage so the session
    // read cannot throw on screen.
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
    stubSecureStorage();
    setupDependencyInjection();
  });

  testWidgets(
    'the salon photo lightbox: contain, labelled, light status icons',
    (tester) async {
      final auth = await signInConsumer(tester);
      await pumpPushedAtWidth(
        tester,
        width: 390,
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProviderProvider()),
          ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ],
        subject: const ProviderDetailScreen(providerId: 'provider1'),
        rounds: 5,
      );

      // Reach the Photos strip and open the first photo.
      await tester.scrollUntilVisible(
        find.text('Photos'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final thumb = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(GestureDetector),
          )
          .first;
      await tester.tap(thumb);
      await tester.pumpAndSettle();

      final dialog = find.byType(Dialog);
      expect(dialog, findsOneWidget, reason: 'the lightbox opened');

      // 1. Every photo in the dialog letterboxes — never crops.
      final images = tester.widgetList<TimedCachedImage>(
        find.descendant(of: dialog, matching: find.byType(TimedCachedImage)),
      );
      expect(images, isNotEmpty, reason: 'the dialog renders the photo');
      for (final img in images) {
        expect(
          img.fit,
          BoxFit.contain,
          reason:
              'cover at viewport size crops every non-viewport-aspect photo '
              '— the owner saw a zoomed slice, not the picture',
        );
      }

      // 2. The photo the user deliberately opened is not a semantic void.
      expect(
        find.descendant(
          of: dialog,
          matching: find.bySemanticsLabel(RegExp('Photo du salon 1 sur')),
        ),
        findsOneWidget,
      );

      // 3. Light status-bar icons over the scrim.
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .ancestor(
              of: dialog,
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .first,
      );
      expect(region.value, SystemUiOverlayStyle.light);
    },
  );
}
