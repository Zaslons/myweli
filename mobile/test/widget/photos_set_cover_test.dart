import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_gallery_provider.dart';
import 'package:myweli/screens/provider/photos/pro_photos_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

class _MockProService extends Mock implements ProServiceInterface {}

/// « Définir comme photo principale » on the tile (gallery-set-cover.md §2)
/// — the affordance half; the provider half lives beside
/// `gallery_reorder_test.dart`.
void main() {
  late _MockProService service;

  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    service = _MockProService();
    serviceLocator.proService = service;
    serviceLocator.imageUploadService = MockImageUploadService();
  });

  setUp(() => reset(service));

  Future<void> pumpWith(WidgetTester tester, List<String> photos) async {
    final auth = await signInPro(tester);
    when(
      () => service.getGalleryPhotos(any()),
    ).thenAnswer((_) async => ApiResponse.success(photos));
    when(() => service.updateGalleryPhotos(any(), any())).thenAnswer(
      (i) async =>
          ApiResponse.success(i.positionalArguments[1] as List<String>),
    );

    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProGalleryProvider()),
        ],
        home: const ProPhotosScreen(),
      ),
    );
    await settleMocks(tester, rounds: 3);
  }

  // A function, not a top-level final: bySemanticsLabel touches the
  // SemanticsBinding, which does not exist until the first testWidgets runs.
  Finder star() => find.bySemanticsLabel('Définir comme photo principale');

  testWidgets('the star renders on every tile EXCEPT the cover', (
    tester,
  ) async {
    await pumpWith(tester, ['a', 'b', 'c']);
    // Two of three: the cover already IS the cover — a star there would be
    // a dead control wearing a promise.
    expect(star(), findsNWidgets(2));
    expect(find.text('Couverture'), findsOneWidget);
  });

  testWidgets('tapping the star promotes THAT photo in one write', (
    tester,
  ) async {
    await pumpWith(tester, ['a', 'b', 'c']);
    // Tiles render in list order, so the last star sits on 'c' (index 2).
    await tester.tap(star().last);
    await settleMocks(tester);
    verify(() => service.updateGalleryPhotos(any(), ['c', 'a', 'b'])).called(1);
  });
}
