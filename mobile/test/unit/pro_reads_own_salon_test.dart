import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A pro surface resolves its own salon BY ACCOUNT, never by public id.
///
/// **Three documents already state this as a fact, and it was false.**
/// `docs/BACKEND.md` T51: *« Pro-own surfaces resolve by account and keep
/// working. »* `docs/design/pro-salon-lifecycle.md` §49-53: *« The pro's own
/// surfaces (`/me/provider`, journal, catalogue…) resolve by account →
/// unaffected. »* And its B4 note, on the web preview: *« fed from
/// /me/provider: owner-scoped by construction, no new endpoint, no T51
/// change. »* Web obeyed all three. Mobile read its own salon through the
/// unauthenticated `GET /providers/{id}` from four places, including the
/// owner's pre-publish preview.
///
/// **Why a source pin and not a behavioural test.** Nothing is user-visible
/// today — the public route still serves drafts, so all four surfaces work. The
/// property is about WHICH DOOR the app knocks on, and the only artifact that
/// records a door is the source. A behavioural test would have to close the
/// public route first, which is the very slice this one unblocks
/// (`salon-state-and-refusals.md` Decision C).
///
/// The dependency-injection file states the rule the pin enforces
/// (`core/di/dependency_injection.dart`): every pro service is constructed with
/// `SecureSessionStore('myweli_provider_session')`, while `providerService`
/// takes no session **by construction**. It is the public, anonymous surface.
/// A pro screen reaching for it is reaching past its own credentials.
///
/// **WHAT THIS PIN CANNOT SEE, and what covers it instead.** The fourth
/// offender named no forbidden token: `/pro/apercu` constructed
/// `ProviderDetailScreen(preview: true)`, and the public fetch happened inside
/// that SHARED screen, which the consumer app owns and legitimately uses. A
/// source pin scoped to pro files is blind to it by construction — this one
/// went red on three of four, which is exactly the shape of a gate that would
/// have gone green while the worst surface stayed broken. The preview is held
/// behavourally instead, by `salon_preview_test.dart`: it pumps the preview
/// against a service that FAILS the test if it is called at all.
void main() {
  /// Comments are not code — the hole A14c found in `salon_time_pin_test` and
  /// that `french_test.dart:51` fixes the same way. Without this, the docstring
  /// above would fail the pin it describes.
  String stripDartComments(String src) => src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp('//[^\n]*'), '');

  /// Every file that belongs to the pro app.
  ///
  /// `lib/providers/pro_*.dart` rather than all of `lib/providers/`: the
  /// consumer's `ProviderProvider` legitimately uses the public service — it IS
  /// the public surface — and the pro app registers it only so the shared
  /// detail screen has a notifier to read. What the pro app must not do is make
  /// it fetch.
  List<File> proFiles() => [
    ...Directory('lib/screens/provider').listSync(recursive: true),
    ...Directory(
      'lib/providers',
    ).listSync().where((e) => e.path.split('/').last.startsWith('pro_')),
    File('lib/core/router/pro_router.dart'),
    File('lib/main_pro.dart'),
  ].whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

  test('no pro surface reads its own salon through the public route', () {
    // `getProviderById` is the public service's method and `loadProviderById`
    // is the consumer notifier's wrapper around it — a pro file naming either
    // has gone round the back of its own session, whichever route it took.
    const forbidden = [
      'serviceLocator.providerService',
      'getProviderById',
      'loadProviderById',
    ];

    final files = proFiles();
    final offenders = <String>[];
    for (final f in files) {
      final src = stripDartComments(f.readAsStringSync());
      for (final token in forbidden) {
        if (src.contains(token)) offenders.add('${f.path} → $token');
      }
    }

    expect(
      files.length,
      greaterThan(20),
      reason:
          'a pin whose glob matches nothing is green about nothing (§21 row '
          '70) — if this fails the paths moved, not the property',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'use `serviceLocator.proService.getMyProvider()` — GET /me/provider '
          'resolves the salon from the token and returns the SAME document, '
          'so there is nothing to gain by asking anonymously and a draft '
          'salon to lose when the public read closes',
    );
  });
}
