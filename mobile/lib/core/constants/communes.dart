/// MOCK SEED ONLY (multi-pays MP2 — docs/design/multi-pays-end-version.md
/// §6): the live app reads the locality tree from `GET /localities` via
/// `LocalityProvider`; this historical list now seeds `MockLocalityService`
/// exclusively so the mock world mirrors the backend seed. Do NOT import it
/// from screens/widgets (grep-pinned).
///
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
