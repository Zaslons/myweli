import 'package:flutter/material.dart';

/// A route's title — the text an app bar shows — as the heading a screen
/// reader finds (SYSTEM.md §13.4, « Titles are headings »).
///
/// ## Why this exists
///
/// `AppBar` marks its title with `Semantics(header: true)`, and from Flutter
/// 3.47 that makes a heading on no phone: iOS sets VoiceOver's Header trait
/// from `headingLevel > 0` only (flutter #186916), and Android has done the
/// same for TalkBack since 3.38 (flutter #175416). On iOS the bar also passes
/// `namesRoute: null`, so without this a VoiceOver user finds no screen title
/// by any means — WCAG 1.3.1, level A. The SDK's frozen `AppBar` will not
/// change, and `material_ui`'s still sets only `header: true`
/// (docs/design/mobile-flutter-3.47-upgrade.md §3.1).
///
/// So every app bar title in `lib/` is a [ScreenTitle], and
/// `test/infra/screen_title_guard_test.dart` fails on one that is not.
///
/// It paints nothing of its own: a [Text] in the bar's text style, inside a
/// [Semantics] that only adds the heading level. The goldens prove it inert.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Semantics(headingLevel: 1, child: Text(text));
}
