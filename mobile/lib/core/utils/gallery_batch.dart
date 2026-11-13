/// Several gallery photos picked at once — the pure rules
/// (docs/design/gallery-multi-select.md). The website's `lib/pro/medias.ts`
/// holds the same rules and the same sentences; keep them together.
library;

/// The server's cap (`ProviderCatalogService._maxGalleryPhotos`), and the
/// website's `MAX_GALLERY`.
const int kMaxGalleryPhotos = 20;

/// What fits of a multi-photo pick: the FIRST ones in the order picked, up to
/// the room left under [kMaxGalleryPhotos]; `dropped` is how many did not fit.
({List<T> kept, int dropped}) fitInGallery<T>(List<T> picked, int current) {
  final room = (kMaxGalleryPhotos - current).clamp(0, kMaxGalleryPhotos);
  final kept = picked.take(room).toList();
  return (kept: kept, dropped: picked.length - kept.length);
}

/// « 20 photos maximum : 3 photos n’ont pas été ajoutées. » (§2.4)
String overCapMessage(int dropped) => dropped == 1
    ? '$kMaxGalleryPhotos photos maximum : 1 photo n’a pas été ajoutée.'
    : '$kMaxGalleryPhotos photos maximum : $dropped photos n’ont pas été '
          'ajoutées.';

/// The one message at the end of a multi-photo add (§2.4). Null for a batch of
/// one with nothing left out — today's messages, unchanged. The app has no
/// typed failure reasons, so it carries no shared hint (the website does).
({String message, bool isError})? gallerySummary({
  required int total,
  required int added,
  int dropped = 0,
}) {
  final capNote = dropped > 0 ? ' ${overCapMessage(dropped)}' : '';
  if (total < 2) {
    return dropped > 0
        ? (message: overCapMessage(dropped), isError: false)
        : null;
  }
  if (added == total) {
    return (message: '$added photos ajoutées.$capNote', isError: false);
  }
  if (added == 0) {
    return (
      message: 'Aucune photo n’a pu être envoyée.$capNote',
      isError: true,
    );
  }
  final failed = total - added;
  final addedText = added == 1 ? '1 photo ajoutée' : '$added photos ajoutées';
  final failedText = failed == 1
      ? '1 n’a pas pu être envoyée.'
      : '$failed n’ont pas pu être envoyées.';
  return (message: '$addedText sur $total. $failedText$capNote', isError: true);
}
