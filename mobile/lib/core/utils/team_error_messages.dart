/// Machine-code → French copy for the team & offers surfaces (team access
/// R3). ONE table used by BOTH the mock and the API services so the copy
/// can never drift between backends.
/// Design: docs/design/team-access-r3-app.md §7.
String teamErrorMessage(String? code, {String? fallback}) => switch (code) {
      'member_exists' => 'Cette personne est déjà dans l\'équipe.',
      'offer_required' =>
        'Choisissez d\'abord votre offre pour inviter votre équipe.',
      'seat_limit' => 'Toutes les places de votre offre sont occupées.',
      'invite_rate_limited' =>
        'Trop d\'invitations envoyées aujourd\'hui. Réessayez demain.',
      'owner_protected' => 'Le propriétaire ne peut pas être modifié.',
      'invitation_expired' =>
        'Cette invitation a expiré. Demandez au salon de la renvoyer.',
      'invalid_role' => 'Rôle invalide.',
      'artist_required' => 'Choisissez la fiche employé du collaborateur.',
      'artist_not_found' =>
        'Fiche employé introuvable. Actualisez et réessayez.',
      'trial_used' =>
        'Votre essai gratuit a déjà été utilisé. Contactez-nous pour '
            'activer votre offre.',
      'not_found' => 'Introuvable. Actualisez et réessayez.',
      // R6 multi-salons (« Ajouter un salon »).
      'reseau_required' => 'L\'offre Réseau est requise pour ajouter un salon. '
          'Passez à l\'offre Réseau depuis « Mon abonnement ».',
      'salon_limit' =>
        'Limite de salons atteinte. Contactez-nous pour aller plus loin.',
      'not_a_member' => 'Votre accès à ce salon a été retiré.',
      'forbidden' => 'Action réservée au propriétaire du salon.',
      _ => fallback ?? 'Une erreur est survenue. Réessayez.',
    };

/// The resend budget exhausts per-invitation — a different message than the
/// per-day invite cap that shares the machine code.
const String resendBudgetExhaustedMessage =
    'Budget de renvois épuisé pour cette invitation.';
