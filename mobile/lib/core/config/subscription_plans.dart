import '../../models/salon_subscription.dart';

/// Seats per offer — the backend tier config mirrored for the mock world
/// (the mock derives a salon's seat cap from its tier, the server sends it).
///
/// **Nothing here is displayed.** The Pro app shows only the salon's CURRENT
/// offer — its tier, status, dates and seats, all from the server — and never
/// another tier, a price, a trial promotion or an entitlement list: it is a
/// companion app (App Store 3.1.3(f)), and offers are chosen on the web. The
/// trial length, the anchors, the entitlement checklists and the ROI line
/// left with the picker. Design: docs/design/pro-companion-path.md §2.
class SubscriptionPlans {
  const SubscriptionPlans._();

  static const int proSeats = 5;
  static const int businessSeats = 15;
  static const int reseauSeatsPerSalon = 15;

  static int seatsFor(SalonTier tier) => switch (tier) {
    SalonTier.pro => proSeats,
    SalonTier.business => businessSeats,
    SalonTier.reseau => reseauSeatsPerSalon,
  };
}
