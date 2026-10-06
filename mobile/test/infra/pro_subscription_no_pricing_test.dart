import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Pro app never sells — App Store 3.1.1 and 3.1.3(f), on BOTH stores.
///
/// ## Why this file exists
///
/// **First, the prices (3.1.1).** « Mon abonnement » rendered a struck-through
/// anchor (« 70 000 FCFA ») and « /mois » on each tier card, beside a « Nous
/// contacter » button that opened WhatsApp with « je souhaite activer mon
/// offre ». A subscription that unlocks app functionality is digital content in
/// Apple's reading; advertising its price and routing the purchase off-platform
/// is the shape that gets an app rejected.
///
/// **Then, the choice itself (3.1.3(f)).** The owner decided on 2026-10-05 that
/// MyWeli Pro ships as a « free stand-alone companion app to a paid web based
/// tool »: no purchasing, and no call to action to purchase outside the app.
/// So the offer picker left the app — on iOS AND Android, because Google Play's
/// payments policy has the same steering rule and one behaviour is one thing to
/// keep honest. This file used to pin « Choisir » as something that MUST stay,
/// because choosing was the only way a salon's trial started and a salon
/// without an offer could not go live. That is no longer true: the server
/// starts the trial at the salon's first successful publish, so removing the
/// picker breaks nothing, and the pin now says the opposite.
/// Design: docs/design/pro-companion-path.md §2.1 (the rule), §11 (decision).
///
/// ## What it reads
///
/// Every Dart file under `lib/`. It used to read only the provider screens
/// and widgets, `core/utils` and the services — and so never `core/config`,
/// where most of the removed copy actually lived (« Tarif personnalisé », the
/// trial length, the entitlement lists, the ROI line, all constants a screen
/// rendered by NAME). A phrase that came back as a constant there, or in a
/// provider or a model, would have passed. The whole of `lib/` holds none of
/// the phrases, consumer and admin code included, so the wide scan costs
/// nothing and leaves no corner to hide in.
///
/// Comments are stripped first: two guards in this repo have matched a string
/// that existed only in a comment, one of them the comment describing the very
/// defect it was meant to catch — and the comments here legitimately quote the
/// removed copy to explain why it went. Then adjacent literals are joined
/// (`'Choisissez votre ' 'offre'` is one phrase on screen, so it is one phrase
/// to the pin), and the apostrophe is compared in one spelling.
///
/// A source pin rather than a widget test, for the reason the other infra
/// tests give: the strings must not be in the binary at all, and a widget
/// test only proves one route through one state. The widget tests prove the
/// states; this proves the corners no state reached.
void main() {
  /// file path → its code with `//` line comments and `/* */` blocks removed.
  Map<String, String> readCode() => {
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        f.path: _stripComments(f.readAsStringSync()),
  };

  group('nothing in the Pro surfaces chooses, promotes or points to an '
      'offer', () {
    // Each phrase is copy that shipped and was removed by the companion path
    // (or by the 3.1.1 price removal before it).
    const removed = [
      'Choisir mon offre',
      'Changer d’offre',
      'Choisissez votre offre',
      'mois offerts',
      'Tarif personnalisé',
      'Réactivez votre offre',
      'Activez votre offre',
      'Passez à l’offre',
      'activer votre offre',
      'se gère depuis votre espace',
    ];

    test('the removed phrases are gone from every scanned file', () {
      final code = readCode();
      expect(code, isNotEmpty, reason: 'the scan found no Dart file');
      // The directory the old scan skipped — proof the wide scan reaches it.
      expect(
        code.keys.where((p) => p.contains('core/config/')),
        isNotEmpty,
        reason: 'the scan no longer reads lib/core/config',
      );
      final hits = <String>[
        for (final e in code.entries)
          for (final phrase in removed)
            if (_asCopy(e.value).contains(_asCopy(phrase)))
              '${e.key}: « $phrase »',
      ];
      expect(
        hits,
        isEmpty,
        reason:
            'the Pro app may show the current offer, never a way to choose, '
            'switch, activate or obtain one (App Store 3.1.3(f), both '
            'stores): $hits',
      );
    });

    test('no price is rendered on « Mon abonnement »', () {
      final code = readCode().entries
          .firstWhere(
            (e) => e.key.endsWith('pro_subscription_screen.dart'),
            orElse: () => throw StateError('screen not found'),
          )
          .value;
      for (final needle in [
        'FCFA',
        'formatCurrency',
        '/mois',
        'Sur devis',
        'AnchorMonthlyFcfa',
        'openWhatsApp',
        'Nous contacter',
        'régler',
      ]) {
        expect(
          code.contains(needle),
          isFalse,
          reason: 'the subscription screen renders "$needle"',
        );
      }
    });

    test('the app never writes an offer — the PUT is the web\'s alone', () {
      // The trial starts server-side at the first publish; choosing or
      // switching happens on the web. A write path back in the app is the
      // picker coming back, whatever its copy says.
      final code = readCode();
      final hits = [
        for (final e in code.entries)
          if (e.value.contains('chooseOffer')) e.key,
      ];
      expect(hits, isEmpty, reason: '$hits');
      final api = code.entries
          .firstWhere(
            (e) => e.key.endsWith('api_pro_subscription_service.dart'),
            orElse: () => throw StateError('subscription service not found'),
          )
          .value;
      expect(api, isNot(contains('.put(')));
    });

    test('the store-policy branch is gone, not just unused', () {
      // The fix is no plan choice on EITHER platform, so a platform switch
      // has nothing left to decide — its return would mean one store sells.
      expect(File('lib/core/config/store_policy.dart').existsSync(), isFalse);
      final hits = [
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              f.readAsStringSync().contains('hidesExternalPurchaseCopy'))
            f.path,
      ];
      expect(hits, isEmpty, reason: '$hits');
    });
  });

  group('the comment stripper', () {
    // Inputs are built from lines so the tricky quotes stay readable.
    const q = "'";
    const q3 = '"""';

    test('drops every kind of comment', () {
      final source = [
        '// Choisir mon offre (a line comment)',
        '/// « 3 mois offerts » (a doc comment)',
        '/* Tarif personnalisé',
        '   /* nested */ (a block) */',
        'final url = ${q}https://myweli.com$q; // trailing: Changer d’offre',
        'final n = $q\${a > 1 ? ${q}s$q : $q$q} jours$q; // Passez à l’offre',
        'final raw = r${q}C:\\$q; // Réactivez votre offre',
        'final mime = ${q}image/*$q; final label = ${q}Vos données$q;',
      ].join('\n');
      final code = _stripComments(source);
      for (final kept in [
        '${q}https://myweli.com$q',
        ' jours$q;',
        'final raw = r${q}C:\\$q;',
        'final label = ${q}Vos données$q;',
      ]) {
        expect(code, contains(kept), reason: 'code was stripped: $kept');
      }
      for (final gone in [
        'Choisir mon offre',
        'mois offerts',
        'Tarif personnalisé',
        'Changer d’offre',
        'Passez à l’offre',
        'Réactivez votre offre',
      ]) {
        expect(code, isNot(contains(gone)), reason: 'comment kept: $gone');
      }
    });

    test('refuses to guess when it loses track (an unclosed string)', () {
      expect(
        () => _stripComments('final s = ${q}Choisir mon offre;'),
        throwsStateError,
      );
    });

    test('keeps a phrase that lives in code, so the pin can fail', () {
      for (final line in [
        'final s = ${q}Choisir mon offre$q;',
        'final s = ${q}https://x$q ${q}Choisir mon offre$q;',
        'final s = ${q}image/*$q; final t = ${q}Choisir mon offre$q; // */',
        'final s = $q\${n > 1 ? ${q}s$q : $q$q} Choisir mon offre$q;',
        'final s = $q3\n// Choisir mon offre\n$q3;',
      ]) {
        expect(
          _stripComments(line),
          contains('Choisir mon offre'),
          reason: line,
        );
      }
    });
  });

  group('the copy normaliser', () {
    const q = "'";
    const dq = '"';

    test('a phrase split across literals is still the phrase', () {
      for (final source in [
        // Adjacent literals, the way `dart format` wraps a long sentence.
        'final s = ${q}Choisissez votre $q\n    ${q}offre$q;',
        // Mixed quotes, a comment in the gap (stripped first), raw strings.
        'final s = ${q}Choisissez $q // wrap\n ${dq}votre offre$dq;',
        'final s = r${q}Choisissez votre $q r${q}offre$q;',
        // `+` between literals.
        'final s = ${q}Choisissez votre $q + ${q}offre$q;',
        // A space that is its own literal.
        'final s = ${q}Choisissez$q $q $q ${q}votre offre$q;',
      ]) {
        expect(
          _asCopy(_stripComments(source)),
          contains(_asCopy('Choisissez votre offre')),
          reason: source,
        );
      }
    });

    test('the apostrophe matches in every spelling', () {
      for (final spelling in [
        '${q}Changer d’offre$q', // the house typographic apostrophe
        '${dq}Changer d${q}offre$dq', // a straight one
        '${q}Changer d\\${q}offre$q', // an escaped one
      ]) {
        expect(
          _asCopy(_stripComments('final s = $spelling;')),
          contains(_asCopy('Changer d’offre')),
          reason: spelling,
        );
      }
    });

    test('two separate literals are not joined into a phrase', () {
      // A comma, a call, an operator: separate strings on screen.
      for (final source in [
        'f(${q}Choisir$q, ${q}mon offre$q);',
        'a ? ${q}Choisir$q : ${q}mon offre$q;',
      ]) {
        expect(
          _asCopy(_stripComments(source)),
          isNot(contains('Choisirmon offre')),
          reason: source,
        );
        expect(
          _asCopy(_stripComments(source)),
          isNot(contains('Choisir mon offre')),
          reason: source,
        );
      }
    });
  });
}

