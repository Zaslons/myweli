import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/formatters.dart';

/// A sentence that names an e-mail address, drawn with the address on a line
/// of its own (SYSTEM.md §13.3):
///
/// ```text
/// Quel rôle pour                  aminata.kone
/// aminata.kone                    @exemple.ci
/// @exemple.ci                     perdra immédiatement l’accès à…
/// ```
///
/// **Why not one sentence.** Inline, an address wider than the line — about
/// 18 characters at 200 % on 360 dp, so most real ones — starts on a line the
/// sentence has begun, or runs on into it, and is cut wherever that line ends:
/// « Quel rôle pour adjoua.ko » / « uame@exemple.ci ? ». On its own line it
/// breaks only at its seams ([Formatters.breakableEmail]). Nothing is drawn
/// after it on its line: a period or a « ? » there would read as part of the
/// address.
///
/// The address is in ink; the sentence keeps its own style — [style] merged
/// over the ambient [DefaultTextStyle], so in a dialog it is the dialog's. A
/// screen reader hears ONE node, [spoken] — the sentence as it was always
/// said, punctuation included — and never the break marks.
///
/// Used by [CodeSentTo] (the code steps), « Équipe »'s « Révoquer l’accès ? »
/// and the invite sheet's role step (docs/design/app-team-email-seams.md).
class EmailSentence extends StatelessWidget {
  /// [lead] drawn first, the address on the line under it.
  const EmailSentence.addressLast({
    super.key,
    required String lead,
    required this.address,
    this._spoken,
    this.style,
    this.textAlign = TextAlign.start,
  }) : _before = lead,
       _after = null;

  /// The address drawn first, [rest] under it — « {adresse} perdra
  /// immédiatement l’accès à … ».
  const EmailSentence.addressFirst({
    super.key,
    required this.address,
    required String rest,
    this._spoken,
    this.style,
    this.textAlign = TextAlign.start,
  }) : _before = null,
       _after = rest;

  /// The address, as typed or stored — without marks.
  final String address;

  /// The sentence's style, merged over the ambient one. The address takes
  /// it too, in ink.
  final TextStyle? style;

  final TextAlign textAlign;

  final String? _before;
  final String? _after;
  final String? _spoken;

  /// What a screen reader hears: the whole sentence. By default the drawn
  /// words joined by a space; a caller whose sentence ends after the address
  /// (a period, a « ? ») says so.
  String get spoken => _spoken ?? [?_before, address, ?_after].join(' ');

  @override
  Widget build(BuildContext context) {
    final sentence = DefaultTextStyle.of(context).style.merge(style);
    final ink = sentence.copyWith(color: AppColors.textPrimary);
    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_before case final before?)
              Text(before, style: sentence, textAlign: textAlign),
            Text(
              Formatters.breakableEmail(address),
              style: ink,
              textAlign: textAlign,
            ),
            if (_after case final after?)
              Text(after, style: sentence, textAlign: textAlign),
          ],
        ),
      ),
    );
  }
}
