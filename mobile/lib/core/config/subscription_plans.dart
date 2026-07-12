import '../../models/salon_subscription.dart';

/// Provider offer-ladder presentation config (pricing pivot, team access
/// R2a/R3). **Provisional — pricing is unvalidated (OQ-2).** All figures live
/// here so they're trivial to change at launch. Billing stays manual
/// (« Nous contacter », no custody); this is display-only.
/// Design: docs/design/team-access-r3-app.md.
class SubscriptionPlans {
  const SubscriptionPlans._();

  /// Advertised free period (must match the backend trial of 90 days).
  static const int trialMonths = 3;

  /// **Anchor** ("regular") monthly prices in FCFA — intentionally higher
  /// than the planned launch prices so the eventual paid price reads as a
  /// discount off these anchors. Réseau has no figure (« Sur devis »).
  static const int proAnchorMonthlyFcfa = 70000;
  static const int businessAnchorMonthlyFcfa = 120000;

  /// Seats per offer (mirrors the backend tier config).
  static const int proSeats = 5;
  static const int businessSeats = 15;
  static const int reseauSeatsPerSalon = 15;

  static int seatsFor(SalonTier tier) => switch (tier) {
        SalonTier.pro => proSeats,
        SalonTier.business => businessSeats,
        SalonTier.reseau => reseauSeatsPerSalon,
      };

  /// What each offer includes (display checklists).
  static const List<String> proEntitlements = [
    'Réservations illimitées',
    'Jusqu’à 5 membres d’équipe',
    'Rappels automatiques WhatsApp/SMS (24 h / 2 h)',
    'Règles d’acompte & protection no-show',
    'Photos & galerie avant/après',
    'Statistiques & gestion des avis',
  ];

  static const List<String> businessEntitlements = [
    'Tout de l’offre Pro',
    'Jusqu’à 15 membres d’équipe',
    'Support prioritaire dédié',
  ];

  static const List<String> reseauEntitlements = [
    'Tout de l’offre Business',
    'Multi-salons — ajoutez des salons à votre compte',
    'Tarif personnalisé',
  ];

  static List<String> entitlementsFor(SalonTier tier) => switch (tier) {
        SalonTier.pro => proEntitlements,
        SalonTier.business => businessEntitlements,
        SalonTier.reseau => reseauEntitlements,
      };

  /// The binding ROI narrative (PRD §6.1).
  static const String roiLine =
      'Un seul rendez-vous manqué évité paie le mois.';
}
