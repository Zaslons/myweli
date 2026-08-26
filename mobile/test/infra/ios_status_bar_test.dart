import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iOS status bar is visible, and Flutter controls its icon brightness.
///
/// ## Why this file exists
///
/// `UIStatusBarHidden=true` arrived in the branding P4 native-splash plist
/// rewrite (144ef89, 2026-07-02) with no stated rationale — splash collateral
/// never scoped back — and hid the time/battery/network in BOTH apps (one
/// Info.plist serves both flavours) until the owner noticed during the
/// demo-salon curation on 2026-08-26. Nothing in the repo depended on it,
/// nothing tested it, and Android showed the bar all along (only its
/// LaunchTheme is fullscreen), so the asymmetry shipped silently.
///
/// The second key is the subtle half: with
/// `UIViewControllerBasedStatusBarAppearance=false` the plist is the SOLE
/// authority on iOS and every `SystemUiOverlayStyle` / `AnnotatedRegion` in
/// the app is a no-op — including the three the dark surfaces now rely on
/// (story viewer, salon photo lightbox, review-photo lightbox).
void main() {
  // XML comments stripped before matching: the plist now carries a comment
  // QUOTING both keys and the old values to explain the history — the
  // four-times-repeated guard defect in this repo is matching one's own
  // explanatory comment.
  final plist = File(
    'ios/Runner/Info.plist',
  ).readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  /// The plist value that FOLLOWS [key] — `<true/>` or `<false/>`.
  String valueOf(String key) {
    final m = RegExp('<key>$key</key>\\s*<(true|false)/>').firstMatch(plist);
    expect(m, isNotNull, reason: '$key is declared in Info.plist');
    return m!.group(1)!;
  }

  test('the status bar is not hidden', () {
    expect(
      valueOf('UIStatusBarHidden'),
      'false',
      reason:
          'true hides time/battery/network in both apps — the 2026-07-02 '
          'splash collateral this test exists to keep out',
    );
  });

  test('view controllers (Flutter) own the status bar style', () {
    expect(
      valueOf('UIViewControllerBasedStatusBarAppearance'),
      'true',
      reason:
          'false makes the plist the sole authority and turns every '
          'AnnotatedRegion/SystemUiOverlayStyle into a no-op on iOS — the '
          'three dark surfaces would show invisible dark icons',
    );
  });
}