/// The comparable form of comment-free code (or of a phrase): adjacent string
/// literals joined, and the apostrophe in one spelling.
///
/// Joining: the gap between two literals that Dart concatenates is whitespace
/// or a `+` once comments are gone, so « quote, gap, quote » goes (with a
/// raw string's `r`). The regex
/// cannot tell a closing quote from an opening one, and it does not need to:
/// it only ever REMOVES quote characters and the blanks between them, and no
/// pinned phrase contains a straight quote — so it can merge text that was
/// split, never hide text that was whole. Then `’`, `\'` and `'` compare
/// equal (after the join, so the new straight quotes are not taken for
/// literal boundaries).
String _asCopy(String code) => code
    .replaceAll(RegExp(r'''['"](?:\s+|\s*\+\s*)r?['"]'''), '')
    .replaceAll(r"\'", "'")
    .replaceAll('’', "'");

/// Removes `//` line comments (including `///`) and `/* … */` blocks
/// (nested, as Dart allows), outside string literals. A tiny scanner rather
/// than a regex, because a regex cannot tell code from string: `https://` in a
/// string is not a comment, `'image/*'` does not open one, and an
/// interpolation holds code — quotes included — inside a string. Getting any
/// of those wrong would strip CODE, the one direction a pin must never err in:
/// it would pass on a phrase it never saw.
String _stripComments(String source) {
  final out = StringBuffer();
  // The open contexts, innermost last. The bottom one is plain code and is
  // never popped; a string pushes, a `${` inside a string pushes code again.
  final stack = <_Ctx>[_Ctx.code(interpolation: false)];
  final identChar = RegExp(r'[A-Za-z0-9_$]');
  var i = 0;
  bool at(String token) => source.startsWith(token, i);

  while (i < source.length) {
    final ctx = stack.last;
    final quote = ctx.quote;
    if (quote != null) {
      // Inside a string literal.
      if (at(quote)) {
        out.write(quote);
        i += quote.length;
        stack.removeLast();
      } else if (!ctx.raw && at(r'\') && i + 1 < source.length) {
        out.write(source.substring(i, i + 2));
        i += 2;
      } else if (!ctx.raw && at(r'${')) {
        out.write(r'${');
        i += 2;
        stack.add(_Ctx.code(interpolation: true));
      } else {
        out.write(source[i]);
        i++;
      }
      continue;
    }

    // Code.
    if (at('//')) {
      final end = source.indexOf('\n', i);
      if (end == -1) break;
      i = end; // keep the newline
      continue;
    }
    if (at('/*')) {
      var depth = 0;
      while (i < source.length) {
        if (at('/*')) {
          depth++;
          i += 2;
        } else if (at('*/')) {
          depth--;
          i += 2;
          if (depth == 0) break;
        } else {
          i++;
        }
      }
      continue;
    }
    final raw =
        at('r') &&
        (i == 0 || !identChar.hasMatch(source[i - 1])) &&
        i + 1 < source.length &&
        (source[i + 1] == "'" || source[i + 1] == '"');
    final start = i + (raw ? 1 : 0);
    String? opening;
    for (final candidate in const ["'''", '"""', "'", '"']) {
      if (source.startsWith(candidate, start)) {
        opening = candidate;
        break;
      }
    }
    if (opening != null) {
      out.write(source.substring(i, start + opening.length));
      i = start + opening.length;
      stack.add(_Ctx.string(opening, raw: raw));
      continue;
    }
    if (ctx.interpolation && at('{')) {
      ctx.depth++;
    } else if (ctx.interpolation && at('}')) {
      if (ctx.depth == 0) {
        stack.removeLast(); // back into the string
      } else {
        ctx.depth--;
      }
    }
    out.write(source[i]);
    i++;
  }
  // Ending inside a string means the scanner lost track somewhere — and a
  // lost scanner could have stripped code. Fail loudly instead.
  if (stack.length != 1) {
    throw StateError(
      'comment stripper ended inside '
      '${stack.last.quote ?? 'an interpolation'} — fix the scanner',
    );
  }
  return out.toString();
}

/// One open context of [_stripComments]: code (the file, or an
/// interpolation's expression) or a string literal.
class _Ctx {
  _Ctx.code({required this.interpolation}) : quote = null, raw = false;
  _Ctx.string(String this.quote, {required this.raw}) : interpolation = false;

  final String? quote;
  final bool raw;
  final bool interpolation;
  int depth = 0;
}
