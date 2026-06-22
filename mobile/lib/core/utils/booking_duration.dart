import '../../models/service.dart';

/// Hair-length variant keys, in display order.
const lengthVariantOrder = ['court', 'moyen', 'long'];

/// The duration a [service] takes for the chosen hair [length]. Falls back to
/// the service's default [Service.durationMinutes] when it declares no variant
/// for that length (or has no variants at all).
int serviceDurationFor(Service service, String? length) {
  final variants = service.durationVariants;
  if (length != null && variants.isNotEmpty) {
    final minutes = switch (length) {
      'court' => variants.court,
      'moyen' => variants.moyen,
      'long' => variants.long,
      _ => null,
    };
    if (minutes != null) return minutes;
  }
  return service.durationMinutes;
}

/// Total duration of a booking's [services] for the chosen [length].
int totalBookingDuration(Iterable<Service> services, String? length) =>
    services.fold<int>(0, (sum, s) => sum + serviceDurationFor(s, length));

/// Whether any of [services] prices/times differently by length.
bool bookingHasVariants(Iterable<Service> services) =>
    services.any((s) => s.durationVariants.isNotEmpty);

/// The length buckets actually offered across [services] (union), ordered.
List<String> availableLengthVariants(Iterable<Service> services) {
  final present = <String>{};
  for (final s in services) {
    final v = s.durationVariants;
    if (v.court != null) present.add('court');
    if (v.moyen != null) present.add('moyen');
    if (v.long != null) present.add('long');
  }
  return lengthVariantOrder.where(present.contains).toList();
}

/// A sensible default length for [services]: prefer 'moyen', else the first
/// available bucket, else null (no variant services selected).
String? defaultLengthVariant(Iterable<Service> services) {
  final available = availableLengthVariants(services);
  if (available.isEmpty) return null;
  if (available.contains('moyen')) return 'moyen';
  return available.first;
}

String lengthVariantLabel(String key) => switch (key) {
      'court' => 'Court',
      'moyen' => 'Moyen',
      'long' => 'Long',
      _ => key,
    };
