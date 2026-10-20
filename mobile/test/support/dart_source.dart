/// Reading Dart SOURCE as the copy it renders — for the source pins in
/// `test/infra/` (`pro_subscription_no_pricing_test.dart`,
/// `promise_honesty_pin_test.dart`), which must see a phrase however `dart
/// format` wrapped it and never see one that lives only in a comment.
///
/// Moved here verbatim from `pro_subscription_no_pricing_test.dart` when the
/// second pin needed it (docs/design/promise-honesty-sweep.md §5); that
/// file's « comment stripper » and « copy normaliser » groups are still the
/// self-tests of these two functions.
library;

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
String asCopy(String code) => code
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
String stripDartComments(String source) {
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

/// One open context of [stripDartComments]: code (the file, or an
/// interpolation's expression) or a string literal.
class _Ctx {
  _Ctx.code({required this.interpolation}) : quote = null, raw = false;
  _Ctx.string(String this.quote, {required this.raw}) : interpolation = false;

  final String? quote;
  final bool raw;
  final bool interpolation;
  int depth = 0;
}
