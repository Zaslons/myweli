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

/// The card's one place line (§2.9): « commune, ville », else the city, else
/// the address. Null when the booking knows none of them.
String? cardPlaceLine(Appointment a) {
  final commune = communeLine(a.providerCommune, a.providerCity);
  if (commune != null) return commune;
  final city = a.providerCity?.trim();
  if (city != null && city.isNotEmpty) return city;
  final address = a.providerAddress?.trim();
  return address == null || address.isEmpty ? null : address;
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
