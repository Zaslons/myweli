import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/design/play-store-forms.md — what the owner (or Claude, in the browser
/// pane) types into the Play Console for MyWeli Pro (BACKLOG B0.10).
///
/// Three facts about that page that nothing checked:
///
/// 1. **The listing fits Play's limits** — name 30, short description 80,
///    full description 4,000 characters (Play help, « Add product details »).
///    And the full description is the App Store's, word for word: the page
///    says so, and two stores telling two stories is how a claim drifts.
///    **And the sign-in instructions fit their field.** No help page of
///    Google's states a limit; the console does — « 0/500 » under « Toute
///    autre information requise pour accéder à votre appli », 60 for the
///    set's name (read in the form on 2026-10-28). The first English draft
///    was over 1,000 characters and would have been cut or refused.
/// 2. **The sign-in steps quote labels the Pro app shows.** The 2026-09-24
///    audit found « Se connecter par e-mail » in this text, a label that
///    never existed. Every « … » in the numbered steps must be a string
///    literal of `pro_login_screen.dart`, comments stripped.
/// 3. **Every data type on the App Store label has its Play row.** The
///    2026-10-28 audit found « User ID » declared to Apple and missing from
///    Play. The iOS table (app-store-forms §7.1, §7.2) is read, each type
///    mapped to its Play name, and the Play table (§4) must carry it. A new
///    iOS type with no mapping fails here rather than being skipped.
void main() {
  final play = File('../docs/design/play-store-forms.md').readAsStringSync();
  final ios = File('../docs/design/app-store-forms.md').readAsStringSync();
  final login = File(
    'lib/screens/provider/auth/pro_login_screen.dart',
  ).readAsStringSync();

  /// Section [n] of a doc: from « ## n · » to the next « ## ».
  String section(String doc, String heading) {
    final start = doc.indexOf(heading);
    expect(start, isNonNegative, reason: 'no « $heading »');
    final next = doc.indexOf('\n## ', start + heading.length);
    return doc.substring(start, next == -1 ? doc.length : next);
  }

  /// The code span on the line that starts with [label] (or the next line).
  String codeSpanAfter(String text, String label) {
    final at = text.indexOf(label);
    expect(at, isNonNegative, reason: 'no « $label »');
    final m = RegExp('`([^`]+)`').firstMatch(text.substring(at));
    expect(m, isNotNull, reason: 'no `…` after « $label »');
    return m!.group(1)!;
  }

  /// The first fenced `text` block after [anchor], without its final newline.
  String fencedAfter(String doc, String anchor) {
    final start = doc.indexOf(anchor);
    expect(start, isNonNegative, reason: 'no « $anchor »');
    const fence = '```text\n';
    final open = doc.indexOf(fence, start) + fence.length;
    final close = doc.indexOf('\n```', open);
    return doc.substring(open, close);
  }

  group('§1 — the Pro listing fits Play', () {
    String listing() => section(play, '## 1 · ');

    test('name ≤ 30, short description ≤ 80, full description ≤ 4,000 '
        'characters', () {
      final name = codeSpanAfter(listing(), "**Nom de l'app**");
      final short = codeSpanAfter(listing(), '**Description courte**');
      final full = fencedAfter(
        listing(),
        '**Description complète** (coller tel quel)',
      );
      // Anti-vacuity: the three were found, and are the texts, not stubs.
      expect(name, startsWith('MyWeli Pro'));
      expect(short.length, greaterThan(20));
      expect(full.length, greaterThan(500));

      // Dart's String.length counts UTF-16 units; every character here is
      // in the BMP, so it is the character count Play shows.
      expect(name.runes.length, lessThanOrEqualTo(30), reason: name);
      expect(short.runes.length, lessThanOrEqualTo(80), reason: short);
      expect(full.runes.length, lessThanOrEqualTo(4000));
    });

    test('the full description is the App Store one, word for word', () {
      final full = fencedAfter(
        listing(),
        '**Description complète** (coller tel quel)',
      );
      final appStore = fencedAfter(section(ios, '## 4 · '), '**Description**');
      expect(full, appStore);
    });

    test('no Markdown in what is pasted — Play shows it literally', () {
      final full = fencedAfter(
        listing(),
        '**Description complète** (coller tel quel)',
      );
      expect(full, isNot(contains('**')));
      expect(full, isNot(contains('> ')));
    });
  });

  group('§2 — the sign-in steps quote the Pro app', () {
    /// The blockquote under the paste-ready anchor, line by line.
    List<String> instructions() {
      const anchor = '**Instructions supplémentaires** (coller tel quel';
      final lines = play.substring(play.indexOf(anchor)).split('\n').skip(1);
      final quoted = <String>[];
      for (final line in lines) {
        if (line.startsWith('>')) {
          quoted.add(line.substring(1).trim());
        } else if (quoted.isNotEmpty) {
          break;
        }
      }
      return quoted;
    }

    /// The Pro sign-in screen's string literals, comments removed — a label
    /// that survives only in a comment is not on screen.
    Set<String> literals() {
      final code = login
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'(^|\s)//.*$'), ''))
          .join('\n');
      return {
        for (final m in RegExp(r"'([^'\\]*)'").allMatches(code)) m.group(1)!,
      };
    }

    test('every « label » in the numbered steps is a literal of '
        'pro_login_screen.dart', () {
      final steps = instructions().where((l) => RegExp(r'^\d+\. ').hasMatch(l));
      expect(steps, hasLength(3), reason: 'the three numbered steps');
      final labels = [
        for (final s in steps)
          for (final m in RegExp('« ([^»]+) »').allMatches(s)) m.group(1)!,
      ];
      // Anti-vacuity: Espace Pro, Votre e-mail, Continuer avec e-mail,
      // Code à 6 chiffres, Se connecter.
      expect(labels, hasLength(5), reason: labels.join(' | '));
      final onScreen = literals();
      for (final label in labels) {
        expect(
          onScreen,
          contains(label),
          reason:
              '« $label » is quoted to Google and is not on the Pro '
              'sign-in screen',
        );
      }
    });

    test('the instructions fit the console: 500 characters, newlines '
        'included; the set\'s name 60', () {
      final pasted = instructions().join('\n');
      expect(pasted.length, greaterThan(200), reason: 'anti-vacuity');
      expect(
        pasted.runes.length,
        lessThanOrEqualTo(500),
        reason: '${pasted.runes.length} characters for a 500-character field',
      );
      final name = codeSpanAfter(section(play, '## 2 · '), '**Nom** de');
      expect(name.runes.length, inInclusiveRange(1, 60), reason: name);
    });

    test('the username typed in the steps is the one in the form', () {
      final user = codeSpanAfter(
        section(play, '## 2 · '),
        "**Nom d'utilisateur**",
      );
      expect(user, 'revue@myweli.test');
      expect(instructions().join(' '), contains(user));
    });
  });

  group('§4 — every App Store data type has its Play row', () {
    /// Apple's type → Play's type, as named in the French Play Console.
    const toPlay = {
      'Name': 'Nom',
      'Email Address': 'Adresse e-mail',
      'Phone Number': 'Numéro de téléphone',
      'Physical Address': 'Adresse',
      'Precise Location': 'Position exacte',
      'Other Financial Info': 'Autres infos financières',
      'Photos or Videos': 'Photos',
      'Other User Content': 'Autre contenu généré par l’utilisateur',
      'User ID': 'ID utilisateur',
      'Device ID': 'Appareil ou autres ID',
      'Other Data Types': 'Autres infos',
      'Crash Data': 'Journaux de plantage',
      'Performance Data': 'Diagnostics',
    };

    /// The bold type in each row of the iOS label tables (§7.1, §7.2).
    List<String> iosTypes() {
      final label = section(ios, '## 7 · ');
      return [
        for (final m in RegExp(
          r'^\| [^|]+ \| \*\*([^*]+)\*\* \|',
          multiLine: true,
        ).allMatches(label))
          m.group(1)!,
      ];
    }

    /// The bold Play type in each row of the Pro table (§4).
    Set<String> playTypes() {
      final safety = section(play, '## 4 · ');
      return {
        for (final m in RegExp(
          r'^\| [^|]*→ \*\*([^*]+)\*\* \|',
          multiLine: true,
        ).allMatches(safety))
          m.group(1)!.replaceAll("'", '’'),
      };
    }

    test('the iOS label is read (13 types, 2026-10-28)', () {
      expect(iosTypes(), hasLength(13), reason: iosTypes().join(' | '));
    });

    test('each iOS type maps to a Play type the table declares', () {
      final declared = playTypes();
      expect(declared, isNotEmpty);
      for (final type in iosTypes()) {
        expect(
          toPlay.keys,
          contains(type),
          reason:
              'a new type on the App Store label, « $type », has no '
              'Play mapping here — add it, then the Play row',
        );
        expect(
          declared,
          contains(toPlay[type]),
          reason:
              '« $type » is declared to Apple; its Play counterpart '
              '« ${toPlay[type]} » is missing from play-store-forms §4',
        );
      }
    });
  });
}
