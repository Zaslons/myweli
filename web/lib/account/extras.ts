/// Pure helpers for the account extras (review + favorites). Unit-tested.

export function isValidRating(rating: number): boolean {
  return Number.isInteger(rating) && rating >= 1 && rating <= 5;
}

/// Optimistic favorite toggle over a list of provider ids.
export function toggleId(ids: string[], id: string): string[] {
  return ids.includes(id) ? ids.filter((x) => x !== id) : [...ids, id];
}

/// Past/terminal bookings can be re-booked ("Réserver à nouveau").
export function canRebook(status: string): boolean {
  return (
    status === 'completed' || status === 'cancelled' || status === 'noShow'
  );
}

export function canReview(status: string): boolean {
  return status === 'completed';
}
