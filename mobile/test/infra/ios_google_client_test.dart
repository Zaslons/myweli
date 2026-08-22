import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The per-flavour Google OAuth client — one `Info.plist`, two apps.
///
/// ## Why this file exists
///
/// `com.myweli.pro` had **no iOS OAuth client at all** until 2026-08-22, and
/// `ios/Runner/Info.plist` — which is shared by both flavours — hardcoded the
/// consumer's in two places. The Pro app therefore rendered a « Continuer avec
/// Google » button that authenticated as the consumer's client under the Pro
/// bundle id, which Google rejects. App Store rule 2.1.
///
/// **Nothing failed loudly, and that is the part worth understanding.**
/// `google_sign_in_ios` resolves the client id from the bundled
/// `GoogleService-Info.plist` first and only falls back to `GIDClientID`. Pro's
/// config had no `CLIENT_ID` key, so it fell through to a fallback that was
/// *wrong* rather than *missing* — no null, no crash, no log. The redirect
/// scheme in `CFBundleURLSchemes` has no fallback at all.
///
/// It was also invisible from the repository: the checked-in plist is only a
/// copy of console state, and the absence was confirmed against the Firebase
/// API rather than the file. So this file pins what the repo CAN see — that the
/// two flavours carry different clients and that `Info.plist` names neither.
///
/// A grep rather than an Xcode build, for the reason
/// `ios_entitlements_test.dart` gives: CI has no Mac, and a wrong constant is
/// exactly what a grep can see.
void main() {
  /// XML comments stripped. Two guards in this repo have matched a string that
  /// existed only in a comment — and the comment this file adds to
  /// `Info.plist` names `$(GOOGLE_CLIENT_ID)` while explaining it.
  String plist(String path) => File(
    path,
  ).readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  String? value(String body, String key) {
    final i = body.indexOf('<key>$key</key>');
    if (i < 0) return null;
    final m = RegExp(r'<string>([^<]*)</string>').firstMatch(body.substring(i));
    return m?.group(1);
  }

  String config(String flavour) =>
      plist('ios/config/$flavour/GoogleService-Info.plist');

  group('each flavour carries its own Google client', () {
    for (final flavour in ['consumer', 'pro']) {
      test('$flavour has a client id, its reverse, and its own bundle id', () {
        final body = config(flavour);
        final expectedBundle = flavour == 'consumer'
            ? 'com.myweli.app'
            : 'com.myweli.pro';

        expect(
          value(body, 'CLIENT_ID'),
          isNotNull,
          reason:
              'without CLIENT_ID the SDK falls back to Info.plist\'s '
              'GIDClientID — which is the other app\'s client, and Google '
              'rejects it against this bundle id',
        );
        expect(value(body, 'REVERSED_CLIENT_ID'), isNotNull);
        expect(value(body, 'BUNDLE_ID'), expectedBundle);
      });

      test('$flavour\'s reversed id is derived from its own client id', () {
        final body = config(flavour);
        final id = value(
          body,
          'CLIENT_ID',
        )!.replaceAll('.apps.googleusercontent.com', '');
        expect(
          value(body, 'REVERSED_CLIENT_ID'),
          'com.googleusercontent.apps.$id',
          reason:
              'the redirect scheme must belong to the SAME client — pasting '
              'one app\'s plist over the other is how this defect arrives',
        );
      });
    }

    test('and the two flavours are NOT the same client', () {
      // The whole defect, in one line.
      expect(
        value(config('consumer'), 'CLIENT_ID'),
        isNot(value(config('pro'), 'CLIENT_ID')),
        reason: 'one client cannot serve two bundle ids',
      );
    });
  });

  group('Info.plist names no client of its own', () {
    final body = plist('ios/Runner/Info.plist');

    test('GIDClientID and the URL scheme are build settings', () {
      expect(value(body, 'GIDClientID'), r'$(GOOGLE_CLIENT_ID)');
      expect(
        body.contains(r'$(GOOGLE_REVERSED_CLIENT_ID)'),
        isTrue,
        reason: 'CFBundleURLSchemes has no runtime fallback; it must vary here',
      );
    });

    test('no literal googleusercontent id survives anywhere in it', () {
      // A literal is the defect itself: one Info.plist, two apps.
      expect(
        RegExp(r'\d{6,}-[a-z0-9]{20,}').hasMatch(body),
        isFalse,
        reason:
            'a hardcoded client id in the shared Info.plist is the consumer\'s '
            'client in the Pro build',
      );
    });
  });

  group('the wiring: every configuration gets a value', () {
    /// The half that matters, mirroring `ios_entitlements_test.dart`'s
    /// setup_flavours assertion. `$(GOOGLE_CLIENT_ID)` expands to EMPTY for any
    /// configuration the script forgets — sign-in with no configuration at all,
    /// a worse failure than the one this replaced, and equally silent.
    final script = File('ios/tool/setup_flavours.rb')
        .readAsStringSync()
        .split('\n')
        .map((l) => l.trimLeft().startsWith('#') ? '' : l)
        .join('\n');

    test('the script sets both settings', () {
      expect(script, contains("build_settings['GOOGLE_CLIENT_ID']"));
      expect(script, contains("build_settings['GOOGLE_REVERSED_CLIENT_ID']"));
    });

    test('both flavours declare a client id in the table', () {
      expect(script, contains('google_client_id:'));
      for (final flavour in ['consumer', 'pro']) {
        final id = value(config(flavour), 'CLIENT_ID')!;
        expect(
          script,
          contains(id),
          reason:
              '$flavour\'s client id is in its GoogleService-Info.plist but '
              'not in the script, so the build setting would not match the '
              'file the copy phase bundles',
        );
      }
    });

    test('the flavourless configurations are covered too', () {
      // Debug/Profile/Release still exist and still build the consumer app.
      expect(
        script,
        contains("FLAVOURS['consumer'][:google_client_id]"),
        reason:
            'left unset, the legacy configurations expand the setting to empty',
      );
    });
  });
}
