import '../../models/appointment.dart';
import 'client_booking_rule.dart';

/// The services + stylist to pre-fill when rebooking, after dropping anything
/// that no longer exists on the provider.
class RebookSelection {
  final List<String> serviceIds;
  final String? artistId;

  const RebookSelection({required this.serviceIds, this.artistId});
}

/// Keep only the services and stylist that still exist on the provider, so a
/// rebook pre-fill never references stale data.
RebookSelection sanitizeRebookSelection({
  required List<String> serviceIds,
  required String? artistId,
  required Set<String> availableServiceIds,
  required Set<String> availableArtistIds,
}) {
  final validServices = serviceIds.where(availableServiceIds.contains).toList();
  final validArtist =
      (artistId != null && availableArtistIds.contains(artistId))
      ? artistId
      : null;
  return RebookSelection(serviceIds: validServices, artistId: validArtist);
}

/// « Réserver à nouveau »: any booking that is not upcoming, at a salon still
/// taking appointments (decision 183 on the web, decision 201 in the app).
/// `salonIsLive` is false for a salon status this build does not know.
bool canRebook(Appointment a, DateTime now) =>
    clientTab(a, now) != ClientBookingTab.upcoming && a.salonIsLive;

/// The booking hub, prefilled with the booking's services and specialist. The
/// hub checks them against the live catalogue (`sanitizeRebookSelection`).
/// One route for « Passés » and the detail.
String rebookLocation(Appointment a) => Uri(
  path: '/booking',
  queryParameters: {
    'providerId': a.providerId.value,
    if (a.serviceIds.isNotEmpty) 'serviceIds': a.serviceIds.join(','),
    if (a.artistId != null) 'artistId': a.artistId!,
  },
).toString();
