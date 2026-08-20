// Runbooks are rendered as MARKDOWN before they are emailed, and markdown eats
// exactly the characters a runbook is made of.
//
// Observed in a delivered alert email (2026-08-20), not inferred:
//   identity_limits.dart  ->  identity<em>limits.dart   the underscore VANISHES
//   --limit=50            ->  &ndash;limit=50           gcloud rejects an en dash
//   'value(...)'          ->  &lsquo;value(...)&rsquo;  the shell rejects a curly quote
//
// So the first command the operator is told to paste could not be pasted, in
// seven of nine policies. The same email also carried an example log line the
// code cannot produce (`ceiling=` where it prints `limit=`) and told the
// operator to set an environment variable that does not exist.
//
// A code span survives — the cron-legacy email delivered a real <code> tag —
// so the rule is: anything an operator would TYPE lives inside backticks.
//
// And because every one of these heredocs is UNQUOTED, a bare backtick in the
// script is command substitution. It must be written \` or the shell runs it.
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

/// Every runbook string an alert script uploads, JSON-unescaped.
///
/// Two shapes, and missing either would make this file lie: most scripts inline
/// `"content": "..."`, but `80-uptime-checks.sh` builds `DOC="..."` and
/// interpolates it, and `88-email-budget-alert.sh` ships TWO policies. A first
/// draft of this guard read one string per file and reported the rest green.
Map<String, String> _runbooks() {
  final out = <String, String>{};
  for (final f in Directory('../infra/gcp').listSync().whereType<File>()) {
    if (!f.path.endsWith('.sh')) continue;
    final name = f.uri.pathSegments.last;
    var i = 0;
    for (final line in f.readAsLinesSync()) {
      final m = RegExp(r'(?:"content": "|^\s*DOC=")(.*)"').firstMatch(line);
      if (m == null) continue;
      final raw = m.group(1)!;
      // an interpolation, resolved elsewhere
      if (raw.startsWith(r'$')) continue;
      out['$name#${i++}'] = raw
          // The file holds \\n and \\" (the shell strips one level in the
          // unquoted heredoc, JSON strips the second). Decoding only one level
          // left a stray backslash before every newline, so a paragraph split
          // on \n\n never matched and every runbook read as ONE paragraph.
          .replaceAll(r'\\n', '\n')
          .replaceAll(r'\\"', '"')
          .replaceAll(r'\`', '`');
    }
  }
  return out;
}

/// The single lines that carry runbook prose, for the escaping check.
List<MapEntry<String, String>> _runbookLines() {
  final out = <MapEntry<String, String>>[];
  for (final f in Directory('../infra/gcp').listSync().whereType<File>()) {
    if (!f.path.endsWith('.sh')) continue;
    for (final line in f.readAsLinesSync()) {
      if (RegExp(r'(?:"content": "|^\s*DOC=")').hasMatch(line)) {
        out.add(MapEntry(f.uri.pathSegments.last, line));
      }
    }
  }
  return out;
}

/// Everything outside a `code span` — the part markdown is free to damage.
String _prose(String s) => s.replaceAll(RegExp('`[^`]*`'), '');

