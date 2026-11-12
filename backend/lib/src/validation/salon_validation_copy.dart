/// The salon validation's words, as the owner approved them (decision 132,
/// « Yes, use these words », 2026-11-12) — docs/design/salon-go-live-approval.md
/// §4.3 (the reasons), §5.2 (the pushes), §6.1 (the resubmit sentence).
///
/// One place, because three channels say them (the push, the in-app feed
/// row, the e-mail) and the apps word the same codes: a sentence edited in
/// one channel only would tell the salon two different things.
///
/// **No « vérif » here.** That word is KYC's (« Vérification »); the salon
/// check is « validation » everywhere (spec, Vocabulary).
library;

import 'salon_validation_repository.dart';

/// §4.3: what the salon reads for each refusal code. `other` has no
/// sentence of its own — the salon reads the admin's note alone (required
/// for that code).
const Map<String, String?> kRefusalSentences = {
  'incomplete_info':
      'Certaines informations du salon sont incomplètes ou peu claires.',
  'photos':
      'Les photos ne montrent pas assez clairement le salon et son travail.',
  'unconfirmed': 'Nous n’avons pas pu confirmer l’existence de ce salon.',
  'outside_ci':
      'MyWeli n’est pas encore disponible dans votre pays. Si votre salon est '
      'en Côte d’Ivoire, écrivez-nous depuis « Aide & Support ».',
  'test_salon': 'Ce salon est un salon de test : il ne sera pas mis en ligne.',
  'other': null,
};

/// §6.1: what a salon refused for a reason it can fix does next. Never said
/// after a final refusal (§4.3), which no new request can answer.
const kResubmitSentence =
    'Modifiez votre salon, puis renvoyez-le pour validation.';

/// The refusal as the salon reads it: the code's sentence, then the note on
/// its own line. For `other`, the note alone.
String refusalText(String code, String? note) {
  final sentence = kRefusalSentences[code];
  final n = (note == null || note.trim().isEmpty) ? null : note.trim();
  return [?sentence, ?n].join('\n');
}

/// §5.2, validated: the push and feed title.
String approvedTitle(String salonName) => '$salonName est en ligne';

/// §5.2, validated: the push and feed body.
const kApprovedBody =
    'Vos clients peuvent maintenant trouver votre salon et réserver.';

/// §5.2, refused: the push and feed title.
String refusedTitle(String salonName) => 'Mise en ligne de $salonName refusée';

/// §5.2, refused: the push body is the code's sentence — for `other`, the
/// note, which is all that code says.
String refusedPushBody(String code, String? note) =>
    kRefusalSentences[code] ?? (note?.trim() ?? '');

/// Whether [code] is final (§4.3) — mirrors [kFinalRefusalCodes].
bool isFinalRefusalCode(String code) => kFinalRefusalCodes.contains(code);
