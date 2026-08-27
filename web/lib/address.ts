/// The address ↔ commune seam (plan « fix/address-commune-dedupe »).
///
/// The owner's own salon page read « marcory, Rue des Nguéssous 93, Marcory »:
/// the Adresse field held the commune (typed in slug casing, echoing the
/// picker just below it), and THREE render sites appended `, {commune}`
/// unconditionally — the visible Localisation line, the FAQ answer (which
/// ships into FAQPage JSON-LD, where it duplicated twice), and PostalAddress
/// `streetAddress` (a genuine structured-data error: `addressLocality`
/// already carries the commune).
///
/// Comparison is by trimmed comma-separated SEGMENT, never substring:
/// « Rue de Marcory » inside Marcory still deserves the append — only an
/// address whose own segment IS the commune already mentions it.

/// Case/accent-insensitive canonical form of one segment.
function canon(s: string): string {
  return s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .trim()
    .toLowerCase();
}

/// Does [address] already carry [commune] as one of its comma segments?
export function addressMentionsCommune(
  address: string | null | undefined,
  commune: string | null | undefined,
): boolean {
  if (!address || !commune) return false;
  const c = canon(commune);
  if (!c) return false;
  return address.split(',').some((seg) => canon(seg) === c);
}

/// The Localisation/FAQ display form: the address, with the commune appended
/// only when the address does not already say it.
export function addressWithCommune(
  address: string | null | undefined,
  commune: string | null | undefined,
): string {
  const a = (address ?? '').trim();
  const c = (commune ?? '').trim();
  if (!a) return c;
  if (!c || addressMentionsCommune(a, c)) return a;
  return `${a}, ${c}`;
}

/// The PostalAddress `streetAddress` form: the address with any LEADING or
/// TRAILING commune segment stripped — `addressLocality` carries the commune,
/// and repeating it inside the street line is a structured-data error. Only
/// the ends are touched: an interior segment is assumed to be real address
/// text, and over-stripping loses data where under-stripping only repeats it.
export function streetAddressWithoutCommune(
  address: string | null | undefined,
  commune: string | null | undefined,
): string | undefined {
  const a = (address ?? '').trim();
  if (!a) return undefined;
  const c = canon(commune ?? '');
  if (!c) return a;
  const segments = a.split(',').map((s) => s.trim());
  while (segments.length > 1 && canon(segments[0]) === c) segments.shift();
  while (segments.length > 1 && canon(segments[segments.length - 1]) === c) {
    segments.pop();
  }
  return segments.join(', ');
}
