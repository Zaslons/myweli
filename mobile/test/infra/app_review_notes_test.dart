import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/team_error_messages.dart';

/// The review notes — the texts the owner pastes into App Store Connect
/// (docs/design/app-store-forms.md §8) and into the Play Console
/// (docs/design/play-store-forms.md §2).
///
/// ## Why a test reads two documents
///
/// The notes live in Markdown, and four things about them are facts that
/// nothing checked:
///
/// 1. **Their weight.** App Store Connect refuses notes over 4,000 bytes.
///    The file states the weight above each block, and that number was
///    recounted by hand each time a block changed — except once: on
///    2026-10-11 « Salon Démo MyWeli » became « Maison Nala » in the block,
///    and the paragraph kept saying 3,483 bytes for a block that weighed
///    3,476. Found on 2026-10-13 by recounting.
/// 2. **The sentence they quote.** The notes tell the reviewer that some
///    actions on the shared demo account answer « Compte de démonstration —
///    cette action est désactivée. ». That sentence is a constant in this
///    app; every copy of it in a store text is a copy that can drift.
/// 3. **That a paste-ready block exists**, in the one place the owner is
///    told to copy from.
/// 4. **WHICH block is paste-ready.** Since 2026-10-13 there are two: the
///    notes in force, and amended notes that say the demo account cannot be
///    deleted. The amended ones are true only once production serves the
///    lock (docs/design/demo-account-deletion-lock.md §10). Pasted before,
///    they invite a reviewer to try a deletion that production still
///    carries out — the loss the lock exists to prevent. Other sections of
///    the same file tell the owner to paste « les notes du §8 telles
///    quelles », so the block under « coller tel quel » has to be the one
///    that is true today.
///
/// ## The dated line
///
/// Whether production serves the lock cannot be observed from this
/// repository. What can be checked is **when someone last confirmed it**:
/// §8 carries one line, « Verrou de suppression du compte démo — vérifié en
/// production : pas encore. », that receives a date after the check of the
/// spec's §10.1. This test READS that line instead of pinning today's
/// world, so it is right before the deploy and after it:
///
/// - « pas encore » → the paste-ready texts must not promise the lock;
/// - dated → they may.
///
/// What this file cannot see, said plainly: whether the line is TRUE.
/// Dating it without having run the check turns this test green on a
/// production that still deletes the account. And it recognises the
/// promise by what the amended texts say today (the quoted sentence in the
/// ACCOUNT DELETION section, the word « delete » outside it, « suppression »
/// in the Play text) — a promise reworded past those is out of its sight.
/// Nor does it check the OTHER labels the notes quote (« Espace Pro »,
/// « Supprimer mon compte », …) against the app: those are reread by hand
/// when a label changes.
void main() {
  final doc = File('../docs/design/app-store-forms.md').readAsStringSync();
  final play = File('../docs/design/play-store-forms.md').readAsStringSync();

  /// The block the owner is told to copy.
  const pasteAnchor = '**Notes** (coller tel quel';

  /// The block that waits for the production check. Gone once it has been
  /// pasted and moved up — every test below holds without it.
  const amendedAnchor = '**Notes amendées** (';

  const playPasteAnchor = '**Instructions supplémentaires** (coller tel quel';
  const playAmendedAnchor = '**Instructions amendées** (';

  bool present(String source, String anchor) {
    final n = anchor.allMatches(source).length;
    expect(n, lessThanOrEqualTo(1), reason: 'two « $anchor » in one file');
    return n == 1;
  }

  /// The App Store anchors that exist, the paste-ready one first.
  List<String> blocks() => [
    pasteAnchor,
    if (present(doc, amendedAnchor)) amendedAnchor,
  ];

  /// The paragraph that introduces a block, on one line.
  String introOf(String anchor) {
    final start = doc.indexOf(anchor);
    final end = doc.indexOf('\n\n', start);
    return doc.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
  }

  /// The first fenced `text` block after [anchor], WITHOUT its final
  /// newline — exactly what `printf '%s' "$(cat notes.txt)"` weighs.
  String notesOf(String anchor) {
    final start = doc.indexOf(anchor);
    const fence = '```text\n';
    final open = doc.indexOf(fence, start) + fence.length;
    final close = doc.indexOf('\n```\n', open);
    return doc.substring(open, close);
  }

  /// The Play text after [anchor]: the first run of `>` lines, joined the
  /// way a paste joins them (the blockquote is wrapped at 80 columns, and a
  /// quoted sentence can straddle two lines).
  String playTextOf(String anchor) {
    final lines = play.substring(play.indexOf(anchor)).split('\n').skip(1);
    final quoted = <String>[];
    for (final line in lines) {
      if (line.startsWith('>')) {
        quoted.add(line.substring(1).trim());
      } else if (quoted.isNotEmpty) {
        break;
      }
    }
    return quoted.join(' ');
  }

  /// The ACCOUNT DELETION section of a notes block: its heading and the
  /// paragraph under it.
  ({int start, int end}) accountDeletionSpan(String block) {
    const heading = 'ACCOUNT DELETION\n';
    expect(heading.allMatches(block), hasLength(1));
    final start = block.indexOf(heading);
    final end = block.indexOf('\n\n', start);
    return (start: start, end: end == -1 ? block.length : end);
  }

  /// Lower case, French accents folded — « Démo », « démo » and « demo »
  /// are one word.
  String fold(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u');

  /// Every « … » of a text that quotes the demo refusal.
  ///
  /// Recognised by its WORDS, not by how it begins. The first version
  /// matched « Compte de démonstration… »: a quote reworded from its first
  /// words (« Compte démo — action désactivée. ») was then no longer a
  /// quote at all, and the test stayed green as long as another, intact
  /// quote survived in the same text. Found by mutating it.
  ///
  /// A quote that keeps neither « compte de démo… » nor « désactiv… » is
  /// out of sight: it no longer reads as the refusal to this test.
  List<String> demoQuotes(String text) => [
    for (final m in RegExp(r'«\s*([^»]*?)\s*»').allMatches(text))
      if (RegExp('compte de demo|desactiv').hasMatch(fold(m.group(1)!)))
        m.group(1)!,
  ];

  int number(String digitsWithSpaces) =>
      int.parse(digitsWithSpaces.replaceAll(RegExp(r'\D'), ''));

  /// The day the deletion lock was confirmed on production (spec §10.1), or
  /// null while it has not been. One line of §8 says it.
  DateTime? lockVerifiedOn() {
    final lines = RegExp(
      r'^\*\*Verrou de suppression du compte démo — vérifié en production : '
      r'(.+?)\.\*\*$',
      multiLine: true,
    ).allMatches(doc).toList();
    expect(
      lines,
      hasLength(1),
      reason: 'the dated line of §8 is missing, or there are two',
    );
    final value = lines.single.group(1)!;
    if (value == 'pas encore') return null;
    final dated = RegExp(r'^le (\d{4}-\d{2}-\d{2})$').firstMatch(value);
    expect(
      dated,
      isNotNull,
      reason: '« pas encore » or « le AAAA-MM-JJ », nothing else: « $value »',
    );
    final day = dated!.group(1)!;
    final date = DateTime.parse(day);
    expect(
      date.toIso8601String(),
      startsWith(day),
      reason: '$day is not a day of the calendar',
    );
    expect(
      date.isBefore(DateTime(2026, 10, 13)),
      isFalse,
      reason: 'the lock was built on 2026-10-13: it was not verified before',
    );
    return date;
  }

  test('there is exactly one paste-ready block, and it is the notes', () {
    expect(pasteAnchor.allMatches(doc), hasLength(1));
    for (final anchor in blocks()) {
      expect(notesOf(anchor), startsWith('MyWeli Pro is the business app'));
      expect(notesOf(anchor), contains('HOW TO SIGN IN (demo account)'));
      expect(notesOf(anchor), contains('ACCOUNT DELETION'));
      expect(notesOf(anchor), isNot(contains('```')));
    }
  });

  test('each block fits App Store Connect — under 4,000 bytes', () {
    for (final anchor in blocks()) {
      expect(utf8.encode(notesOf(anchor)).length, lessThan(4000));
    }
  });

  test('the weight stated above each block is the real one', () {
    for (final anchor in blocks()) {
      final stated = RegExp(
        r'Poids : \*\*([\d\s]+) octets\*\* \(([\d\s]+) caractères\)',
      ).firstMatch(introOf(anchor));
      expect(
        stated,
        isNotNull,
        reason: 'the « Poids : … » sentence moved ($anchor)',
      );
      expect(
        number(stated!.group(1)!),
        utf8.encode(notesOf(anchor)).length,
        reason: 'a block changed and its byte count was not updated ($anchor)',
      );
      expect(
        number(stated.group(2)!),
        notesOf(anchor).runes.length,
        reason:
            'a block changed and its character count was not updated '
            '($anchor)',
      );
    }
  });

  test('wherever the store texts quote the demo refusal, it is the sentence '
      'the app shows — word for word', () {
    // Not a count of mentions: the texts may be reworded. What may not
    // happen is a quote that the app does not say.
    final texts = <String, String>{
      for (final anchor in blocks()) 'App Store $anchor': notesOf(anchor),
      'Play $playPasteAnchor': playTextOf(playPasteAnchor),
      if (present(play, playAmendedAnchor))
        'Play $playAmendedAnchor': playTextOf(playAmendedAnchor),
    };
    for (final text in texts.entries) {
      final quoted = demoQuotes(text.value);
      expect(quoted, isNotEmpty, reason: '${text.key} no longer quotes it');
      expect(quoted, everyElement(demoAccountLockedMessage), reason: text.key);
    }
  });

  test('the line that says whether production serves the deletion lock is '
      'there, once, and readable', () {
    // « pas encore », or a real day on or after 2026-10-13.
    lockVerifiedOn();
  });

  test('App Store — the paste-ready notes promise the deletion lock only '
      'once its production check is dated', () {
    if (lockVerifiedOn() != null) return; // dated: either block may go in.

    const why =
        'the notes under « coller tel quel » tell the reviewer the demo '
        'account cannot be deleted, and §8 says production has not been '
        'checked. Until `api.myweli.com` answers 403 demo_account_locked '
        '(docs/design/demo-account-deletion-lock.md §10.1), a reviewer who '
        'tries it deletes the account. Date the line of §8 after the check '
        '— not before.';
    final block = notesOf(pasteAnchor);
    final span = accountDeletionSpan(block);
    final section = block.substring(span.start, span.end);
    final rest = block.substring(0, span.start) + block.substring(span.end);

    expect(section, isNot(contains(demoAccountLockedMessage)), reason: why);
    expect(
      section,
      contains('Please do not delete the shared demo account'),
      reason:
          'on a server without the lock, this plea is the only thing '
          'between a reviewer and the demo account',
    );
    // The amended notes also say it in the « … actions are deliberately
    // disabled » sentence. Outside its own section, the notes in force do
    // not speak of deletion at all.
    expect(
      rest,
      isNot(contains(RegExp('delet', caseSensitive: false))),
      reason: why,
    );
  });

  test('App Store — the amended notes are the ones that promise the lock, '
      'and differ from the notes in force in two passages only', () {
    if (!present(doc, amendedAnchor)) return; // pasted, moved up, removed.

    final inForce = notesOf(pasteAnchor).split('\n');
    final amended = notesOf(amendedAnchor).split('\n');
    final span = accountDeletionSpan(notesOf(amendedAnchor));
    expect(
      notesOf(amendedAnchor).substring(span.start, span.end),
      contains(demoAccountLockedMessage),
      reason: 'the block labelled « amendées » does not promise the lock',
    );
    if (lockVerifiedOn() != null) return; // the swap may be under way.

    // « Amend minimally, keep every other word » — as a mechanism: a label
    // corrected in one block and forgotten in the other is a block that
    // will be pasted stale.
    expect(amended, hasLength(inForce.length));
    final differing = [
      for (var i = 0; i < inForce.length; i++)
        if (inForce[i] != amended[i]) amended[i],
    ];
    expect(
      differing,
      hasLength(2),
      reason: 'the two blocks drifted apart:\n${differing.join('\n')}',
    );
    expect(differing.first, contains('deliberately disabled'));
    expect(differing.last, startsWith('Profil > « Supprimer mon compte »'));
  });

  test('Play — the paste-ready text speaks of deletion only once the '
      'production check is dated; the amended text is the one that does', () {
    expect(playPasteAnchor.allMatches(play), hasLength(1));
    // French (« suppression ») or English (« deleting ») — the Play text is in
    // English since 2026-10-28, as Google asks of sign-in instructions.
    final deletion = RegExp('suppr|delet', caseSensitive: false);
    if (present(play, playAmendedAnchor)) {
      expect(playTextOf(playAmendedAnchor), contains('suppression du compte'));
    }
    if (lockVerifiedOn() != null) return;
    expect(
      playTextOf(playPasteAnchor),
      isNot(contains(deletion)),
      reason:
          'the Play text under « coller tel quel » lists account deletion '
          'among the disabled actions, and app-store-forms.md §8 says '
          'production has not been checked.',
    );
  });
}
