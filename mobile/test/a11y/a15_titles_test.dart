import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fonts.dart';
import '_a11y.dart';

/// One app-bar title the scan found in source, and the declaration (if any)
/// that exempts it from having to fit.
typedef TitleSite = ({String text, String where, String? reason});

/// The scan, as a **pure function over lines** so the fixture below can run the
/// shipping code rather than a copy of its regexes.
///
/// A pin whose test re-implements the pin is a pin that passes while the pin is
/// broken — `web/tests/clip-ok.test.ts` learned this first, and this signature
/// exists so the same fixture argument can be made here.
///
/// Returns the title sites, and the `clip-ok:` markers that govern **nothing**
/// — see [scanAppBarTitles]'s orphan rule below.
({List<TitleSite> sites, List<String> orphans, List<String> interpolating})
scanAppBarTitles(List<String> lines, {required String name}) {
  final literal = RegExp(r"'((?:[^'$\\]|\\.)*)'");
  // `//  clip-ok:  <why>` — the same word the web uses (WEB-SYSTEM §9.4), so
  // one vocabulary covers both surfaces for the same claim. No minimum reason
  // length: a floor teaches shorter reasons, not better ones.
  final marker = RegExp(r'^\s*//\s*clip-ok:(.*)$');

  final sites = <TitleSite>[];
  final orphans = <String>[];
  final interpolating = <String>[];
  // The line each site OPENS at, so a marker can be bound to it by distance.
  final openers = <int>{};
  final markers = <({int line, String reason})>[];

  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('//')) {
      final m = marker.firstMatch(lines[i]);
      if (m != null) markers.add((line: i, reason: m.group(1)!.trim()));
      continue;
    }

    // An `AppBar(` and the ten lines under it — a title is written on the
    // same line as often as on its own, and anchoring to `title:` alone
    // both misses the one-liners and catches every `EmptyState(title:)` in
    // the app. Measured: the naive version found 15 strings, two of them
    // not app-bar titles at all. Ten and not five because a multi-line
    // `leading:` sits between the two — `reschedule_screen.dart` opens its
    // bar at :86 and names the title at :92, and a five-line window loses
    // it silently.
    if (lines[i].contains('AppBar(')) {
      final window = lines.sublist(i, (i + 11).clamp(0, lines.length));
      for (final l in window) {
        if (l.trimLeft().startsWith('//')) continue;
        if (!l.contains('title:')) continue;
        // **The escape hatch this scan would otherwise leave open.** The
        // literal below deliberately refuses `$`, so an interpolating title is
        // invisible to every measurement in this file — and a title is exactly
        // where a datum has no width to promise. Reported, not measured: there
        // is no string to measure.
        if (l.substring(l.indexOf('title:')).contains(r'$')) {
          interpolating.add('$name:${i + 1}');
        }
        for (final m in literal.allMatches(l.substring(l.indexOf('title:')))) {
          final t = m.group(1)!;
          if (t.trim().length < 3) continue;
          openers.add(i);
          sites.add((text: t, where: '$name:${i + 1}', reason: null));
        }
        break;
      }
    }

    // `helpText:` reaches a real bar through the pickers, and the spec's
    // §2 count missed all four — including « Dates à bloquer », the string
    // the A14 device run photographed as « Dat… ». A survey of
    // `AppBar(title:` alone would not have contained row 79's own example.
    if (lines[i].contains('helpText:')) {
      for (final m in literal.allMatches(lines[i])) {
        final t = m.group(1)!;
        if (t.trim().length < 3) continue;
        openers.add(i);
        sites.add((text: t, where: '$name:${i + 1}', reason: null));
      }
    }
  }

  // Bind each marker to the sites it opens over — ten lines, the same window
  // the title scan uses, and the same one the web pin uses for its own marker.
  final exempt = <int, String>{};
  for (final m in markers) {
    final governed = openers.where((o) => o > m.line && o <= m.line + 10);
    // **A bare `// clip-ok:` is not a declaration.** It reads as one, which is
    // worse than nothing: the next person sees a declared exception and stops
    // asking. It counts as an orphan, so it cannot silently exempt anything.
    if (m.reason.isEmpty || governed.isEmpty) {
      orphans.add(
        '$name:${m.line + 1} — '
        '${m.reason.isEmpty ? 'no reason after the colon' : 'no app-bar title in the 10 lines below'}',
      );
      continue;
    }
    for (final o in governed) {
      exempt[o] = m.reason;
    }
  }

  return (
    sites: [
      for (final s in sites)
        (
          text: s.text,
          where: s.where,
          reason: exempt[int.parse(s.where.split(':').last) - 1],
        ),
    ],
    orphans: orphans,
    interpolating: interpolating,
  );
}

