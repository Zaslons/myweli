import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// **`docs/LAUNCH.md` is the only document anyone reads under pressure**, and
/// it is the one this repository has caught lying about itself most often.
///
/// On 2026-08-22 a sweep found roughly two dozen drifted claims in it. The two
/// worst were structural rather than careless:
///
///   - the §2 table said `Forced upgrade | ❌ nothing` about a gate that had
///     been built, shipped and tested — because the table was a SECOND copy of
///     state the checkboxes already held, and two hand-maintained copies of one
///     fact disagree eventually. That table is now an index.
///   - a paragraph asserted « **Nothing has been built** (verified 2026-08-18) »
///     **three lines above** a box reading « Done 2026-08-18 ».
///
/// Prose cannot be type-checked, so this does not try. It pins the parts that
/// are mechanical — the references — because those rot silently and mislead
/// precisely when someone is following them step by step.
///
/// **What it cannot see, stated so nobody assumes otherwise:** whether a
/// sentence is true. A claim like « no signed build exists » is outside any
/// test here. What it catches is a path that moved, a script that was renamed,
/// a job that no longer exists, and a citation into code that now points
/// somewhere else — the last of which had already happened, undetected, to
/// `service_files_test.dart:728`.
/// Pure, so the rule can be exercised on fixtures even when the document
/// contains no instance of it. `lineCountOf` returns null for a path this
/// checker cannot resolve — those are the path test's business.
List<String> staleCitations(String text, int? Function(String) lineCountOf) {
  final out = <String>[];
  final re = RegExp(
    r'`([A-Za-z0-9_./-]+\.(?:dart|ts|tsx|mjs|sh|ya?ml)):(\d+)`',
  );
  for (final m in re.allMatches(text)) {
    final path = m.group(1)!, line = int.parse(m.group(2)!);
    final count = lineCountOf(path);
    if (count != null && count < line) out.add('$path:$line');
  }
  return out;
}

int? lineCountOf(String root, String path) {
  for (final c in [
    '$root/$path',
    '$root/mobile/$path',
    '$root/backend/$path',
    '$root/web/$path',
  ]) {
    final f = File(c);
    if (f.existsSync()) return f.readAsLinesSync().length;
  }
  return null;
}

