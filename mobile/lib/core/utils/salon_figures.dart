import '../../models/provider.dart';

/// A salon's `rating` and `reviewCount` after one review is published —
/// docs/design/amounts-that-fit.md §5 « Reviews ».
///
/// The server keeps ONE review per appointment: a visit reviewed again
/// replaces its review, so the count stays and the average moves by the
/// difference ([replacedStars] is what that visit said before). A first
/// review of a visit adds one.
///
/// **An estimate, not the server's figure.** The server averages the stars;
/// this can only start from the stored average, already rounded to one
/// decimal — so it may sit 0,1 away (4, 4 and 5 are stored « 4,3 »; a fourth
/// review of 4 is « 4,3 » there and « 4,2 » here). The re-read that follows a
/// review replaces it (`ProviderProvider.rereadSalonAfterReview`).
///
/// The same arithmetic moves the mock salon in `MockReviewService`, whose
/// seeded figures stand for reviews its list does not hold.
({double rating, int reviewCount}) figuresAfterReview({
  required double rating,
  required int reviewCount,
  required int stars,
  int? replacedStars,
}) {
  // Nothing to replace in a salon that counts no review: it is the first.
  final replaced = reviewCount > 0 ? replacedStars : null;
  final count = replaced == null ? reviewCount + 1 : reviewCount;
  final sum = rating * reviewCount + stars - (replaced ?? 0);
  // One to five stars average between one and five. A replacement computed
  // from a ROUNDED average can leave that range: 19 fives and a four are
  // stored « 5,0 », and the four turned into a five would read « 5,1 ».
  final average = (sum / count).clamp(1.0, 5.0);
  // One decimal, half away from zero — the backend's `_round1`.
  return (rating: (average * 10).round() / 10, reviewCount: count);
}

/// [salons] with [rating] and [reviewCount] carried onto the salon [id] — in
/// place: the same rows, in the same order, every other salon the same object.
///
/// A NEW list when something changed, [salons] itself when nothing did: a
/// list that came from a service is not this caller's to write into, and a
/// listener comparing the list by identity has to see the change.
List<Provider> withSalonFigures(
  List<Provider> salons,
  String id, {
  required double rating,
  required int reviewCount,
}) {
  bool stale(Provider p) =>
      p.id == id && (p.rating != rating || p.reviewCount != reviewCount);
  if (!salons.any(stale)) return salons;
  return [
    for (final p in salons)
      stale(p) ? p.copyWith(rating: rating, reviewCount: reviewCount) : p,
  ];
}
