/// Pure helpers for the account extras (review + favorites). Unit-tested.

import { type Appointment, clientTab, rebookHref } from './appointments';

export function isValidRating(rating: number): boolean {
  return Number.isInteger(rating) && rating >= 1 && rating <= 5;
}

/// Optimistic favorite toggle over a list of provider ids.
export function toggleId(ids: string[], id: string): string[] {
  return ids.includes(id) ? ids.filter((x) => x !== id) : [...ids, id];
}

/// « Réserver à nouveau » (decision 183): any booking that is not upcoming —
/// past, whatever its status, or cancelled — at a salon still open, with its
/// page (`rebookHref` is null for a stopped salon, a salon status this build
/// does not know, or a booking missing its slug). The list under « Passés »
/// and the detail ask this one question, so they cannot disagree.
///
/// A web choice, not parity: the app's detail has no « Réserver à nouveau ».
export function canRebook(a: Appointment, now: Date = new Date()): boolean {
  return clientTab(a, now) !== 'upcoming' && rebookHref(a) !== null;
}

export function canReview(status: string): boolean {
  return status === 'completed';
}
