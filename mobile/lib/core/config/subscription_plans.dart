/// Provider subscription presentation config (FR-PRO-SUB-001).
///
/// **Provisional — pricing is unvalidated (OQ-2).** All figures live here so
/// they're trivial to change at launch. In-app billing is deferred (PRD §6.3);
/// this is display-only. Design: docs/design/pro-subscription.md.
class SubscriptionPlans {
  const SubscriptionPlans._();

  /// Advertised free period (must match the backend `kProTrialDays = 90`).
  static const int trialMonths = 3;

  /// **Anchor** ("regular") monthly price shown for Pro, in FCFA. Intentionally
  /// higher than the planned launch price (planned base ≈ 20 000–40 000 FCFA,
  /// internal/not shown) so the eventual paid price reads as a discount off this
  /// anchor.
  static const int proAnchorMonthlyFcfa = 70000;

  /// What each tier includes (display checklist).
  static const List<String> freeEntitlements = [
    'Profil public + page de réservation',
    'Accepter les réservations · calendrier',
    '1 membre du personnel',
    'Acomptes activés',
    'Confirmations WhatsApp/SMS de base',
  ];

  static const List<String> proEntitlements = [
    'Réservations illimitées · jusqu’à 5 membres',
    'Rappels automatiques WhatsApp/SMS (24 h / 2 h)',
    'Règles d’acompte & protection no-show',
    'Photos & galerie avant/après',
    'Statistiques & gestion des avis',
    'Sans la marque Myweli · support prioritaire',
  ];

  /// The binding ROI narrative (PRD §6.1).
  static const String roiLine =
      'Un seul rendez-vous manqué évité paie le mois.';
}
