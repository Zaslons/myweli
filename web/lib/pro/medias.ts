/// Pure helpers for the pro Médias editors (gallery + before/after). Unit-tested.

export type BeforeAfterPair = {
  before: string;
  after: string;
  caption?: string;
};

export const MAX_GALLERY = 20;
export const MAX_PAIRS = 12;

/// Swap item `i` with its neighbour in `dir` (-1 up / +1 down); no-op at edges.
export function moveItem<T>(arr: T[], i: number, dir: -1 | 1): T[] {
  const j = i + dir;
  if (j < 0 || j >= arr.length) return arr;
  const copy = [...arr];
  [copy[i], copy[j]] = [copy[j], copy[i]];
  return copy;
}

export function removeAt<T>(arr: T[], i: number): T[] {
  return arr.filter((_, idx) => idx !== i);
}

/// « Définir comme photo principale » (gallery-set-cover.md): item `i` jumps
/// to the head — the cover slot — and the rest keep their relative order.
/// No-op at 0 (already the cover) and out of bounds.
export function toCover<T>(arr: T[], i: number): T[] {
  if (i <= 0 || i >= arr.length) return arr;
  return [arr[i], ...arr.filter((_, idx) => idx !== i)];
}

export function canAddPhoto(photos: string[]): boolean {
  return photos.length < MAX_GALLERY;
}

export function canAddPair(pairs: BeforeAfterPair[]): boolean {
  return pairs.length < MAX_PAIRS;
}
