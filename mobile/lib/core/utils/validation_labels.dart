import '../../models/admin_salon_validation.dart';
import '../../models/salon_validation.dart';

/// The admin console's words for a salon's validation (B0.18 —
/// docs/design/salon-go-live-approval.md §4.3, §4.4).
///
/// **Its own vocabulary, not [StatusLabels]'s.** That one resolves `pending`
/// through the booking enum first (« En attente »), so it cannot say « En
/// attente de validation » — and teaching it to would relabel every KYC and
/// booking « En attente » in the console. Pinned by
/// `test/unit/validation_labels_test.dart`, which also holds the shared label
/// still.
///
/// **No « vérif » here.** That word is KYC's (« Vérification KYC »); the salon
/// check is « validation » everywhere (spec, Vocabulary).
///
/// The error sentences the routes answer live with the other codes in
/// `AdminService.sentenceFor`; this file holds what the console LABELS.
class ValidationLabels {
  ValidationLabels._();

  // --- the validation's state (§4.4) ----------------------------------------

  static const pending = 'En attente de validation';
  static const approved = 'Validé';
  static const refused = 'Refusé';

  /// Approved, never live — a validation interrupted before it took the salon
  /// public (§3.2); the same button finishes it.
  static const finishing = 'Validation à terminer';

  /// The salon never asked to go live (a detail reached by its URL).
  static const neverAsked = 'Aucune demande de mise en ligne';

  /// The label of a validation, or null for a state this build does not know
  /// (the caller shows « — », never the wire value).
  static String? of(SalonValidation? v) {
    if (v == null) return neverAsked;
    return switch (v.state) {
      SalonValidationState.pending => pending,
      SalonValidationState.approved => v.wentLive ? approved : finishing,
      SalonValidationState.refused => refused,
      SalonValidationState.unknown => null,
    };
  }

  // --- refusing (§4.3) ------------------------------------------------------

  /// The short name the admin picks in the refusal dialog, per code.
  static const Map<String, String> refusalNames = {
    'incomplete_info': 'Informations incomplètes',
    'photos': 'Photos insuffisantes',
    'unconfirmed': 'Salon non confirmé',
    'outside_ci': 'Hors de Côte d’Ivoire',
    'test_salon': 'Salon de test',
    'other': 'Autre',
  };

  /// What the salon reads for each code — the owner's approved words
  /// (decision 132), the server's `kRefusalSentences`
  /// (salon_validation_copy.dart). `other` has none: the salon reads the note
  /// alone.
  static const Map<String, String?> salonSentences = {
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

  /// The admin name of a code, or the code itself when this build does not
  /// know it (the console is an internal tool; a raw code is information).
  static String refusalName(String? code) =>
      refusalNames[code] ?? (code ?? '—');

  /// A final code removes « Renvoyer pour validation » on the salon's side.
  static bool isFinal(String code) => kFinalSalonRefusalCodes.contains(code);

  // --- the go-live gate's steps (a 409 `incomplete`'s `missing`) ------------

  /// Each key of the gate as the 409 sentence lists it (« Le salon n’est plus
  /// complet : photos, horaires. »). `photos` and `availability` are the
  /// spec's words; the others are the Pro checklist's step names
  /// (pro_onboarding_screen.dart), lower-cased and without « (3 minimum) », as
  /// the spec wrote « photos » for « Photos (3 minimum) ». `offer` has its own
  /// sentence, never this list. An unknown key is kept as sent.
  static String missingStep(String key) => switch (key) {
    'profile' => 'profil de l’entreprise',
    'location' => 'position sur la carte',
    'services' => 'services',
    'photos' => 'photos',
    'availability' => 'horaires',
    'offer' => 'offre',
    _ => key,
  };

  // --- « Lever la suspension » (§4.4) ---------------------------------------

  static const restoredLive = 'Salon remis en ligne';

  /// Followed by the reason's word.
  static const restoredOffline =
      'Suspension levée — le salon reste hors ligne : ';

  /// Why a lifted suspension left the salon offline.
  static String restoreReason(String? reason) => switch (reason) {
    'not_validated' => 'non validé',
    'offer_not_live' => 'offre inactive',
    'unpaid' => 'dépublié pour impayé',
    'no_owner' => 'sans propriétaire',
    'unknown_prior' => 'état antérieur inconnu',
    _ => 'motif non reconnu',
  };

  /// The snackbar after a lift — from either server: the older one always
  /// answers a live salon.
  static String restoreMessage(RestoreOutcome outcome) => outcome.isLive
      ? restoredLive
      : '$restoredOffline${restoreReason(outcome.reason)}';

  // --- the request's history ------------------------------------------------

  static String eventKind(ValidationEventKind kind) => switch (kind) {
    ValidationEventKind.submitted => 'Demande de mise en ligne',
    ValidationEventKind.approved => 'Validé',
    ValidationEventKind.refused => 'Refusé',
    ValidationEventKind.unknown => '—',
  };

  // --- before the backend deploy (§9.2) -------------------------------------

  /// The queue's calm state while the server predates B0.18 (its routes
  /// answer 404): the console goes live first.
  static const unavailableTitle = 'Validation des salons pas encore active';
  static const unavailableBody =
      'Le serveur ne gère pas encore la validation des salons. Cette page '
      's’activera après sa mise à jour.';
}
