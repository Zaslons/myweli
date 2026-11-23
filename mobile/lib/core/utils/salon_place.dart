import '../../models/appointment.dart';

/// « commune, ville » — the commune first, the city after it when known.
/// Null without a commune.
String? communeLine(String? commune, String? city) {
  final c = commune?.trim();
  if (c == null || c.isEmpty) return null;
  final v = city?.trim();
  return v == null || v.isEmpty ? c : '$c, $v';
}

/// The address lines of « Le salon » on the detail
/// (appointment-detail-complete.md §2.6): the address, then « commune, ville »
/// when the address does not already name the commune — compared without
/// case or accents, so « Cocody » is found in « Rue des Jardins, COCODY ».
List<String> salonAddressLines(Appointment a) {
  final address = a.providerAddress?.trim();
  final hasAddress = address != null && address.isNotEmpty;
  final commune = communeLine(a.providerCommune, a.providerCity);
  final named =
      hasAddress &&
      a.providerCommune != null &&
      fold(address).contains(fold(a.providerCommune!.trim()));
  return [if (hasAddress) address, if (commune != null && !named) commune];
}

/// The card's place line (§2.9): the booking's « commune, ville » when it
/// knows the commune; else what the discovery list holds for the salon (its
/// city, else its address) — the card's line before A2, for an older server.
String? cardPlaceLine(
  Appointment a, {
  String? listedCity,
  String? listedAddress,
}) {
  final commune = communeLine(a.providerCommune, a.providerCity);
  if (commune != null) return commune;
  for (final v in [listedCity, listedAddress]) {
    final t = v?.trim();
    if (t != null && t.isNotEmpty) return t;
  }
  return null;
}

/// The card's position: the booking's pair first, else the discovery list's.
({double lat, double lng})? cardPosition(
  Appointment a, {
  double? listedLat,
  double? listedLng,
}) {
  if (a.hasPosition) {
    return (lat: a.providerLatitude!, lng: a.providerLongitude!);
  }
  if (listedLat != null && listedLng != null) {
    return (lat: listedLat, lng: listedLng);
  }
  return null;
}

/// The card's photo: the booking's cover first. The discovery list is the
/// fallback only while the salon is live: the server sends no photo for a
/// stopped salon (decision 194), and a list loaded before it stopped must not
/// bring that cover back.
String? cardPhoto(Appointment a, {String? listedPhoto}) {
  final own = a.providerPhotoUrl;
  if (own != null && own.isNotEmpty) return own;
  if (!a.salonIsLive) return null;
  return listedPhoto == null || listedPhoto.isEmpty ? null : listedPhoto;
}

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'î': 'i', 'ï': 'i', 'í': 'i', //
  'ô': 'o', 'ö': 'o', 'ó': 'o', //
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', //
  'ÿ': 'y', 'ç': 'c', 'œ': 'oe', 'æ': 'ae',
};

/// Lower case, without French accents.
String fold(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    out.write(_accents[ch] ?? ch);
  }
  return out.toString();
}
