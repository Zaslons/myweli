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

/// Puts [item] back at [i] in the list AS IT IS NOW (clamped): the undo of
/// one delete, never a snapshot restored (SYSTEM §15).
export function insertAt<T>(arr: T[], i: number, item: T): T[] {
  const at = Math.max(0, Math.min(i, arr.length));
  return [...arr.slice(0, at), item, ...arr.slice(at)];
}

export function canAddPhoto(photos: string[]): boolean {
  return photos.length < MAX_GALLERY;
}

// ---- several photos at once — docs/design/gallery-multi-select.md ---------

/// What fits of a multi-photo pick: the FIRST ones in the order picked, up to
/// the room left under [MAX_GALLERY]; `dropped` is how many did not fit.
export function fitInGallery<T>(picked: T[], current: number): { kept: T[]; dropped: number } {
  const room = Math.max(0, MAX_GALLERY - current);
  return { kept: picked.slice(0, room), dropped: Math.max(0, picked.length - room) };
}

/// « 20 photos maximum : 3 photos n’ont pas été ajoutées. » (§2.4)
export function overCapMessage(dropped: number): string {
  return dropped === 1
    ? `${MAX_GALLERY} photos maximum : 1 photo n’a pas été ajoutée.`
    : `${MAX_GALLERY} photos maximum : ${dropped} photos n’ont pas été ajoutées.`;
}

/// Why one photo of a batch did not make it — an upload's reason, or `failed`
/// for a save the server refused.
export type BatchFailure = 'unreadable' | 'too_large' | 'blocked' | 'failed';

/// The hint when EVERY photo of a batch failed for the same reason the pro can
/// act on (the batch twin of `uploadFailureMessage`'s three sentences).
const SHARED_HINT: Partial<Record<BatchFailure, string>> = {
  unreadable: 'Choisissez des images JPEG, PNG ou WebP.',
  too_large: 'Choisissez des images plus petites.',
  blocked: 'Essayez avec un autre navigateur.',
};

const photosWord = (n: number) => (n === 1 ? '1 photo' : `${n} photos`);

/// The one message at the end of a multi-photo add (§2.4), or null for a batch
/// of one — which keeps today's messages, unchanged.
export function batchSummary(input: {
  total: number;
  added: number;
  failures: BatchFailure[];
  dropped?: number;
}): { message: string; kind: 'success' | 'error' } | null {
  const { total, added, failures, dropped = 0 } = input;
  if (total < 2) return null;
  const capNote = dropped > 0 ? ` ${overCapMessage(dropped)}` : '';
  if (added === total) {
    return { message: `${photosWord(added)} ajoutées.${capNote}`, kind: 'success' };
  }
  if (added === 0) {
    const shared = failures.length > 0 && failures.every((f) => f === failures[0]);
    const hint = shared ? SHARED_HINT[failures[0]] : undefined;
    return {
      message: `Aucune photo n’a pu être envoyée.${hint ? ` ${hint}` : ''}${capNote}`,
      kind: 'error',
    };
  }
  const failed = total - added;
  const added_ = added === 1 ? '1 photo ajoutée' : `${added} photos ajoutées`;
  const failed_ =
    failed === 1 ? '1 n’a pas pu être envoyée.' : `${failed} n’ont pas pu être envoyées.`;
  return { message: `${added_} sur ${total}. ${failed_}${capNote}`, kind: 'error' };
}

export function canAddPair(pairs: BeforeAfterPair[]): boolean {
  return pairs.length < MAX_PAIRS;
}
