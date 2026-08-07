import 'dart:io';

import 'package:test/test.dart';

/// Every `asset:` the seed hands out must exist in the app that has to render it.
///
/// **This is here because it did not.** The seeded salons carried
/// `asset:assets/images/salon1.jpg`, `salon2.jpg`, `barber1.jpg` and
/// `nails1.jpg` — four files that have **never existed in this repository**,
/// checked against the whole of git history, not just the working tree. Anyone
/// running the app against a real backend saw four broken images on the consumer
/// home screen, and that was true from the day the seed was written.
///
/// **Why nothing else could catch it.** The widget tests, the goldens and every
/// screen test run on `MockData`, which points at
/// `assets/images/providers/*_photo.png` — files that DO exist. So the mock and
/// the seed had quietly diverged, and the half with the coverage was the half
/// that was right. The API-level funnel smoke talks to this server and never
/// renders a pixel, so a string that is a valid `String` but an invalid asset
/// passes it untouched. The defect was reachable only by running the app against
/// the server, which is exactly how it was eventually found.
///
/// The seam is a **string convention across two packages** — the server writes
/// `asset:<path>`, `TimedCachedImage` resolves it against the Flutter bundle —
/// and a convention with no compiler and no test is a convention that drifts.
/// This is the compiler.
void main() {
  test('every seeded asset: URL resolves to a file the app bundles', () {
    final repo = File('lib/src/providers_repository.dart');
    expect(
      repo.existsSync(),
      isTrue,
      reason: 'run from backend/ — the seed is read as a source file',
    );

    // The app root, relative to backend/. Resolved rather than assumed so the
    // failure is "the app moved", not a confusing "asset missing".
    final mobile = Directory('../mobile');
    expect(
      mobile.existsSync(),
      isTrue,
      reason: 'the monorepo layout changed; this test needs to move with it',
    );

    final urls = RegExp(
      r'''asset:([^'"]+)''',
    ).allMatches(repo.readAsStringSync()).map((m) => m.group(1)!).toSet();

    expect(
      urls,
      isNotEmpty,
      reason:
          'the seed stopped using asset: URLs — if that is deliberate, delete '
          'this test rather than letting it pass vacuously',
    );

    final missing =
        urls.where((p) => !File('${mobile.path}/$p').existsSync()).toList()
          ..sort();

    expect(
      missing,
      isEmpty,
      reason:
          'the seed points at ${missing.length} asset(s) the app does not '
          'bundle, so every salon using them renders a placeholder instead of '
          'a photo: ${missing.join(', ')}',
    );
  });
}
