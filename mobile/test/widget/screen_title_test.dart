import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/screen_title.dart';

/// [ScreenTitle] makes an app bar's title a heading a phone can read.
///
/// What a phone reads is `headingLevel > 0`: iOS sets VoiceOver's Header trait
/// from it since Flutter 3.47, Android TalkBack's since 3.38, and neither sends
/// the number on (docs/design/mobile-flutter-3.47-upgrade.md §3.1). So these
/// assert on the level of the semantics node that carries the title's text —
/// the node the screen reader focuses — not on `header`, which the bar still
/// sets and which no phone reads any more.
void main() {
  Future<SemanticsData> titleNode(WidgetTester tester, Widget title) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: title),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    return tester.getSemantics(find.text('Accueil')).getSemanticsData();
  }

  testWidgets('a ScreenTitle in an app bar is a level-1 heading', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final node = await titleNode(tester, const ScreenTitle('Accueil'));
    expect(node.headingLevel, 1);
    handle.dispose();
  });

  testWidgets('the control: a bare Text title is no heading on a phone', (
    tester,
  ) async {
    // The bar's own `header: true` is still there — and reaches no phone. If
    // this ever reads > 0, the SDK changed and the reason for ScreenTitle
    // with it.
    final handle = tester.ensureSemantics();
    final node = await titleNode(tester, const Text('Accueil'));
    expect(node.headingLevel, 0);
    expect(node.flagsCollection.isHeader, isTrue);
    handle.dispose();
  });

  testWidgets('it paints the bar\'s own title, unchanged', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(appBar: AppBar(title: const ScreenTitle('Accueil'))),
      ),
    );
    final bare = tester.widget<Text>(find.text('Accueil'));
    // No style of its own: the bar's DefaultTextStyle decides, as for a Text.
    expect(bare.style, isNull);
  });
}