void main() {
  final books = _runbooks();

  test('the scripts that create alert policies were all found', () {
    // Guards the extraction itself: a regex that silently matched nothing
    // would make every assertion below vacuously true.
    expect(
      books.length,
      greaterThanOrEqualTo(6),
      reason: 'found: ${books.keys}',
    );
  });

  group('markdown cannot damage what an operator has to type', () {
    for (final e in books.entries) {
      test('${e.key}: identifiers with _ are in code spans', () {
        final bad = RegExp(
          r'[A-Za-z0-9][A-Za-z0-9./*-]*_[A-Za-z0-9./*_-]*',
        ).allMatches(_prose(e.value)).map((m) => m.group(0)).toSet();
        expect(
          bad,
          isEmpty,
          reason: 'markdown turns a pair of _ into <em> and DELETES them',
        );
      });

      test('${e.key}: --flags are in code spans', () {
        final bad = RegExp(
          r'(?<![-\w])--[a-z]',
        ).allMatches(_prose(e.value)).map((m) => m.group(0)).toSet();
        expect(bad, isEmpty, reason: 'markdown turns -- into an en dash');
      });

      test('${e.key}: command lines are in code spans', () {
        final bad = _prose(e.value)
            .split('\n')
            .map((l) => l.trim())
            .where((l) => RegExp(r'^(gcloud|curl|psql|kubectl) ').hasMatch(l))
            .toList();
        expect(
          bad,
          isEmpty,
          reason: 'a command outside a code span is retyped by hand',
        );
      });
    }
  });

  group(
    'these are shell strings, so a bare backtick is command substitution',
    () {
      for (final e in _runbookLines()) {
        test(
          '${e.key}: backticks escaped in ${e.value.trimLeft().split(' ').first}',
          () {
            expect(
              RegExp(r'(?<!\\)`').hasMatch(e.value),
              isFalse,
              reason: 'an unescaped ` in an unquoted heredoc or "..." RUNS',
            );
          },
        );
      }
    },
  );

  group('the shell actually emits valid JSON', () {
    // The rule the Dart-only checks could not enforce. A backtick that survives
    // into the heredoc is command substitution: the policy body is then whatever
    // that command printed, and `gcloud policies create` fails at the console
    // rather than here. Running the heredoc is the only oracle that sees it.
    for (final f in Directory('../infra/gcp').listSync().whereType<File>()) {
      if (!f.path.endsWith('.sh')) continue;
      final lines = f.readAsLinesSync();
      final starts = <int>[];
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'^\s*cat > .*<<JSON$').hasMatch(lines[i])) starts.add(i);
      }
      if (starts.isEmpty) continue;

      test(
        '${f.uri.pathSegments.last}: ${starts.length} policy body/bodies parse',
        () {
          for (final s0 in starts) {
            final end = lines.indexOf('JSON', s0);
            expect(end, greaterThan(s0), reason: 'unterminated heredoc');
            final body = [
              'cat <<JSON',
              ...lines.sublist(s0 + 1, end + 1),
            ].join('\n');
            final tmp = File('${Directory.systemTemp.path}/rb_$s0.sh')
              ..writeAsStringSync(body);
            // PROJECT and CHANNEL are resolved at RUNTIME by the authoring scripts
            // — `CHANNEL=\$(gcloud … channels list …)` — so a heredoc run bare
            // renders `"notificationChannels": [""]`. A sentinel is injected rather
            // than calling gcloud, which tests something stronger than a shape:
            // that the body actually interpolates the channel it is given.
            const sentinel = 'projects/myweli/notificationChannels/SENTINEL';
            final r = Process.runSync(
              'bash',
              [tmp.path],
              environment: {'PROJECT': 'myweli', 'CHANNEL': sentinel},
            );
            expect(r.exitCode, 0, reason: 'bash: ${r.stderr}');
            final out = (r.stdout as String).trim();
            expect(out, isNotEmpty, reason: 'the heredoc produced nothing');
            late final Map<String, dynamic> policy;
            expect(
              () => policy = jsonDecode(out) as Map<String, dynamic>,
              returnsNormally,
              reason:
                  'INVALID JSON — a live backtick ate part of it:\n'
                  '${out.length > 300 ? out.substring(0, 300) : out}',
            );
            // The parsed body is already in hand, and until 2026-08-20 nothing
            // looked at anything but the documentation. `notificationChannels`
            // is the one that matters most: the sync tool's renderer produced
            // `[""]` for every policy, and a converge built on that would have
            // detached all nine from the project's only channel while each still
            // read "enabled, no incidents".
            final channels = policy['notificationChannels'] as List<dynamic>?;
            expect(
              channels,
              isNotNull,
              reason: 'no notificationChannels declared',
            );
            expect(
              channels,
              isNotEmpty,
              reason: 'a policy that notifies nobody',
            );
            for (final ch in channels!) {
              expect(
                ch,
                sentinel,
                reason:
                    'the body did not interpolate the channel it was given — '
                    'a hardcoded or empty value silences the policy while '
                    'leaving every observable sign of health intact',
              );
            }

            expect(
              policy['enabled'],
              isTrue,
              reason:
                  'absence means enabled on write — declare it, do not infer it',
            );
            expect(policy['combiner'], 'OR');

            final conds = policy['conditions'] as List<dynamic>;
            expect(conds, isNotEmpty);
            for (final cond in conds.cast<Map<String, dynamic>>()) {
              expect(cond['displayName'], isNotNull);
              expect(
                cond.keys.where((k) => k.startsWith('condition')),
                hasLength(1),
                reason: 'exactly one condition kind per condition',
              );
            }

            final strategy = policy['alertStrategy'] as Map<String, dynamic>?;
            if (strategy != null) {
              expect(strategy['autoClose'], matches(r'^\d+s$'));
              final rl =
                  strategy['notificationRateLimit'] as Map<String, dynamic>?;
              if (rl != null) expect(rl['period'], matches(r'^\d+s$'));
            }

            final c = (policy['documentation']?['content'] ?? '') as String;
            expect(
              '`'.allMatches(c).length.isEven,
              isTrue,
              reason: 'an unclosed code span leaks into the next paragraph',
            );
            tmp.deleteSync();
          }
        },
      );
    }
  });

  test('two commands never share a paragraph', () {
    // Markdown folds a single newline into a space, so consecutive command
    // lines render run-together on one wrapped line and an operator can copy
    // both as one command. Seen in the delivered cron alert (2026-08-20): the
    // scheduler and the run-services command arrived as one visual line.
    for (final e in _runbooks().entries) {
      for (final para in e.value.split('\n\n')) {
        final cmds = RegExp('`([^`]*)`')
            .allMatches(para)
            .map((m) => m.group(1)!)
            .where((s) => RegExp(r'^(gcloud|curl|psql|kubectl) ').hasMatch(s))
            .toList();
        expect(
          cmds.length,
          lessThan(2),
          reason: '${e.key}: ${cmds.length} commands fold into one paragraph',
        );
      }
    }
  });

  test('a code span does not swallow sentence punctuation', () {
    // The transform that introduced spans matched `EMAIL_BUDGET_COLD.` with the
    // period inside, because the token pattern allows a dot (for file paths like
    // identity_limits.dart). Rendered, the operator is shown a variable name
    // that ends in a full stop, which is worse than the underscore bug it fixed.
    for (final e in _runbooks().entries) {
      for (final m in RegExp('`([^`]*)`').allMatches(e.value)) {
        final span = m.group(1)!;
        if (RegExp(r'^(gcloud|curl|psql|kubectl) ').hasMatch(span)) continue;
        expect(
          RegExp(r'[.,;:)]$').hasMatch(span),
          isFalse,
          reason:
              '${e.key}: `$span` ends in punctuation that belongs to the sentence',
        );
      }
    }
  });

  group('every textPayload filter greps a string the code actually prints', () {
    // A filter that greps a string nothing emits reads "no incidents" forever
    // and is indistinguishable from a healthy service.
    //
    // The obvious pin — `expect(script, contains('rate_limit_warning'))` — does
    // NOT catch this. Renaming the emitter to `rate_limit_warnings` throughout
    // leaves that assertion green, because the longer string contains the
    // shorter one. Watched green on 2026-08-20 while the alert was broken.
    //
    // So the filter literal is extracted from the script and looked for in the
    // source instead. That direction cannot be satisfied by a substring.
    final lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    for (final f in Directory('../infra/gcp').listSync().whereType<File>()) {
      if (!f.path.endsWith('.sh')) continue;
      final src = f.readAsStringSync();
      final lits = RegExp(
        r'textPayload:\\+"([^"\\]+)\\+"',
      ).allMatches(src).map((m) => m.group(1)!).toSet();
      if (lits.isEmpty) continue;

      test(
        '${f.uri.pathSegments.last}: ${lits.length} filter string(s) exist in lib/',
        () {
          for (final lit in lits) {
            expect(
              lib,
              contains(lit),
              reason:
                  'no file under lib/ prints "$lit", so this alert can never fire',
            );
          }
        },
      );
    }
  });

  test('no backtick is DOUBLE escaped', () {
    // A transform that escaped an already-escaped backtick produced \\` in
    // 85-db-capacity-alert.sh. In an unquoted heredoc that is a backslash
    // followed by a LIVE backtick, so `${INSTANCE}\` ran as a command and the
    // policy JSON came out malformed. The guard above only checks for an
    // UNescaped backtick and was green throughout.
    for (final f in Directory('../infra/gcp').listSync().whereType<File>()) {
      if (!f.path.endsWith('.sh')) continue;
      expect(
        f.readAsStringSync(),
        isNot(contains(r'\\`')),
        reason:
            '${f.uri.pathSegments.last}: \\` is a live backtick, not an escaped one',
      );
    }
  });

  // Every runbook that quotes a log line must quote one the code can actually
  // produce. Until 2026-08-20 this was hard-wired to the refusal policy, so the
  // two sibling policies added the same day had no format check at all — the
  // rule existed and covered one third of the surface it looked like it covered.
  const examples = [
    (
      'lib/src/security/identity_limits.dart',
      'rate_limited bucket=',
      '92-identity-limit-alert.sh#0',
    ),
    (
      'lib/src/security/identity_limits.dart',
      'rate_limit_warning bucket=',
      '94-identity-warning-alert.sh#0',
    ),
    (
      'lib/src/security/rate_limiter.dart',
      'rate_limit_unavailable bucket=',
      '94-identity-warning-alert.sh#1',
    ),
  ];

  for (final (source, prefix, key) in examples) {
    test('$key quotes a line $prefix that the code produces', () {
      // The delivered email showed `ceiling=10`. The code prints `limit=`. An
      // operator grepping the documented shape would have found nothing.
      final src = File(source).readAsStringSync();
      final fmt = RegExp("'($prefix[^']*)'").firstMatch(src);
      expect(
        fmt,
        isNotNull,
        reason: '$prefix moved or was removed from $source',
      );

      final keys = RegExp(
        r'(\w+)=',
      ).allMatches(fmt!.group(1)!).map((m) => m.group(1)).toSet();
      final book = books[key];
      expect(book, isNotNull, reason: 'no runbook found at $key');
      for (final k in keys) {
        expect(
          book,
          contains('$k='),
          reason: 'the code prints $k= and $key never mentions it',
        );
      }
      expect(
        book,
        isNot(contains('ceiling=')),
        reason: 'nothing prints ceiling=; the runbook invented it',
      );
    });
  }

  test('every env var a runbook tells you to change really exists', () {
    // The delivered email told the operator to "set the matching LIMIT_*
    // environment variable in infra/gcp/service.yaml". There is no such
    // variable, in that file or anywhere else. Generalised: if a runbook names
    // a SCREAMING_SNAKE identifier and points at service.yaml, it must be there.
    final yaml = File('../infra/gcp/service.yaml').readAsStringSync();
    for (final e in _runbooks().entries) {
      if (!e.value.contains('service.yaml')) continue;
      for (final m in RegExp(
        r'`([A-Z][A-Z0-9]*(?:_[A-Z0-9*]+)+)`',
      ).allMatches(e.value)) {
        expect(
          yaml,
          contains(m.group(1)!.replaceAll('*', '')),
          reason: '${e.key} points at an env var service.yaml does not set',
        );
      }
    }
  });
}
