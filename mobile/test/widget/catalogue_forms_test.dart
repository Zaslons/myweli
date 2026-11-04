import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/artist.dart';
import 'package:myweli/models/service.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_service_provider.dart';
import 'package:myweli/screens/provider/artists/artist_form_screen.dart';
import 'package:myweli/screens/provider/services/service_form_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/widgets/common/app_text_field.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';

/// docs/design/hygiene-batch9.md §2.6 (B9.7) — the staff form and the
/// service form: each fault under its field (SYSTEM.md §14 rule 1), the first
/// one focused in reading order, nothing sent, and asked again as the value
/// changes once errored (rule 2) — the price ceiling against its floor too.
void main() {
  final pro = _CountingProService();
  final artists = _CountingArtistService();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = pro;
    serviceLocator.proArtistService = artists;
    serviceLocator.imageUploadService = MockImageUploadService();
  });

  setUp(() {
    pro.created = 0;
    artists.created = 0;
  });

  Future<void> open(WidgetTester tester, Widget form) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider(create: (_) => ProAuthProvider()),
          ChangeNotifierProvider(create: (_) => ProServiceProvider()),
          ChangeNotifierProvider(create: (_) => ProArtistProvider()),
        ],
        home: form,
      ),
    );
    await settleMocks(tester);
  }

  Finder field(String label) =>
      find.byWidgetPredicate((w) => w is AppTextField && w.label == label);
  Finder input(String label) =>
      find.descendant(of: field(label), matching: find.byType(TextField));
  Finder under(String label, String message) =>
      find.descendant(of: field(label), matching: find.text(message));
  bool focused(WidgetTester tester, String label) => tester
      .widget<EditableText>(
        find.descendant(of: field(label), matching: find.byType(EditableText)),
      )
      .focusNode
      .hasFocus;

  Future<void> type(WidgetTester tester, String label, String value) async {
    await tester.enterText(input(label), value);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await settleMocks(tester);
  }

  group('the staff form', () {
    testWidgets('no name: said under « Nom », focused, nothing sent', (
      tester,
    ) async {
      await open(tester, const ArtistFormScreen());
      await save(tester);

      expect(under('Nom', 'Saisissez un nom.'), findsOneWidget);
      expect(focused(tester, 'Nom'), isTrue);
      expect(artists.created, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('one letter: the rule says how long; a real name clears it '
        'without a second press', (tester) async {
      await open(tester, const ArtistFormScreen());
      await type(tester, 'Nom', 'A');
      await save(tester);

      expect(
        under('Nom', 'Le nom doit comporter au moins 2 caractères.'),
        findsOneWidget,
      );
      expect(artists.created, 0);

      await type(tester, 'Nom', 'Awa');
      expect(
        find.text('Le nom doit comporter au moins 2 caractères.'),
        findsNothing,
      );
    });
  });

  group('the service form', () {
    testWidgets('a blank press: name, price and length each under their '
        'field, the name focused, nothing sent', (tester) async {
      await open(tester, const ServiceFormScreen());
      await save(tester);

      expect(
        under('Nom du service', 'Indiquez le nom du service.'),
        findsOneWidget,
      );
      expect(
        under('Prix — à partir de (FCFA)', 'Indiquez un prix.'),
        findsOneWidget,
      );
      expect(
        under('Ou durée personnalisée (minutes)', 'Indiquez une durée.'),
        findsOneWidget,
      );
      expect(
        find.text('Le prix maximum doit être supérieur au prix de départ.'),
        findsNothing,
        reason: 'the ceiling is optional',
      );
      expect(focused(tester, 'Nom du service'), isTrue);
      expect(pro.created, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a ceiling below its floor: said under the ceiling; lowering '
        'the floor clears it — the pair is asked again', (tester) async {
      await open(tester, const ServiceFormScreen());
      await type(tester, 'Nom du service', 'Tresses');
      await type(tester, 'Prix — à partir de (FCFA)', '5000');
      await type(tester, 'Prix maximum (optionnel)', '3000');
      await type(tester, 'Ou durée personnalisée (minutes)', '120');
      await save(tester);

      const ceiling = 'Le prix maximum doit être supérieur au prix de départ.';
      expect(under('Prix maximum (optionnel)', ceiling), findsOneWidget);
      expect(pro.created, 0);

      await type(tester, 'Prix — à partir de (FCFA)', '2000');
      expect(find.text(ceiling), findsNothing);
    });
  });
}

class _CountingProService extends MockProService {
  int created = 0;

  @override
  Future<ApiResponse<Service>> createService(
    SalonId providerId,
    Map<String, dynamic> serviceData,
  ) {
    created++;
    return super.createService(providerId, serviceData);
  }
}

class _CountingArtistService extends MockProArtistService {
  int created = 0;

  @override
  Future<ApiResponse<Artist>> createArtist(
    SalonId providerId,
    Map<String, dynamic> data,
  ) {
    created++;
    return super.createArtist(providerId, data);
  }
}
