import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/common/timed_cached_image.dart';
import 'package:provider/provider.dart';

import '../a11y/_a11y.dart';
import '../support/fonts.dart';
import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';

/// The salon page's cover photo (docs/design/salon-cover-photo.md).
///
/// The owner saw no cover in the pro « Aperçu » where the website shows one:
/// the header's background was a plain white `Container` and never read
/// `imageUrls`. These pin the header that replaced it — both branches, the
/// geometry the website set (224dp, a 64dp ringed logo 16dp from the corner),
/// the way into the viewer, the toolbar and status bar over a photo, and the
/// heart that used to be white on white.
void main() {
  setUpAll(() async {
    // photo_lightbox_test.dart's bootstrap: clock before the locator, real
    // fonts for the pushed-route harness, stubbed storage for the session.
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
    stubSecureStorage();
    setupDependencyInjection();
  });

  tearDownAll(AppClock.restore);

  const logo = 'asset:assets/images/providers/salon_excellence.svg';
  final seed = MockData.providers.firstWhere((p) => p.id == 'provider1');

  /// A status bar 24dp tall, so « under the status bar » means something.
  const statusBar = 24.0;

  /// The owner preview: seeded, fetches nothing, renders the client page.
  Future<void> pumpPreview(
    WidgetTester tester,
    models.Provider salon, {
    Size size = const Size(390, 1600),
  }) async {
    pinSurface(tester, size: size);
    tester.view.padding = const FakeViewPadding(top: statusBar);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider.value(
            value: ProviderProvider()..showPreloaded(salon),
          ),
        ],
        home: const ProviderDetailScreen(
          providerId: SalonId('provider1'),
          preview: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder imageIn(Finder scope, String url) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate(
      (w) => w is TimedCachedImage && w.imageUrl == url,
    ),
  );

  Brightness? statusIcons() =>
      SystemChrome.latestStyle?.statusBarIconBrightness;

  testWidgets('the cover: imageUrls[0], full-bleed, labelled, opens photo 1', (
    tester,
  ) async {
    await pumpPreview(tester, seed.copyWith(logoUrl: logo));

    final cover = imageIn(find.byType(SliverAppBar), seed.imageUrls.first);
    expect(cover, findsOneWidget);
    // Edge to edge, from the top of the SCREEN: under the status bar and the
    // toolbar, 224dp below the status bar — the website's `h-56`.
    expect(
      tester.getRect(cover),
      const Rect.fromLTWH(0, 0, 390, statusBar + 224),
    );

    // The logo: 64dp, a 2dp white ring, 16dp from the cover's bottom-left —
    // `bottom-m left-m h-16 w-16 border-2` on the website. The image sits
    // inside the ring, so its rect proves the ring's width and the offset.
    final mark = tester.getRect(imageIn(find.byType(SliverAppBar), logo));
    expect(mark.left, AppTheme.spacingM + 2);
    expect(mark.bottom, statusBar + 224 - AppTheme.spacingM - 2);
    expect(mark.size, const Size(60, 60));
    final ring = tester.widget<Container>(
      find
          .ancestor(
            of: imageIn(find.byType(SliverAppBar), logo),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = ring.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.border, Border.all(color: AppColors.secondary, width: 2));

    // The name is below the photo, on the page's surface.
    expect(
      tester.getTopLeft(find.text('Salon Excellence').first).dy,
      greaterThan(statusBar + 224),
    );

    // Named for the screen reader, a button, and the way to photo 1.
    final label = find.bySemanticsLabel('Photo du salon Salon Excellence');
    expect(
      tester.getSemantics(label),
      isSemantics(
        label: 'Photo du salon Salon Excellence',
        hint: 'Agrandir la photo',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.bySemanticsLabel('Photo du salon 1 sur 2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no logo: no disc on the cover', (tester) async {
    await pumpPreview(tester, seed); // provider1 has no logoUrl
    expect(
      find.descendant(
        of: find.byType(SliverAppBar),
        matching: find.byType(TimedCachedImage),
      ),
      findsOneWidget,
      reason: 'the cover only — a generic disc on a photo identifies nothing',
    );
    expect(find.byIcon(Icons.store_outlined), findsNothing);
  });

  testWidgets('the cover as the only photo: no « Photos » section', (
    tester,
  ) async {
    await pumpPreview(tester, seed.copyWith(imageUrls: [seed.imageUrls.first]));
    expect(imageIn(find.byType(SliverAppBar), seed.imageUrls.first), findsOne);
    expect(find.text('Photos'), findsNothing);
    expect(find.text('Aucune photo pour le moment.'), findsNothing);
  });

  testWidgets('no photo at all: the header without a cover', (tester) async {
    await pumpPreview(tester, seed.copyWith(imageUrls: const []));
    expect(
      find.descendant(
        of: find.byType(SliverAppBar),
        matching: find.byType(TimedCachedImage),
      ),
      findsNothing,
    );
    expect(find.byIcon(Icons.store_outlined), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Aucune photo pour le moment.'), findsOneWidget);
    await tester.pump();
    expect(statusIcons(), Brightness.dark, reason: 'white header, dark icons');
  });

  testWidgets('status icons are light over the photo, dark once it fades', (
    tester,
  ) async {
    await pumpPreview(tester, seed, size: const Size(390, 844));
    await tester.pump();
    expect(statusIcons(), Brightness.light, reason: 'over the photo');

    // A little scroll: the photo is still fully there.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(statusIcons(), Brightness.light, reason: 'photo still showing');

    // Collapsed: the photo has faded into the bar.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(statusIcons(), Brightness.dark, reason: 'the bar, not the photo');
  });

  testWidgets('a scrim under the status bar and the toolbar', (tester) async {
    // Light icons on a white wall are invisible: §19's story scrim, black 60%
    // → transparent, over exactly the band the icons and the pills sit in.
    await pumpPreview(tester, seed);
    final scrim = find.descendant(
      of: find.byType(SliverAppBar),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).gradient is LinearGradient,
      ),
    );
    expect(scrim, findsOneWidget);
    final gradient =
        (tester.widget<DecoratedBox>(scrim).decoration as BoxDecoration)
                .gradient!
            as LinearGradient;
    expect(gradient.colors, [
      Colors.black.withValues(alpha: 0.6),
      Colors.transparent,
    ]);
    expect(gradient.begin, Alignment.topCenter);
    expect(
      tester.getRect(scrim),
      const Rect.fromLTWH(0, 0, 390, statusBar + kToolbarHeight),
    );
  });

  testWidgets('collapsed, a tap on the bar opens no photo nobody can see', (
    tester,
  ) async {
    await pumpPreview(tester, seed, size: const Size(390, 844));
    // The middle of the toolbar: the preview has no heart and no « Retour »,
    // so nothing but the cover is under this point.
    const onTheBar = Offset(195, statusBar + kToolbarHeight / 2);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tapAt(onTheBar);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing, reason: 'the cover has faded');

    // C: the same point IS the cover once it shows again.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester.tapAt(onTheBar);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget, reason: 'C: the cover opens');
  });

  testWidgets('a cover that fails to load keeps its band — no jump', (
    tester,
  ) async {
    // §2.4's decision: the page does not fall back to the no-photo header
    // after the fact; `TimedCachedImage` paints « image unavailable » in the
    // same 224dp, and everything around it stays where it was.
    const missing = 'asset:assets/images/providers/no_such_cover.png';
    await pumpPreview(
      tester,
      seed.copyWith(imageUrls: [missing, seed.imageUrls.last]),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    final bar = find.byType(SliverAppBar);
    expect(
      find.descendant(
        of: bar,
        matching: find.byIcon(Icons.image_not_supported),
      ),
      findsOneWidget,
      reason: 'the failure surface, inside the cover band',
    );
    expect(tester.getRect(imageIn(bar, missing)).height, statusBar + 224);
    expect(find.byIcon(Icons.store_outlined), findsNothing);
    expect(find.bySemanticsLabel('Photo du salon Salon Excellence'), findsOne);
  });

  // ---- the consumer app: the toolbar and the heart -------------------------

  Future<ProviderProvider> pumpConsumer(WidgetTester tester) async {
    final auth = await signInConsumer(tester);
    final salon = ProviderProvider();
    await pumpPushedAtWidth(
      tester,
      width: 390,
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: salon),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
      ],
      subject: const ProviderDetailScreen(providerId: SalonId('provider1')),
      rounds: 5,
    );
    return salon;
  }

  final pill = AppColors.secondary.withValues(alpha: 0.9);
  Color? fillOf(WidgetTester tester, Finder control) => tester
      .widget<Material>(
        find.descendant(of: control, matching: find.byType(Material)).first,
      )
      .color;
  Finder heart() => find.ancestor(
    of: find.byIcon(Icons.favorite_border),
    matching: find.byType(IconButton),
  );

  testWidgets('on the photo, « Retour » and the heart sit on white pills', (
    tester,
  ) async {
    await pumpConsumer(tester);
    expect(find.byTooltip('Ajouter aux favoris'), findsOneWidget);
    for (final (name, control) in [
      ('Retour', find.byType(BackButton)),
      ('the heart', heart()),
    ]) {
      expect(
        fillOf(tester, control),
        pill,
        reason: '$name must read on any photo — provider_card.dart\'s pill',
      );
      final size = tester.getSize(control);
      expect(size.width, greaterThanOrEqualTo(48), reason: '$name, §13.2');
      expect(size.height, greaterThanOrEqualTo(48), reason: '$name, §13.2');
    }
  });

  testWidgets('the heart is visible on both headers', (tester) async {
    final salon = await pumpConsumer(tester);
    Color? heartColor() =>
        tester.widget<Icon>(find.byIcon(Icons.favorite_border)).color;
    expect(heartColor(), AppColors.textPrimary, reason: 'on its pill');

    salon.showPreloaded(seed.copyWith(imageUrls: const []));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SliverAppBar),
        matching: find.byIcon(Icons.store_outlined),
      ),
      findsOneWidget,
      reason:
          'C: this is the header without a photo (the appointment tiles '
          'below draw the same glyph, hence the scope)',
    );
    expect(
      heartColor(),
      AppColors.textPrimary,
      reason:
          'it was `secondary` — #FFFFFF on the white header, invisible until '
          'it turned red',
    );
    expect(
      fillOf(tester, heart()),
      isNot(pill),
      reason: 'no photo, no pill: the header is the one it always was',
    );
  });
}
