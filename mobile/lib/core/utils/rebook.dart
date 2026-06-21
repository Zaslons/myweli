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