/// **Every app-bar title in `lib/`, on the narrowest bar it can appear in**
/// (SYSTEM.md §13.3, A15, §21 row 79).
///
/// §5③ of the spec says « the gate's first red run **is** the list », and this
/// is that run — the corpus is read out of `lib/` rather than hand-copied, so
/// the 66th title cannot join by being forgotten.
///
/// **Why one budget for all of them.** Each title is pumped on a *pushed bar
/// with no actions* — 280dp at 360×2×, after A15 took Material's 56dp leading
/// box down to the 48 a `BackButton` actually occupies. The 16dp of
/// `titleSpacing` on each side stays: it is the gap that keeps a ROOT bar's
/// title aligned with the body it heads, and taking it bought 32dp the corpus
/// turned out not to need. That is the WIDEST bar any title gets once it is
/// pushed, so a title that reds here is too long on every bar in the app. The
/// converse does not hold: a title that passes here can still be starved by an
/// action, because an action's label is scaled by the FULL system scaler while
/// the title is clamped to 1.34× (`app_bar.dart:1092`) — measured in
/// `primitives_test.dart`, where a `TextButton` leaves « Avis » unable to fit.
/// Those bars are held by the matrix, which renders their real actions.
///
/// **The way out is a declaration, not a silent ellipsis** (§4.1): a
/// `// clip-ok: <why>` in the ten lines above the bar exempts that title, and
/// prints the reason in the run. Nothing in `lib/` declares one today — which
/// is why the orphan rule and the fixture below exist rather than an assertion
/// that the count is zero. A mechanism nobody has used yet is a mechanism
/// nobody has tested.
void main() {
  setUpAll(loadRealFonts);

  List<TitleSite> corpusSites() {
    final out = <TitleSite>[];
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            // The flag-hidden V2/V3 screens, excluded exactly as the §5 spacing
            // pin excludes them (`design_system_pin_test.dart:33`) — they
            // re-enter the day the flag flips, which is the day a user can read
            // them.
            .where((f) => !f.path.contains('/screens/provider/features/'))) {
      out.addAll(
        scanAppBarTitles(
          f.readAsLinesSync(),
          name: f.path.split('/').last,
        ).sites,
      );
    }
    return out;
  }

  List<String> corpusOrphans() {
    final out = <String>[];
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.contains('/screens/provider/features/'))) {
      out.addAll(
        scanAppBarTitles(
          f.readAsLinesSync(),
          name: f.path.split('/').last,
        ).orphans,
      );
    }
    return out;
  }

  final corpus = corpusSites();

  test(
    'the corpus is not empty — a run over nothing is green about nothing',
    () {
      expect(
        corpus.length,
        greaterThan(40),
        reason:
            'the title scan matched ${corpus.length} strings; either the shape '
            'of an AppBar construction changed or the regex rotted, and either '
            'way every measurement below is about a set nobody chose',
      );
    },
  );

  test('no app-bar title interpolates a datum', () {
    // **Without this, the way out of every measurement above is a `$`.** The
    // literal regex refuses interpolation by construction, so an interpolating
    // title is not merely unmeasured — it is unmeasur*able*, and it is the one
    // shape guaranteed to have no width it can promise: the journal's
    // « {Salon} — votre planning » fit for « Salon Excellence » and not for
    // « Institut de Beauté Cocody Riviera ».
    //
    // Both offenders were real and both are fixed in the same commit that
    // wrote this: the journal's, and `availability_screen.dart`'s
    // « Horaires - {jour} » on a bar that also carries an action.
    final out = <String>[];
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.contains('/screens/provider/features/'))) {
      out.addAll(
        scanAppBarTitles(
          f.readAsLinesSync(),
          name: f.path.split('/').last,
        ).interpolating,
      );
    }
    expect(
      out,
      isEmpty,
      reason:
          'an AppBar title interpolates data and therefore promises a width it '
          'cannot keep. Move the datum into the body, where it can wrap.',
    );
  });

  test('every « clip-ok » governs a title — an orphan declares nothing', () {
    // The bidirectional half of the marker. Without it a `clip-ok:` that drifts
    // away from its bar (a refactor moves the `AppBar(` eleven lines down, or
    // deletes it) stays in the file looking like a live exception, and the
    // title it was written for silently re-enters the gate — or worse, a NEW
    // title lands under a stale marker and inherits an exemption nobody
    // granted it.
    expect(
      corpusOrphans(),
      isEmpty,
      reason:
          'a « // clip-ok: » in lib/ governs no app-bar title, or carries no '
          'reason. Move it to within ten lines above the bar it is about, '
          'give it a reason, or delete it.',
    );
  });

  group('the marker, run through the shipping scan', () {
    // Four cases, all through `scanAppBarTitles` itself. A fixture that
    // re-spelt the regex would agree with a broken pin.
    ({List<TitleSite> sites, List<String> orphans, List<String> interpolating})
    scan(String src) => scanAppBarTitles(src.split('\n'), name: 'fixture.dart');

    test('an interpolating title is reported, and contributes no literal', () {
      // The pair for the `lib/` run above, which is green and would stay green
      // if the detector stopped detecting.
      final r = scan(r"""
appBar: AppBar(title: Text('Horaires - ${widget.dayName}')),
""");
      expect(r.interpolating, hasLength(1));
      expect(
        r.sites,
        isEmpty,
        reason:
            r'the literal regex refuses $-bearing strings, which is exactly '
            'why '
            'the report above has to exist',
      );
    });

    test(
      'present, with a reason — the title is exempt and the reason kept',
      () {
        final r = scan('''
// clip-ok: a legal reference, and « Art. 12 » is not a phrase we own
appBar: AppBar(title: Text('Conditions générales d’utilisation')),
''');
        expect(r.sites.single.text, 'Conditions générales d’utilisation');
        expect(r.sites.single.reason, contains('legal reference'));
        expect(r.orphans, isEmpty);
      },
    );

    test('absent — the same title is NOT exempt', () {
      // The pair. Without it « always exempt » would pass the case above.
      final r = scan('''
appBar: AppBar(title: Text('Conditions générales d’utilisation')),
''');
      expect(r.sites.single.reason, isNull);
      expect(r.orphans, isEmpty);
    });

    test('twelve lines away — out of the window, so it governs nothing', () {
      final r = scan('''
// clip-ok: too far to be about the bar below
${List.filled(12, 'final x = 1;').join('\n')}
appBar: AppBar(title: Text('Conditions générales d’utilisation')),
''');
      expect(
        r.sites.single.reason,
        isNull,
        reason: 'a distant marker must not reach the title',
      );
      expect(r.orphans, hasLength(1));
      expect(r.orphans.single, contains('no app-bar title'));
    });

    test('bare — a marker with no reason exempts nothing and is an orphan', () {
      final r = scan('''
// clip-ok:
appBar: AppBar(title: Text('Conditions générales d’utilisation')),
''');
      expect(r.sites.single.reason, isNull);
      expect(r.orphans, hasLength(1));
      expect(r.orphans.single, contains('no reason'));
    });
  });

  for (final t in corpus.where((t) => t.reason == null)) {
    testWidgets('« ${t.text} » (${t.where}) fits a pushed bar at 360 × 2×', (
      tester,
    ) async {
      await pumpPushedAtWidth(
        tester,
        width: 360,
        scale: 2,
        rounds: 0,
        subject: Scaffold(appBar: AppBar(title: Text(t.text))),
      );
      expectAppBarTitleWhole(tester, at: '${t.where} — 360dp × 2×');
    });
  }

  for (final t in corpus.where((t) => t.reason != null)) {
    test('« ${t.text} » (${t.where}) is DECLARED: ${t.reason}', () {
      // Not skipped silently — a declared exception still prints, every run,
      // with its reason attached. §4.1's whole point is that the exception is
      // readable, and a `skip:` is the one thing nobody reads.
      expect(t.reason, isNotEmpty);
    });
  }
}
