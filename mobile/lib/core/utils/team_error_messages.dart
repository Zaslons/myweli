/// Machine-code → French copy for the team & offers surfaces (team access
/// R3). ONE table used by BOTH the mock and the API services so the copy
/// can never drift between backends.
///
/// **No sentence here sends the salon anywhere to obtain an offer.** The Pro
/// app is a companion app (App Store 3.1.3(f)): it states a fact — the offer
/// is not active, the places are taken — and never asks the salon to choose,
/// upgrade or contact anyone about an offer, nor says where one is bought. An
/// `InlineFeedback` is a live region, so VoiceOver reads these sentences
/// aloud: removing the button beside one is not enough, the sentence itself
/// must be neutral. Design: docs/design/team-access-r3-app.md §7,
/// docs/design/pro-companion-path.md §2.2.
String teamErrorMessage(String? code, {String? fallback}) => switch (code) {
  'member_exists' => 'Cette personne est déjà dans l’équipe.',
  // The code alone cannot tell setup from expired — this is the setup
  // sentence (the common case); the invite sheet upgrades it when an offer
  // row is known to exist, or implied by the salon being online. See
  // [inviteOfferRequiredMessage].
  'offer_required' => inviteOfferRequiredMessage(offerExists: false),
  'seat_limit' => 'Toutes les places de votre offre sont occupées.',
  'invite_rate_limited' =>
    'Trop d’invitations envoyées aujourd’hui. Réessayez demain.',
  'owner_protected' => 'Le propriétaire ne peut pas être modifié.',
  'invitation_expired' =>
    'Cette invitation a expiré. Demandez au salon de la renvoyer.',
  'invalid_role' => 'Rôle invalide.',
  'artist_required' => 'Choisissez la fiche employé du collaborateur.',
  'artist_not_found' => 'Fiche employé introuvable. Actualisez et réessayez.',
  'trial_used' => 'Votre essai gratuit a déjà été utilisé.',
  'not_found' => 'Introuvable. Actualisez et réessayez.',
  // R6 multi-salons (« Ajouter un salon »).
  'reseau_required' =>
    'L’ajout de salons n’est pas disponible avec l’offre actuelle.',
  'salon_limit' => 'Nombre maximal de salons atteint.',
  'not_a_member' => 'Votre accès à ce salon a été retiré.',
  'forbidden' => 'Action réservée au propriétaire du salon.',
  'demo_account_locked' => demoAccountLockedMessage,
  _ => fallback ?? 'Une erreur est survenue. Réessayez.',
};

/// The invite refused by the offer gate (`offer_required`). The server sends
/// one code for two different salons, and they need different sentences:
///
/// - **no offer row** (setup — the trial starts at the first publish): the
///   invites open once the salon is online;
/// - **a row that is no longer live** (expired): the invites are unavailable.
///
/// Neither names a way to get an offer (pro-companion-path §2.2, §11 Q4).
String inviteOfferRequiredMessage({required bool offerExists}) => offerExists
    ? 'Les invitations sont indisponibles : l’offre de votre salon n’est '
          'plus active.'
    : 'Vous pourrez inviter votre équipe une fois votre salon en ligne.';

/// Publish refused by the offer gate (`missing: ['offer']`). Since the server
/// starts the trial at the first publish, only a salon whose offer EXPIRED
/// reaches this — so it states that, and offers no way out to a purchase.
/// Shared by the API and mock publish and by the onboarding screen.
const String publishOfferInactiveMessage =
    'La mise en ligne est indisponible : l’offre de votre salon n’est plus '
    'active.';

/// The demo account's 403 (`demo_account_locked`) — the sentence the App
/// Review notes promise. Its credential is public, so the server refuses the
/// actions that would outlive the weekly reset.
const String demoAccountLockedMessage =
    'Compte de démonstration — cette action est désactivée.';

/// The resend budget exhausts per-invitation — a different message than the
/// per-day invite cap that shares the machine code.
const String resendBudgetExhaustedMessage =
    'Budget de renvois épuisé pour cette invitation.';
