/// A commune of Abidjan, with an approximate centroid used to resolve the
/// "Près de moi" option to the nearest commune.
class Commune {
  final String name;
  final double latitude;
  final double longitude;

  const Commune({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

/// The communes Myweli supports for filtering. Launch focus is Cocody, Marcory
/// and Plateau (PRD §19); the rest are listed so the picker isn't limited to
/// communes that happen to have providers yet.
const List<Commune> abidjanCommunes = [
  Commune(name: 'Cocody', latitude: 5.3600, longitude: -4.0083),
  Commune(name: 'Marcory', latitude: 5.2800, longitude: -4.0500),
  Commune(name: 'Plateau', latitude: 5.3200, longitude: -4.0300),
  Commune(name: 'Yopougon', latitude: 5.3200, longitude: -4.0800),
  Commune(name: 'Treichville', latitude: 5.2930, longitude: -4.0100),
  Commune(name: 'Adjamé', latitude: 5.3660, longitude: -4.0250),
  Commune(name: 'Abobo', latitude: 5.4200, longitude: -4.0200),
  Commune(name: 'Koumassi', latitude: 5.2900, longitude: -3.9450),
  Commune(name: 'Port-Bouët', latitude: 5.2550, longitude: -3.9260),
  Commune(name: 'Attécoubé', latitude: 5.3400, longitude: -4.0350),
  Commune(name: 'Bingerville', latitude: 5.3550, longitude: -3.8900),
];

/// Returns the commune nearest to the given coordinates, or null if the list is
/// empty. Squared-degree distance is enough to rank communes within one city —
/// we don't need true geodesic distance here.
Commune? nearestCommune(double latitude, double longitude) {
  Commune? best;
  var bestDistance = double.infinity;
  for (final c in abidjanCommunes) {
    final dLat = c.latitude - latitude;
    final dLng = c.longitude - longitude;
    final d = dLat * dLat + dLng * dLng;
    if (d < bestDistance) {
      bestDistance = d;
      best = c;
    }
  }
  return best;
}
