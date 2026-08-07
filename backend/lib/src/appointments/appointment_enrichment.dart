import '../providers_repository.dart';
import '../salon_visibility.dart';
import 'booking_window.dart';

/// The salon facts a consumer's own booking carries (`salon-state-and-refusals.md`
/// §5, Decision C).
///
/// **Why this exists at all.** An appointment stored a `providerId` and nothing
/// else about the salon, so every consumer surface made a SECOND call to the
/// *public* `GET /providers/{id}` just to print a name: web fanned out one
/// request per distinct salon (`bff.ts`'s `providerSummary`), mobile made six
/// from the appointment-detail screen alone. Closing that public read (Decision
/// C) would therefore have broken a client's view of their **own** booking —
/// authenticated data about a salon they have a relationship with.
///
/// The answer is that the relationship lives on the server, so the server
/// hydrates it. `GET /appointments` is already authenticated and already scoped
/// to the caller; it is the endpoint that *owns* the relationship, and it is
/// the one place that can serve a hidden salon's facts without giving an
/// anonymous caller an enumeration oracle. Deliberately **no status filter**:
/// a draft or suspended salon enriches in full, and ships its `providerStatus`
/// so the client can say which state it is in rather than degrade silently.
///
/// **The naming rule, once.** A `provider`-prefixed key is a LIVE salon fact,
/// re-read on every request and never stored on the booking. An unprefixed key
/// is stamped into the booking at write time and immutable — `currency` is the
/// deliberate one (multi-pays §4: a price is what it was, not what it is).
///
/// **The allowlist rule, once.** This runs on every consumer appointment read,
/// so everything on it is disclosed to anyone holding a booking at that salon.
/// Only fields that are public while the salon is `active` may ride here. The
/// catalogue, the artist roster and the gallery are resolved down to the two
/// arrays the surfaces render — never shipped whole, or the closure becomes a
/// back door to the document it closed.
Future<List<Map<String, dynamic>>> withProviderFacts(
  ProvidersRepository providers,
  List<Map<String, dynamic>> items,
) async {
  final ids = {
    for (final a in items)
      if ((a['providerId'] as String?)?.isNotEmpty ?? false)
        a['providerId'] as String,
  }.toList();
  final salons = {
    for (final p in await providers.byIds(ids)) p['id'] as String: p,
  };

  return [for (final a in items) _factsFor(a, salons[a['providerId']])];
}

/// [withProviderFacts] for a single appointment (the detail route).
Future<Map<String, dynamic>> withProviderFactsOne(
  ProvidersRepository providers,
  Map<String, dynamic> appointment,
) async => (await withProviderFacts(providers, [appointment])).single;

Map<String, dynamic> _factsFor(
  Map<String, dynamic> a,
  Map<String, dynamic>? p,
) {
  final services = (p?['services'] as List?) ?? const [];
  final serviceIds = ((a['serviceIds'] as List?) ?? const []).cast<String>();
  final availability = (p?['availability'] as Map?) ?? const {};

  return {
    ...a,
    // Identity.
    'providerName': p?['name'],
    'providerSlug': p?['slug'],
    // The whole point: a client that can no longer read the public document
    // still learns the salon stopped taking appointments, and in which sense.
    'providerStatus': p == null ? null : publicSalonStatus(p),
    // Contact — kept precisely BECAUSE the salon is stopped: this is when a
    // client needs to reach it most.
    'providerPhone': p?['phoneNumber'],
    'providerWhatsapp': p?['whatsapp'],
    'providerAddress': p?['address'],
    // Market facts (MP1) — the consumer renders the SALON's clock and currency.
    'providerCountryCode': p?['countryCode'],
    'providerTimezone': p?['timezone'],
    'providerCurrency': p?['currency'],
    // The deposit coordinates. Without these a pay-later client at a salon the
    // public read no longer serves has nowhere to send the money, on the one
    // screen whose entire job is collecting it.
    'depositMobileMoneyOperator': p?['depositMobileMoneyOperator'],
    'depositMobileMoneyNumber': p?['depositMobileMoneyNumber'],
    // Ids resolved to names: the booking stores ids, the catalogue is the only
    // place the name lives, and the client no longer has the catalogue. A
    // deleted service drops out rather than leaving a null in an array both
    // clients render with a join.
    'artistName': _nameOf(p?['artists'], a['artistId'] as String?),
    'serviceNames': [
      for (final id in serviceIds)
        if (_nameOf(services, id) case final String name) name,
    ],
    // The booking window, so the reschedule picker asks the salon's own rule
    // instead of falling back to a year (A14d). Defaults here, not on the
    // client, so an unreachable salon cannot silently widen the picker.
    'providerBookingHorizonDays':
        (availability['bookingHorizonDays'] as num?)?.toInt() ??
        kDefaultBookingHorizonDays,
    'providerMinimumNoticeMinutes':
        (availability['minimumNoticeMinutes'] as num?)?.toInt() ??
        kDefaultMinimumNoticeMinutes,
    // Backfilled, never overwritten. `durationMinutes` is nullable on a
    // consumer payload, and the reschedule screen needed the whole salon
    // object for exactly this — a 3-hour braid with a null length was offered
    // 30-minute slots. The catalogue that priced the booking is the correct
    // source, and it is already in hand. A stored value wins: a service edited
    // since must not retroactively move an existing appointment.
    'durationMinutes':
        (a['durationMinutes'] as num?)?.toInt() ??
        _durationOf(services, serviceIds),
  };
}

String? _nameOf(Object? list, String? id) {
  if (id == null) return null;
  for (final e in (list as List?) ?? const []) {
    final m = e as Map<String, dynamic>;
    if (m['id'] == id) return m['name'] as String?;
  }
  return null;
}

int? _durationOf(List<dynamic> services, List<String> serviceIds) {
  var total = 0;
  var found = false;
  for (final id in serviceIds) {
    for (final e in services) {
      final m = e as Map<String, dynamic>;
      if (m['id'] == id) {
        total += (m['durationMinutes'] as num?)?.toInt() ?? 0;
        found = true;
      }
    }
  }
  return found ? total : null;
}
