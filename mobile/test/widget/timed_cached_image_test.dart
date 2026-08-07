import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/timed_cached_image.dart';

/// `TimedCachedImage` has two branches and, until now, two different ideas of
/// what failure looks like.
///
/// The network branch has always degraded to a placeholder. The **asset**
/// branch had no `errorBuilder`, so a missing asset threw and Flutter's
/// `ErrorWidget` rendered in its place — a red box in debug, grey in release,
/// sitting on the salon card.
///
/// That shipped. The backend's seeded salons pointed at
/// `asset:assets/images/barber1.jpg` and three siblings that have never existed
/// in this repository, so the consumer home screen rendered four error boxes
/// against a real server. The seed is fixed and gated on the backend side
/// (`backend/test/seed_assets_test.dart`), but the seed is not the only way a
/// path can go stale — an asset can be renamed or dropped from `pubspec.yaml`
/// at any time. This asserts the *widget* never lets that reach the user.
void main() {
  Widget host(String url) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: TimedCachedImage(imageUrl: url, width: 100, height: 100),
      ),
    ),
  );

  testWidgets('a missing asset renders the placeholder, never an error box', (
    tester,
  ) async {
    await tester.pumpWidget(host('asset:assets/images/does_not_exist.png'));
    await tester.pump();

    expect(
      find.byIcon(Icons.image_not_supported),
      findsOneWidget,
      reason: 'the same surface the network branch has always shown',
    );

    // The actual regression guard. `ErrorWidget` is what Flutter substitutes
    // when a build throws; if it is present, the user is looking at a red box.
    expect(
      find.byType(ErrorWidget),
      findsNothing,
      reason: 'a missing asset must degrade, not throw into the widget tree',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an asset that IS bundled still renders as an image', (
    tester,
  ) async {
    // Guards the obvious way to "fix" the above — swallowing every asset into
    // the placeholder. This path must still paint the real thing.
    await tester.pumpWidget(
      host('asset:assets/images/providers/barber_shop_pro_photo.png'),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.image_not_supported), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
