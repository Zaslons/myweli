import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// **The 30-day log-retention promise, tied to the number behind it.**
///
/// `web/app/politique-confidentialite/page.tsx` tells users « Ces journaux …
/// sont supprimés automatiquement au bout de 30 jours ». That is a
/// representation to users and to the app stores.
///
/// Until 2026-08-22 nothing in this repo recorded the number it rests on:
/// `_Default` appeared in one prose sentence in ROADMAP.md, and
/// `web/tests/legal.test.tsx` asserted only that *the page says 30* — a
/// one-directional guard against deleting the disclosure. Raise the bucket to
/// 400 days and every check stays green while the sentence becomes false.
///
/// This is the offline half: **manifest ↔ published page**. It runs on every
/// push, because `ci.yml`'s backend job is a bare `dart test`. The live half —
/// **manifest ↔ the actual bucket** — is `infra/gcp/97-verify-log-retention.sh`,
/// which needs GCP credentials and runs on the daily cron. Neither alone is
/// enough: this test cannot see GCP, and the script cannot see whether someone
/// changed the sentence.
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  final manifestFile = File('$root/infra/gcp/logging-manifest.json');
  final checkerFile = File('$root/infra/gcp/97-verify-log-retention.sh');

  test('the manifest and the checker are where this test thinks they are', () {
    // Without this the whole file degrades into vacuous passes the moment
    // either is moved or renamed.
    expect(manifestFile.existsSync(), isTrue, reason: manifestFile.path);
    expect(checkerFile.existsSync(), isTrue, reason: checkerFile.path);
  });

  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final buckets = manifest['buckets'] as Map<String, dynamic>;

  test('the manifest names at least one bucket', () {
    // A manifest with an empty `buckets` map would make every assertion below
    // iterate nothing and report success — the shape of vacuity this project
    // keeps finding.
    expect(buckets, isNotEmpty);
  });

  group('every published claim in the manifest is on the page it names', () {
    for (final entry in buckets.entries) {
      final b = entry.value as Map<String, dynamic>;
      final days = b['maxRetentionDays'] as int;
      final claim = b['backsPublishedClaim'] as Map<String, dynamic>;
      final page = File('$root/${claim['page']}');

      test('${entry.key}: the page exists', () {
        expect(page.existsSync(), isTrue, reason: page.path);
      });

      test('${entry.key}: the page states the manifest number, and only it', () {
        final src = page.readAsStringSync();

        // Every duration figure on the page, with the JSX stripped — the number
        // and its unit are split across a `<strong>` tag and a newline in the
        // source, so a naive substring match on "30 jours" would depend on
        // formatting rather than content.
        final text = src
            .replaceAll(RegExp(r'<[^>]*>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ');
        final figures = RegExp(
          r'(\d+)\s*jours',
        ).allMatches(text).map((m) => int.parse(m.group(1)!)).toSet();

        expect(
          figures,
          isNotEmpty,
          reason:
              'the page states no retention period at all — the disclosure '
              'has been deleted, which is what legal.test.tsx also guards',
        );
        expect(
          figures,
          {days},
          reason:
              'the page and infra/gcp/logging-manifest.json disagree about '
              'how long logs are kept. One of them is now a false statement to '
              'users: the page says $figures, the manifest ceiling is $days',
        );
      });

      test('${entry.key}: the claim text really appears', () {
        // The figures check above would still pass if the sentence were
        // rewritten to mean something else while keeping the number.
        final flat = page
            .readAsStringSync()
            .replaceAll(RegExp(r'<[^>]*>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ');
        expect(flat, contains(claim['text'] as String));
      });
    }
  });

  group('the live checker cannot write', () {
    final checker = checkerFile.readAsStringSync();

    /// Shell comments stripped before matching. **This file caught the trap in
    /// itself:** the `locked` assertion below matched `== "false"` inside the
    /// comment that explains the footgun, and failed on a script that does the
    /// right thing. That is the fourth time in this repo a check has matched a
    /// string present only in a comment — one of them the comment explaining
    /// the very defect it was meant to catch.
    final code = checker
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#'))
        .join('\n');

    test('it names no mutating gcloud verb', () {
      // The header promises read-only, and this is what makes that a property
      // rather than a comment. Matched anywhere in the file, comments included:
      // a commented-out `buckets update` is a line someone uncomments at 2am.
      //
      // The verbs are gcloud's actual subcommand paths. `r2_manifest_test.dart`
      // records why that matters — its first draft guarded `r2 lifecycle add`
      // while wrangler spells it `r2 bucket lifecycle add`, so the guard could
      // not fire and a mutation appending exactly that line watched it pass.
      const mutating = [
        'logging buckets update',
        'logging buckets create',
        'logging buckets delete',
        'logging buckets undelete',
        'logging settings update',
        'logging sinks create',
        'logging sinks update',
        'logging sinks delete',
        'projects add-iam-policy-binding',
        'iam roles create',
        'iam roles update',
      ];
      // **This used to read `code`, which has comments stripped — so the claim
      // three lines above was false.** Verified on 2026-08-23 by adding
      // `# gcloud logging buckets update _Default --retention-days=400` to the
      // script and watching this test pass. The whole point is that a
      // commented-out mutation is a line someone uncomments at 2am, so it is
      // matched against the raw file. None of the script's own prose names a
      // mutating verb, so nothing had to be reworded.
      for (final verb in mutating) {
        expect(
          checker.contains(verb),
          isFalse,
          reason: 'the read-only checker contains `$verb`',
        );
      }
    });

    test('it reads the bucket at all — otherwise it verifies nothing', () {
      expect(code, contains('logging buckets describe'));
    });

    test('it refuses an empty manifest rather than reporting success', () {
      // The vacuity guard inside the shell script itself. Without it a manifest
      // whose `buckets` map is empty exits 0 having checked nothing.
      expect(code, contains('refusing to report success'));
    });

    test('it treats an absent `locked` field as false, not as a string', () {
      // `gcloud logging buckets describe` OMITS `locked` when it is false — the
      // control is `_Required`, which GCP always locks and which does print
      // `locked: true`. Comparing a shell variable against the string 'false'
      // passes for the wrong reason.
      expect(
        code.contains("== \"false\""),
        isFalse,
        reason:
            'comparing against the string "false" cannot distinguish '
            '"not locked" from "field absent"',
      );
    });
  });
}
