import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/team_error_messages.dart';

/// The App Review notes — the text the owner pastes into App Store Connect
/// (docs/design/app-store-forms.md §8).
///
/// ## Why a test reads a document
///
/// The notes live in a Markdown file, and three things about them are facts
/// that nothing checked:
///
/// 1. **Their weight.** App Store Connect refuses notes over 4,000 bytes.
///    The file states the weight above the block, and that number was
///    recounted by hand each time the block changed — except once: on
///    2026-10-11 « Salon Démo MyWeli » became « Maison Nala » in the block,
///    and the paragraph kept saying 3,483 bytes for a block that weighed
///    3,476. Found on 2026-10-13 by recounting.
/// 2. **The sentence they quote.** The notes tell the reviewer that three
///    actions on the shared demo account answer « Compte de démonstration —
///    cette action est désactivée. ». That sentence is a constant in this
///    app; the notes are a copy of it in another language's paragraph.
/// 3. **That a paste-ready block exists at all**, in the one place the
///    owner is told to copy from.
///
/// What this file cannot see: whether the notes are TRUE of the server the
/// reviewer reaches. The demo account's deletion lock is server-side, and
/// the amended notes are valid only once production serves it — that is a
/// rollout step (docs/design/demo-account-deletion-lock.md §10), not
/// something a test in this repository can observe.
void main() {
  final doc = File('../docs/design/app-store-forms.md').readAsStringSync();

  const anchor = '**Notes** (coller tel quel';

  /// The paragraph that introduces the block, on one line.
  String intro() {
    final start = doc.indexOf(anchor);
    final end = doc.indexOf('\n\n', start);
    return doc.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
  }

  /// The first fenced `text` block after the anchor, WITHOUT its final
  /// newline — exactly what `printf '%s' "$(cat notes.txt)"` weighs.
  String notes() {
    final start = doc.indexOf(anchor);
    const fence = '```text\n';
    final open = doc.indexOf(fence, start) + fence.length;
    final close = doc.indexOf('\n```\n', open);
    return doc.substring(open, close);
  }

  int number(String digitsWithSpaces) =>
      int.parse(digitsWithSpaces.replaceAll(RegExp(r'\D'), ''));

  test('there is exactly one paste-ready block, and it is the notes', () {
    expect(anchor.allMatches(doc), hasLength(1));
    expect(notes(), startsWith('MyWeli Pro is the business app'));
    expect(notes(), contains('HOW TO SIGN IN (demo account)'));
    expect(notes(), contains('ACCOUNT DELETION'));
    expect(notes(), isNot(contains('```')));
  });

  test('the block fits App Store Connect — under 4,000 bytes', () {
    expect(utf8.encode(notes()).length, lessThan(4000));
  });

  test('the weight stated above the block is the real one', () {
    final stated = RegExp(
      r'Poids : \*\*([\d\s]+) octets\*\* \(([\d\s]+) caractères\)',
    ).firstMatch(intro());
    expect(stated, isNotNull, reason: 'the « Poids : … » sentence moved');
    expect(
      number(stated!.group(1)!),
      utf8.encode(notes()).length,
      reason: 'the block changed and its byte count was not updated',
    );
    expect(
      number(stated.group(2)!),
      notes().runes.length,
      reason: 'the block changed and its character count was not updated',
    );
  });

  test('wherever the notes quote the demo refusal, it is the sentence the '
      'app shows — word for word', () {
    // Not a count of mentions: the notes may be reworded. What may not
    // happen is a quote that the app does not say.
    final quoted = RegExp(
      r'« (Compte de démonstration[^»]*?) »',
    ).allMatches(notes()).map((m) => m.group(1)).toList();
    expect(quoted, isNotEmpty, reason: 'the notes no longer quote it');
    expect(quoted, everyElement(demoAccountLockedMessage));
  });
}
