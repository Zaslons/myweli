import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/widgets/common/commune_picker_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_location.dart';
import '../support/pump_app.dart';

/// The commune picker renders the LOCALITY TREE (multi-pays MP2) and returns
/// both the display name (the consumer filter contract) and the areaId (the
/// pro write paths).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupDependencyInjection);

  Widget host(void Function(CommuneChoice?) onResult, {bool allowAll = true}) =>
      wrapApp(
        providers: [ChangeNotifierProvider(create: (_) => LocalityProvider())],
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                onResult(
                  await showCommunePicker(
                    context,
                    selected: null,
                    allowAll: allowAll,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

  testWidgets('returns the tapped commune with its areaId', (tester) async {
    CommuneChoice? result;
    await tester.pumpWidget(host((r) => result = r));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Choisir une commune'), findsOneWidget);

    await tester.tap(find.text('Cocody'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.commune, 'Cocody');
    expect(result!.areaId, 'cocody'); // the pro write-path id
  });

  testWidgets('search filters the commune list', (tester) async {
    await tester.pumpWidget(host((_) {}));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'marc');
    await tester.pumpAndSettle();

    expect(find.text('Marcory'), findsOneWidget);
    expect(find.text('Cocody'), findsNothing);
  });

  testWidgets('allowAll: false hides « Toutes les communes » (pro editors)', (
    tester,
  ) async {
    await tester.pumpWidget(host((_) {}, allowAll: false));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Toutes les communes'), findsNothing);
    expect(find.text('Cocody'), findsOneWidget);
  });

  group('« Près de moi » (consumer-location.md §2.2)', () {
    late FakePhoneLocation phone;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      phone = FakePhoneLocation();
    });

    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<CommuneChoice? Function()> nearMe(WidgetTester tester) async {
      phone.install(tester);
      CommuneChoice? result;
      await tester.pumpWidget(host((r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Près de moi'));
      await frames(tester);
      return () => result;
    }

    /// Inside the sheet, never a snackbar: the sheet is a modal (§2.2,
    /// mobile-a6-feedback.md).
    void inSheet(WidgetTester tester, String sentence) {
      expect(find.text(sentence), findsOneWidget);
      expect(find.text('Choisir une commune'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    }

    testWidgets('allowed: the nearest commune, read at « medium »', (
      tester,
    ) async {
      phone.requests = [FakePhoneLocation.whileInUse];
      final result = await nearMe(tester);
      await tester.pumpAndSettle();
      expect(result(), isNotNull);
      expect(find.text('Choisir une commune'), findsNothing);
      expect(
        phone.positionSettings?['accuracy'],
        LocationAccuracy.medium.index,
      );
    });

    testWidgets('refused (Android): the list is the way', (tester) async {
      phone.requests = [FakePhoneLocation.denied];
      await nearMe(tester);
      inSheet(
        tester,
        'Localisation refusée. Choisissez votre commune dans la liste.',
      );
      expect(
        find.widgetWithText(TextButton, 'Ouvrir les réglages'),
        findsNothing,
      );
    });

    testWidgets('refused for good: « Ouvrir les réglages » opens the APP '
        'page', (tester) async {
      phone.requests = [FakePhoneLocation.deniedForever];
      await nearMe(tester);
      inSheet(
        tester,
        'Localisation bloquée. Autorisez-la dans les réglages du téléphone, '
        'ou choisissez votre commune dans la liste.',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Ouvrir les réglages'));
      await tester.pump();
      expect(phone.count('openAppSettings'), 1);
      expect(phone.count('openLocationSettings'), 0);
    });

    testWidgets('location off (Android): « Ouvrir les réglages » opens the '
        'LOCATION page', (tester) async {
      phone.service = false;
      await nearMe(tester);
      inSheet(
        tester,
        'La localisation du téléphone est désactivée. Activez-la dans les '
        'réglages, ou choisissez votre commune dans la liste.',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Ouvrir les réglages'));
      await tester.pump();
      expect(phone.count('openLocationSettings'), 1);
      expect(phone.count('openAppSettings'), 0);
    });

    testWidgets('no position: try again, or the list', (tester) async {
      phone
        ..requests = [FakePhoneLocation.whileInUse]
        ..positionError = 'LOCATION_UPDATE_FAILURE';
      await nearMe(tester);
      inSheet(
        tester,
        'Position introuvable. Réessayez, ou choisissez votre commune dans la '
        'liste.',
      );
    });

    testWidgets('iOS: restricted, and location off, with no button that '
        'cannot work', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        phone.requests = [FakePhoneLocation.denied];
        await nearMe(tester);
        inSheet(
          tester,
          'La localisation est limitée sur ce téléphone. Choisissez votre '
          'commune dans la liste.',
        );

        phone.service = false;
        await tester.tap(find.text('Près de moi'));
        await frames(tester);
        inSheet(
          tester,
          'Le service de localisation est désactivé (Réglages › '
          'Confidentialité et sécurité). Choisissez votre commune dans la '
          'liste.',
        );
        expect(
          find.widgetWithText(TextButton, 'Ouvrir les réglages'),
          findsNothing,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
