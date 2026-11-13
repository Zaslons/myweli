import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_gallery_provider.dart';
import 'package:myweli/screens/provider/photos/pro_photos_screen.dart';
import 'package:myweli/services/interfaces/image_upload_service_interface.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

class _MockProService extends Mock implements ProServiceInterface {}

class _MockUpload extends Mock implements ImageUploadServiceInterface {}

/// docs/design/gallery-multi-select.md — the screen half: the uploading tile
/// says which photo of the pick is on its way, and the add tile goes at the
/// server's 20-photo cap.
void main() {
  late _MockProService service;
  late _MockUpload upload;
  late Map<String, Completer<void>> holds;

  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    service = _MockProService();
    upload = _MockUpload();
    serviceLocator.proService = service;
    serviceLocator.imageUploadService = upload;
  });

  setUp(() {
    reset(service);
    reset(upload);
    holds = {};
    when(
      () => upload.uploadImage(
        source: any(named: 'source'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((inv) async {
      final source = inv.namedArguments[#source] as String;
      await holds[source]?.future;
      return ApiResponse.success('https://cdn/$source');
    });
    when(() => service.updateGalleryPhotos(any(), any())).thenAnswer(
      (i) async =>
          ApiResponse.success(i.positionalArguments[1] as List<String>),
    );
  });

  Future<ProGalleryProvider> pumpWith(
    WidgetTester tester,
    List<String> photos,
  ) async {
    final auth = await signInPro(tester);
    final gallery = ProGalleryProvider();
    when(
      () => service.getGalleryPhotos(any()),
    ).thenAnswer((_) async => ApiResponse.success(photos));
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider<ProGalleryProvider>.value(value: gallery),
        ],
        home: const ProPhotosScreen(),
      ),
    );
    await settleMocks(tester, rounds: 3);
    return gallery;
  }

  /// The add tile's tap, or null while it waits.
  VoidCallback? addTap(WidgetTester tester) => tester
      .widget<GestureDetector>(
        find
            .ancestor(
              of: find.text('Ajouter'),
              matching: find.byType(GestureDetector),
            )
            .first,
      )
      .onTap;

  testWidgets(
    'a pick of three: « Envoi 2 sur 3… », and the add tile waits throughout',
    (tester) async {
      final gallery = await pumpWith(tester, ['https://cdn/a.jpg']);
      holds['c.jpg'] = Completer<void>();
      final run = gallery.addPhotos(const SalonId('provider1'), [
        'b.jpg',
        'c.jpg',
        'd.jpg',
      ]);
      await settleMocks(tester);
      expect(find.text('Envoi 2 sur 3… 0%'), findsOneWidget);
      expect(addTap(tester), isNull);
      holds['c.jpg']!.complete();
      await run;
      await settleMocks(tester);
      expect(find.textContaining('Envoi'), findsNothing);
      expect(addTap(tester), isNotNull);
    },
  );

  testWidgets('one photo keeps « Envoi… »', (tester) async {
    final gallery = await pumpWith(tester, ['https://cdn/a.jpg']);
    holds['b.jpg'] = Completer<void>();
    final run = gallery.addPhoto(const SalonId('provider1'), 'b.jpg');
    await settleMocks(tester);
    expect(find.text('Envoi… 0%'), findsOneWidget);
    holds['b.jpg']!.complete();
    await run;
    await settleMocks(tester);
  });

  testWidgets('at 20 photos the add tile is gone; at 19 it is there', (
    tester,
  ) async {
    await pumpWith(tester, [for (var i = 0; i < 20; i++) 'https://cdn/$i.jpg']);
    await tester.scrollUntilVisible(
      find.byType(Image).last,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ajouter'), findsNothing);
  });

  testWidgets('at 19 photos the add tile is there', (tester) async {
    await pumpWith(tester, [for (var i = 0; i < 19; i++) 'https://cdn/$i.jpg']);
    await tester.scrollUntilVisible(
      find.text('Ajouter'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ajouter'), findsOneWidget);
  });
}
