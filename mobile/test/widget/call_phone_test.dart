import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/external_link.dart';

/// docs/design/pro-app-batch7.md §2.11 (B7.11) — « Appeler » opens the dialer
/// WITHOUT asking `canLaunchUrl` first: on Android 11+ that question answers
/// « no » for a scheme the app has not declared (`tel` is not), and on iOS
/// for one missing from `LSApplicationQueriesSchemes` — so two buttons did
/// nothing on most phones, without a word. When nothing opens, it says so.
void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  late List<String> asked;

  Future<void> pumpButton(WidgetTester tester, String number) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => callPhone(context, number),
              child: const Text('Appeler'),
            ),
          ),
        ),
      ),
    );
  }

  void answer(Future<Object?> Function(MethodCall call) handler) {
    asked = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          asked.add('${call.method} ${(call.arguments as Map)['url']}');
          return handler(call);
        });
  }

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets('opens tel: straight away — never asks canLaunch — and the '
      'spaces of the number go', (tester) async {
    answer((_) async => true);
    await pumpButton(tester, '+225 07 00 00 00 01');
    await tester.tap(find.text('Appeler'));
    await tester.pumpAndSettle();
    expect(asked, ['launch tel:+2250700000001']);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('nothing opens (no dialer) → « Impossible d’ouvrir '
      'l’application. »', (tester) async {
    answer((_) async => false);
    await pumpButton(tester, '+2250700000001');
    await tester.tap(find.text('Appeler'));
    await tester.pumpAndSettle();
    expect(find.text('Impossible d’ouvrir l’application.'), findsOneWidget);
  });

  testWidgets('the platform throws → the same sentence, never silence', (
    tester,
  ) async {
    answer((_) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'));
    await pumpButton(tester, '+2250700000001');
    await tester.tap(find.text('Appeler'));
    await tester.pumpAndSettle();
    expect(find.text('Impossible d’ouvrir l’application.'), findsOneWidget);
  });

  test('no tel: is opened anywhere but callPhone', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('core/utils/external_link.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r"""['"]tel:""").allMatches(src)) {
        final line = src.substring(0, m.start).split('\n').length;
        offenders.add('${f.path}:$line');
      }
    }
    expect(offenders, isEmpty, reason: 'call through callPhone');
  });

  test('Android declares the tel scheme in <queries> (belt and braces)', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final queries = RegExp(
      r'<queries>(.*?)</queries>',
      dotAll: true,
    ).firstMatch(manifest)!.group(1)!;
    expect(queries, contains('android:scheme="tel"'));
  });
}
