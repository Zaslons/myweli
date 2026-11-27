import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';

/// The sentence that says where a code went, with the address on a line of
/// its own (docs/design/account-email-change.md §12, SYSTEM.md §13.3):
///
/// ```text
/// Entrez le code reçu par e-mail à
/// aminata.kone
/// @exemple.ci
/// ```
///
/// **Why not one sentence.** Inline after « à », an address wider than the
/// line — about 18 characters at 200 % on 360 dp, so most real ones — began
/// on the line the sentence had started and was cut wherever it ran out:
/// « par e-mail à aminata. » / « kone@exemple.ci. ». On its own line it breaks
/// only at its seams ([Formatters.breakableEmail]). No period is drawn after
/// it: on a line of its own, it would read as part of the address.
///
/// The address is in ink, as « Modifier le profil » shows it; the sentence
/// keeps its secondary colour. A screen reader hears ONE node, the sentence
/// it always heard — « Entrez le code reçu par e-mail à aminata.kone@exemple.ci. »
/// — and never the break marks.
///
/// Used on every code step that names an address: the sign-in, the Pro
/// sign-in, the Android Pro sign-up, and the address change (both codes).
class CodeSentTo extends StatelessWidget {
  /// « Entrez le code reçu par e-mail à » / {address}.
  const CodeSentTo.byEmail(
    this.address, {
    super.key,
    this.textAlign = TextAlign.start,
  }) : lead = 'Entrez le code reçu par e-mail à',
       _spokenJoin = ' ';

  /// « Entrez le code reçu à votre adresse actuelle » / {address}: decision
  /// 265's second code. Its comma stays in what a screen reader hears.
  const CodeSentTo.currentAddress(
    this.address, {
    super.key,
    this.textAlign = TextAlign.start,
  }) : lead = 'Entrez le code reçu à votre adresse actuelle',
       _spokenJoin = ', ';

  /// The sentence, drawn above the address.
  final String lead;

  /// The address the code went to, as typed or stored — without marks.
  final String address;

  /// The screen's own: the sign-ins centre, the change screen starts.
  final TextAlign textAlign;

  final String _spokenJoin;

  /// What a screen reader hears: the whole sentence, its period included.
  String get spoken => '$lead$_spokenJoin$address.';

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: spoken,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            lead,
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: textAlign,
          ),
          Text(
            Formatters.breakableEmail(address),
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.textPrimary,
            ),
            textAlign: textAlign,
          ),
        ],
      ),
    ),
  );
}
