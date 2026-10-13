import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// One string a layout is about to draw, with the style it will draw it in.
typedef FitText = ({String text, TextStyle style});

/// Measures text the way [Text] will draw it, so a layout can take the widest
/// shape in which every value stays whole (SYSTEM.md §13.3,
/// docs/design/amounts-that-fit.md).
///
/// **Why this exists.** Three layouts chose their shape from a text-SIZE
/// constant (« 2 × 2 above 1.1× »). A constant cannot know the width of the
/// phone or the amount on screen: « 180 000 » needs 64.7dp of a 60dp tile at
/// 1.1×, and « 1 250 000 » does not fit that tile at the default size. Whether
/// a token fits is a question about widths, so it is asked of the widths.
///
/// **Built like `Text.build`, line for line** — the `DefaultTextStyle` merge,
/// OS bold text, the letter- and word-spacing overrides, the ambient scaler,
/// locale and direction. The app's styles name no font family (the theme
/// supplies it), so a bare style would measure another face than the one
/// drawn; that is the mistake this class is here to prevent, not an
/// optimisation to remove.
///
/// Read it from a `LayoutBuilder`'s builder context, so the shape is decided
/// again when the width, the text size or the data changes.
class TextFit {
  TextFit.of(BuildContext context)
    : _defaultStyle = DefaultTextStyle.of(context).style,
      _boldText = MediaQuery.boldTextOf(context),
      _letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context),
      _wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context),
      _textScaler = MediaQuery.textScalerOf(context),
      _textDirection = Directionality.of(context),
      _locale = Localizations.maybeLocaleOf(context);

  final TextStyle _defaultStyle;
  final bool _boldText;
  final double? _letterSpacing;
  final double? _wordSpacing;
  final TextScaler _textScaler;
  final TextDirection _textDirection;
  final Locale? _locale;

  /// Kept between a token and the edge of its box. Half a logical pixel:
  /// below anything a reader can see, above the rounding between this painter
  /// and the paragraph that draws the same text a frame later. On the edge the
  /// narrower shape wins — a number that is whole beats a wider row.
  static const double slack = 0.5;

  /// Where the engine may break a line: the breaking white space only.
  ///
  /// Not `\s` — Dart's `\s` also matches U+00A0, U+2007, U+202F and U+FEFF,
  /// the characters whose job is to forbid a break. French numbers are
  /// grouped with U+202F.
  static final RegExp _breakingSpace = RegExp(
    '[\\u0009-\\u000D\\u0020\\u1680\\u2000-\\u2006\\u2008-\\u200A'
    '\\u2028\\u2029\\u205F\\u3000]+',
  );

  /// A hyphen between two letters: the engine may break after it
  /// (« Rendez- » / « vous »). Between digits it may not (« 2026-10 »).
  static final RegExp _hyphenBetweenLetters = RegExp(
    r'(?<=\p{L}-)(?=\p{L})',
    unicode: true,
  );

  /// Glue left at the end of a token hangs past the box edge, as a trailing
  /// space does (read off the engine: « 180 000 » + U+00A0, 63.0dp, is drawn
  /// whole in a 60dp box).
  static final RegExp _trailingGlue = RegExp('[\\u00A0\\u2007\\u202F]+\$');

  /// The pieces of [text] the engine may not break inside, in order.
  @visibleForTesting
  static Iterable<String> tokens(String text) => text
      .split(_breakingSpace)
      .expand((piece) => piece.split(_hyphenBetweenLetters))
      .map((token) => token.replaceFirst(_trailingGlue, ''))
      .where((token) => token.isNotEmpty);

  TextStyle _resolve(TextStyle style) {
    var effective = style.inherit ? _defaultStyle.merge(style) : style;
    if (_boldText) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    if (_letterSpacing != null || _wordSpacing != null) {
      effective = effective.merge(
        TextStyle(letterSpacing: _letterSpacing, wordSpacing: _wordSpacing),
      );
    }
    return effective;
  }

  /// The width of [text] drawn on one line in [style].
  double lineWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _resolve(style)),
      textDirection: _textDirection,
      textScaler: _textScaler,
      locale: _locale,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// The width of the widest piece of [text] that may not be broken.
  double widestToken(String text, TextStyle style) => tokens(
    text,
  ).fold(0, (widest, token) => math.max(widest, lineWidth(token, style)));

  /// Whether a box [width] wide draws every one of [texts] without breaking
  /// inside a token.
  bool holds(double width, Iterable<FitText> texts) =>
      texts.every((t) => widestToken(t.text, t.style) + slack <= width);

  /// The first of [candidates] — column counts, widest shape first — whose
  /// cell holds every one of [texts]; the last candidate when none does
  /// (nothing wider is left to give).
  int columns({
    required List<int> candidates,
    required double Function(int columns) cellWidth,
    required Iterable<FitText> texts,
  }) {
    assert(candidates.isNotEmpty);
    final all = texts.toList(growable: false);
    for (final count in candidates) {
      if (holds(cellWidth(count), all)) return count;
    }
    return candidates.last;
  }
}