void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  final doc = File('$root/docs/LAUNCH.md').readAsStringSync();

  /// Fenced blocks are worked examples, often deliberately showing a command
  /// that FAILS or a path that does not exist yet. Only prose is pinned.
  String withoutFencedBlocks(String src) {
    var fenced = false;
    return src
        .split('\n')
        .map((l) {
          if (l.trimLeft().startsWith('```')) {
            fenced = !fenced;
            return '';
          }
          return fenced ? '' : l;
        })
        .join('\n');
  }

  final prose = withoutFencedBlocks(doc);

  /// Backticked tokens that look like a repo path: a slash and a known
  /// extension. Deliberately narrow — `api.myweli.com/providers` is a URL, and
  /// `provider1`–`provider4` are data.
  final paths = RegExp(
    r'`([A-Za-z0-9_./-]+\.(?:dart|ts|tsx|mjs|sh|ya?ml|json|md))`',
  ).allMatches(prose).map((m) => m.group(1)!).toSet();

  /// The doc names files relative to whichever surface it is discussing, and
  /// often by BARE NAME — « `layout.tsx` », « `dependencies.dart` » — where the
  /// prose already makes the location obvious to a human. For those the useful
  /// question is not "is it at this path" but "does it still exist at all", so
  /// they are resolved by basename anywhere in the tree.
  final allFiles = Directory(root)
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where(
        (f) =>
            !f.path.contains('/node_modules/') &&
            !f.path.contains('/.git/') &&
            !f.path.contains('/build/') &&
            !f.path.contains('/.dart_tool/') &&
            !f.path.contains('/.next/'),
      )
      .toList();
  final basenames = allFiles.map((f) => f.path.split('/').last).toSet();

  bool resolves(String p) {
    if (!p.contains('/')) return basenames.contains(p);
    return [
      '$root/$p',
      '$root/docs/$p',
      '$root/mobile/$p',
      '$root/backend/$p',
      '$root/web/$p',
      '$root/.github/workflows/$p',
    ].any((c) => File(c).existsSync());
  }

  group('docs/LAUNCH.md — every reference it makes still exists', () {
    test('the paths it names resolve', () {
      final dead = paths.where((p) => !resolves(p)).toList()..sort();
      expect(
        dead,
        isEmpty,
        reason:
            'LAUNCH.md points at files that are not there. A reader following '
            'it step by step lands on nothing, which is worse than no citation.',
      );
    });

    test('and it names enough of them for that to mean something', () {
      // THE CONTROL. A regex that matched nothing would pass the test above
      // for the wrong reason, forever.
      expect(paths.length, greaterThan(15));
      expect(paths, contains('tool/release_build.sh'));
    });

    test('the npm scripts it tells you to run exist', () {
      final pkg =
          jsonDecode(File('$root/web/package.json').readAsStringSync())
              as Map<String, dynamic>;
      final scripts = (pkg['scripts'] as Map<String, dynamic>).keys.toSet();
      // Scanned over the WHOLE document, fences included: a command in a
      // fenced block is precisely the one a reader copies and runs. Stripping
      // fences here found zero commands and passed for the wrong reason —
      // caught by the non-empty control on the next line.
      final named = RegExp(
        r'npm run ([A-Za-z0-9:_-]+)',
      ).allMatches(doc).map((m) => m.group(1)!).toSet();
      expect(named, isNotEmpty);
      expect(
        named.difference(scripts).toList()..sort(),
        isEmpty,
        reason:
            'LAUNCH.md gives a command that web/package.json no longer defines.',
      );
    });

    test('the file:line citations point inside the file', () {
      // **This currently guards an EMPTY SET, and says so rather than reading
      // as coverage.** The document's only file:line citation was
      // `service_files_test.dart:728`, which had already rotted — the file grew
      // and the assertion moved to :768 — and it was replaced with a
      // name-only reference on 2026-08-22. So the rule is prospective: it
      // matters the next time someone writes one. The LOGIC is proven on
      // fixtures below, because a rule nobody can watch fail is the shape this
      // repository keeps having to remove.
      expect(staleCitations(prose, (p) => lineCountOf(root, p)), isEmpty);
    });

    test('and the citation rule itself can fire', () {
      int? fake(String p) => p == 'a/b.dart' ? 10 : null;
      expect(
        staleCitations('see `a/b.dart:99` for the detail', fake),
        equals(['a/b.dart:99']),
      );
      expect(staleCitations('see `a/b.dart:9` for the detail', fake), isEmpty);
      // A file this test cannot resolve is the path test's business, not this
      // one's — silently claiming it is fine would double-report.
      expect(staleCitations('see `gone/x.dart:5`', fake), isEmpty);
    });
  });

  group('the CI jobs and what protects main', () {
    /// **Pinned so that adding a job forces someone to revisit branch
    /// protection.** On 2026-08-22 `ci.yml` had ten jobs and `main` required
    /// nine contexts: `monitor-alive` — the dead-man's switch — was added in
    /// #488, after protection was configured in #482, and nothing reconciled
    /// them. It ran, it passed, and it could not block a merge, which is the
    /// one thing it exists to do.
    ///
    /// A test cannot read branch protection (that needs a token CI does not
    /// have here), so it pins the input instead: change this list and you are
    /// told, in the failure, to go and change the protection too.
    const expectedJobs = <String>{
      'analyze-and-test',
      'backend',
      'backend-boot-smoke',
      'web',
      'web-e2e',
      'web-lighthouse',
      'admin-console-build',
      'apk-size',
      'monitor-alive',
      'security',
    };

    test('ci.yml defines exactly the jobs protection was configured for', () {
      final ci =
          loadYaml(File('$root/.github/workflows/ci.yml').readAsStringSync())
              as YamlMap;
      final jobs = (ci['jobs'] as YamlMap).keys.cast<String>().toSet();
      expect(
        jobs,
        equals(expectedJobs),
        reason:
            'ci.yml gained or lost a job. Branch protection lists required '
            'CONTEXTS by name and does not follow — the last time this drifted, '
            'the dead-man\'s switch spent a day unable to block anything. '
            'Update the required checks on main, then update this list.',
      );
    });

    test('the workflows LAUNCH.md names are real', () {
      final named = RegExp(
        r'`([a-z0-9-]+\.yml)`',
      ).allMatches(prose).map((m) => m.group(1)!).toSet();
      expect(named, isNotEmpty);
      final missing = named
          .where((w) => !File('$root/.github/workflows/$w').existsSync())
          .toList();
      expect(
        missing,
        isEmpty,
        reason: 'LAUNCH.md names a workflow that is gone',
      );
    });
  });

  group('the §2 table stays an index', () {
    /// It carried a `State` column until 2026-08-22, and that column is the
    /// whole reason this file could say « three of three wired and proven » in
    /// one place and « two of the three are now live » in another. Restoring it
    /// restores the defect.
    test('it does not grow a status column again', () {
      final header = RegExp(
        r'^\| Capability \| ([^|]+) \|',
        multiLine: true,
      ).firstMatch(doc);
      expect(header, isNotNull, reason: 'the §2 table is gone entirely');
      expect(
        header!.group(1)!.trim(),
        'Where the answer lives',
        reason:
            'the §2 table is an INDEX. A second column of state is a second '
            'source of truth, and it drifted from the checkboxes within days.',
      );
    });
  });
}
