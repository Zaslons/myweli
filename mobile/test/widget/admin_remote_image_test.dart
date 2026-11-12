import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/screens/admin/widgets/admin_detail_widgets.dart';
import 'package:myweli/screens/admin/widgets/admin_remote_image.dart';
import 'package:myweli/widgets/common/brand_loader.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';

/// docs/design/admin-remote-images.md — the console draws an image from R2 as
/// a plain `<img>`, which needs no CORS header, because R2 sends none to
/// `admin.myweli.com` (probed 2026-11-12, spec §1).
///
/// A widget test runs on the VM, where the strategy is ignored: what it can
/// hold is that the strategy is ASKED FOR, with no header (a header makes the
/// framework fetch the bytes instead, CORS again). That the browser then draws
/// the `<img>` was observed in a release CanvasKit build (spec §8.2), not here.
void main() {
  setUpAll(loadRealFonts);

  const url =
      'https://acc.r2.cloudflarestorage.com/deposit/u2/proof.jpg?X-Amz-Signature=s';

  Future<void> pump(
    WidgetTester t,
    Widget child, {
    double textScale = 1,
  }) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    t.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(
      wrapApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  NetworkImage providerOf(WidgetTester t, Finder image) =>
      t.widget<Image>(image).image as NetworkImage;

  testWidgets('asks the browser for an <img>: prefer, and no header', (
    t,
  ) async {
    await pump(t, const AdminRemoteImage(url: url));

    final provider = providerOf(t, find.byType(Image));
    expect(provider.url, url);
    expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.prefer);
    expect(provider.headers ?? const {}, isEmpty);
  });

  testWidgets('the loader shows until the first frame', (t) async {
    await pump(
      t,
      const SizedBox(
        width: 220,
        height: 160,
        child: AdminRemoteImage(url: url),
      ),
    );
    expect(find.byType(BrandLoader), findsOneWidget);
    expect(find.text(AdminRemoteImage.unavailableLabel), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('a refused link says « Image indisponible » in a 220 × 160 '
        'tile at $scale×, whole', (t) async {
      await pump(
        t,
        const SizedBox(
          width: 220,
          height: 160,
          child: AdminRemoteImage(url: url),
        ),
        textScale: scale,
      );
      // flutter_test answers every HTTP request 400: the refused link.
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pumpAndSettle();

      expect(find.text(AdminRemoteImage.unavailableLabel), findsOneWidget);
      expect(find.byType(BrandLoader), findsNothing);
      // Nothing to reload: no button that cannot help.
      expect(find.text(AdminRemoteImage.reloadLabel), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('with a way to reload, the failure offers « Actualiser » in a '
        '220 × 160 tile at $scale×, reachable, and a tap reloads', (t) async {
      var reloads = 0;
      await pump(
        t,
        SizedBox(
          width: 220,
          height: 160,
          child: AdminRemoteImage(url: url, onReload: () => reloads++),
        ),
        textScale: scale,
      );
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pumpAndSettle();

      expect(find.text(AdminRemoteImage.unavailableLabel), findsOneWidget);
      expect(t.takeException(), isNull);
      // At 2× the message and the button outgrow the tile: they scroll, and
      // the button is still there to reach.
      await t.ensureVisible(find.text(AdminRemoteImage.reloadLabel));
      await t.pumpAndSettle();
      await t.tap(find.text(AdminRemoteImage.reloadLabel));
      expect(reloads, 1);
      if (scale == 1) {
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      }
    });
  }

  testWidgets('a tile with its own placeholders (B0.18\'s salon photos) shows '
      'them — until the first frame, and on the failure, which then carries '
      'no « Image indisponible » and no « Actualiser »', (t) async {
    const loading = Icon(Icons.image_outlined);
    const failed = Icon(Icons.broken_image_outlined);
    Widget tile() => const SizedBox(
      width: 144,
      height: 144,
      child: AdminRemoteImage(
        url: url,
        placeholder: loading,
        errorPlaceholder: failed,
      ),
    );
    await pump(t, tile());
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byType(BrandLoader), findsNothing);
    // Still the <img>, with no header.
    final provider = providerOf(t, find.byType(Image));
    expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.prefer);
    expect(provider.headers ?? const {}, isEmpty);

    // flutter_test answers every HTTP request 400.
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(find.text(AdminRemoteImage.unavailableLabel), findsNothing);
    expect(find.text(AdminRemoteImage.reloadLabel), findsNothing);
  });

  test('a failure of its own never comes with a reload: the button would be '
      'replaced with it', () {
    expect(
      () => AdminRemoteImage(
        url: url,
        errorPlaceholder: const SizedBox(),
        onReload: () {},
      ),
      throwsAssertionError,
    );
  });

  testWidgets('the deposit proof (AdminEvidenceImage) draws through it, and '
      'its zoom too', (t) async {
    await pump(t, const AdminEvidenceImage(url: url, caption: 'Preuve'));

    expect(find.byType(AdminRemoteImage), findsOneWidget);
    expect(
      providerOf(t, find.byType(Image)).webHtmlElementStrategy,
      WebHtmlElementStrategy.prefer,
    );

    await t.tap(find.byType(AdminRemoteImage));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    final zoomed = find.descendant(
      of: find.byType(InteractiveViewer),
      matching: find.byType(AdminRemoteImage),
    );
    expect(zoomed, findsOneWidget);
    expect(t.widget<AdminRemoteImage>(zoomed).fit, BoxFit.contain);
    expect(
      providerOf(
        t,
        find.descendant(of: zoomed, matching: find.byType(Image)),
      ).webHtmlElementStrategy,
      WebHtmlElementStrategy.prefer,
    );
  });

  testWidgets('a failure in the zoom closes it, then reloads: the page under '
      'it must not keep the dead link', (t) async {
    var reloads = 0;
    await pump(
      t,
      AdminEvidenceImage(
        url: url,
        caption: 'Preuve',
        onReload: () => reloads++,
      ),
    );
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pumpAndSettle();

    // The failed tile's centre is its « Actualiser » (a tap there reloads);
    // the rest of the tile still opens the zoom.
    await t.tapAt(
      t.getTopLeft(find.byType(AdminRemoteImage)) + const Offset(12, 12),
    );
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(reloads, 0);

    await t.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text(AdminRemoteImage.reloadLabel),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(reloads, 1);
  });

  testWidgets('no link: the placeholder, no image at all', (t) async {
    await pump(t, const AdminEvidenceImage(url: null));
    expect(find.byType(AdminRemoteImage), findsNothing);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
  });
}
