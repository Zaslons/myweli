/// Every French word the salon reads about MyWeli's validation of its salon,
/// in the Pro app (B0.18 — docs/design/salon-go-live-approval.md §6.1, §6.6;
/// the owner's answers of 2026-11-13, decisions 132 and 136). ONE home, so
/// the copy has one ban test (`test/unit/validation_labels_test.dart`):
///
/// - **No « vérif ».** That word is KYC's (« Vérification KYC »); the salon
///   check is « validation » everywhere (spec, Vocabulary).
/// - **The same words as the website** (`web/lib/pro/salon-validation.ts`)
///   wherever the two show the same thing, pinned by
///   `test/unit/salon_go_live_test.dart`.
/// - **The refusal sentences are the server's** (`kRefusalSentences`,
///   backend/lib/src/validation/salon_validation_copy.dart — this file's
///   twin): the push, the feed row and the e-mail say what the app shows.
///
/// The console's words (« En attente de validation », the refusal names)
/// stay in `ValidationLabels`; the derivation that picks among these lives
/// in `lib/core/utils/salon_go_live.dart`.
library;

import '../utils/team_error_messages.dart';

class SalonValidationCopy {
  SalonValidationCopy._();

  // --- why MyWeli refused (§4.3, decision 132) ------------------------------

  /// What the salon reads for each refusal code, verbatim from the server's
  /// `kRefusalSentences`. `other` has none: the salon reads the admin's note
  /// alone.
  static const Map<String, String?> refusalSentences = {
    'incomplete_info':
        'Certaines informations du salon sont incomplètes ou peu claires.',
    'photos':
        'Les photos ne montrent pas assez clairement le salon et son travail.',
    'unconfirmed': 'Nous n’avons pas pu confirmer l’existence de ce salon.',
    'outside_ci':
        'MyWeli n’est pas encore disponible dans votre pays. Si votre salon '
        'est en Côte d’Ivoire, écrivez-nous depuis « Aide & Support ».',
    'test_salon':
        'Ce salon est un salon de test : il ne sera pas mis en ligne.',
    'other': null,
  };

  /// Under a refusal the salon can answer (the server's `kResubmitSentence`).
  static const resubmit =
      'Modifiez votre salon, puis renvoyez-le pour validation.';

  // --- the state's line (the salon picker; §6.1 « Badge / row line ») ------

  static const lineNeverAsked = 'Brouillon — pas encore en ligne';
  static const linePending = 'En cours de validation';
  static const lineRefused = 'Mise en ligne refusée';
  static const lineLive = 'En ligne';
  static const lineOffline = 'Plus en ligne';
  static const lineSuspended = 'Suspendu';

  // --- the banner on « Configuration » (§6.1) -------------------------------

  static const pendingTitle = 'En cours de validation';

  /// No delay promised (Q4).
  static const pendingText =
      'Nous examinons votre salon avant sa mise en ligne. Nous vous '
      'préviendrons dès que c’est fait.';

  static const refusedTitle = 'Mise en ligne refusée';
  static const offlineTitle = 'Votre salon n’est plus en ligne';

  /// Offer lapsed: « Mon abonnement »'s own sentence, never a second one.
  static const offlineUnpaidText = salonUnpublishedForBillingMessage;

  static const offlineRepublishText = 'Vous pouvez le remettre en ligne.';
  static const suspendedTitle = 'Votre salon est suspendu';

  /// New with B0.18 (corrected 2026-11-13, web-salon-validation.md §3.1).
  /// A server from before B0.18 keeps the older sentence
  /// (`salonSuspendedMessage`).
  static const suspendedText = 'Contactez MyWeli pour en savoir plus.';

  // --- the action (§6.1 « Button ») ------------------------------------------

  /// Today's button, kept on a server from before B0.18: there, the publish
  /// does put the salon online.
  static const legacyButton = 'Mettre mon profil en ligne';
  static const requestButton = 'Demander la mise en ligne';
  static const resubmitButton = 'Renvoyer pour validation';

  /// Validated, went live once, back to `draft`, its offer live: the publish
  /// answers 200.
  static const republishButton = 'Remettre en ligne';

  /// The unpaid banner's pointer (decision 136 item 5): « Mon abonnement »'s
  /// own title. It opens that screen — a pointer, never a choice of offer.
  static const billingPointer = 'Mon abonnement';

  /// Beside a disabled button. Today's, kept on a server from before B0.18.
  static const legacyHint =
      'Complétez les étapes essentielles pour mettre votre profil en ligne.';
  static const requestHint =
      'Complétez les étapes essentielles pour demander la mise en ligne.';

  /// In place of the button while the request waits (decision 136 item 6:
  /// no weekday, as the website) — [requestSentOn] fills the date.
  static const requestSentOnPrefix = 'Demande envoyée le';

  /// « Demande envoyée le 13 novembre 2026 ».
  static String requestSentOn(String date) => '$requestSentOnPrefix $date';

  // --- after a publish (§6.1 « After a request ») ----------------------------

  /// A 202 the salon now waits on (decision 136 item 7: not for a 202 whose
  /// validation is refused or null).
  static const requestSent =
      'Demande envoyée. Nous vous préviendrons de la décision.';

  /// A 200 only: the salon is online.
  static const wentLive = '🎉 Votre profil est en ligne !';

  /// A stale button hit by a 409 `validation_refused_final` (decision 136
  /// item 2): said, then the screen re-reads and shows the refused banner.
  static const refusedFinalMessage = lineRefused;

  // --- the home card « Configurer mon profil » (decision 136 item 1) --------

  /// Today's subtitle: never asked, a server from before B0.18, and a state
  /// not read yet (an offline cold start — §6.2).
  static const homeSetUp = 'Complétez les étapes pour aller en ligne';
  static const homeLive = 'Votre salon est en ligne';

  // --- « Profil de l’entreprise » (R8, decision 136 item 4) ------------------

  /// The profile is filled, but its commune is not one of MyWeli's: the
  /// server's `validArea` would refuse it. The website's words.
  static const communeFromList = 'Choisissez la commune dans la liste';
}
