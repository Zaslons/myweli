import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/text_fit.dart';
import 'package:myweli/widgets/common/confirm_dialog.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';
import '_a11y.dart';

/// Every literal title passed to `showConfirmDialog` / `showInputDialog` in
/// `lib/` — read from the source, so a new dialog is swept the day it lands.
List<String> _dialogTitles() {
  final titles = <String>{};
  final call = RegExp(
    r'''show(?:Confirm|Input)Dialog\([^;]*?title:\s*'([^'$]+)'\s*,''',
    dotAll: true,
  );
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    for (final m in call.allMatches(f.readAsStringSync())) {
      titles.add(m.group(1)!);
    }
  }
  return titles.toList()..sort();
}

/// A hyphen between two letters: a legal line break (« rendez- » / « vous »).
final RegExp _hyphenated = RegExp(r'\p{L}-\p{L}', unicode: true);

/// docs/design/pro-app-batch7.md §2.2 (B7.2) — no dialog title breaks inside
/// a word at 200 % on a 360 dp phone. The title sat beside its icon in a Row,
/// 232 dp at 2×, and « Abandonner les modifications ? » broke twice
/// (« Abandonne/r », « modifi/cations »): « modifications » alone needs
/// 272 dp. Measured WITH the icon, the widest a title can be asked to fit.
void main() {
  final titles = _dialogTitles();

  // Roboto, the font the phone draws: with none loaded every glyph is a
  // square of the font size, and every title reads as broken.
  setUpAll(loadRealFonts);

  test('the sweep found the dialogs (17 literal titles on 2026-10-22)', () {
    expect(titles.length, greaterThanOrEqualTo(17));
  });

  for (final title in titles) {
    testWidgets('« $title » is whole at 200 % on 360 dp', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpApp(
        tester,
        theme: AppTheme.themeData(fontFamily: kRealFont),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showConfirmDialog(
                context,
                title: title,
                message: 'Le message.',
                confirmLabel: 'OK',
                icon: Icons.warning_amber_rounded,
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      if (_hyphenated.hasMatch(title)) {
        // The engine may break after « rendez- » — a legal break, and the
        // house rule (`_a11y.dart`: hyphenated labels are not named to
        // `expectNoMidWordBreak`). So the pieces it may NOT break inside —
        // `TextFit.tokens`, which split there too — must each fit the box.
        final p = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(title),
            matching: find.byType(RichText),
          ),
        );
        for (final token in TextFit.tokens(title)) {
          final tp = TextPainter(
            text: TextSpan(text: token, style: p.text.style),
            textDirection: TextDirection.ltr,
            textScaler: p.textScaler,
          )..layout();
          expect(
            p.size.width + 0.5,
            greaterThanOrEqualTo(tp.width),
            reason: '« $token » breaks inside at 200 % on 360 dp',
          );
          tp.dispose();
        }
      } else {
        expectNoMidWordBreak(tester, title, 'the dialog at 200 % on 360 dp');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
