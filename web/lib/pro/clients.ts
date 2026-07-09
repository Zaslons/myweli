/// Module `clients` C1b — pure domain helpers for the salon client base
/// (docs/design/clients-c1.md §6). Types mirror the OpenAPI SalonClient*
/// schemas (docs/api/openapi.yaml).

export type SalonClient = {
  id: string;
  displayName: string;
  phone?: string | null;
  tags: string[];
  lastVisitAt?: string | null;
  linked: boolean;
  createdAt: string;
};

export type SalonClientListItem = SalonClient & {
  visits: number;
  noShows: number;
};

export type SalonClientList = {
  items: SalonClientListItem[];
  page: number;
  pageSize: number;
  total: number;
  availableTags?: string[];
};

export type SalonClientStats = {
  visits: number;
  spentFcfa: number;
  noShows: number;
  cancellations: number;
};

export type SalonClientNote = {
  id: string;
  authorName: string;
  body: string;
  createdAt: string;
};

export type SalonClientCard = SalonClient & {
  stats: SalonClientStats;
  upcoming?: { id: string; appointmentDate: string; status: string };
  notes: SalonClientNote[];
};

/// The starter presets (module decision §11.1) — always offered first.
export const PRESET_TAGS = ['VIP', 'Fidèle', 'À risque'];

export const MAX_TAGS = 10;
export const MAX_TAG_LENGTH = 24;
export const MAX_NOTE_LENGTH = 500;

/// « +225 07 •• •• •89 » — full number stays on the card only.
export function maskPhone(phone?: string | null): string {
  if (!phone) return '';
  const digits = phone.replace(/[^0-9]/g, '');
  if (digits.length < 6) return phone;
  const tail = digits.slice(-2);
  const cc = phone.startsWith('+') ? `+${digits.slice(0, 3)} ` : '';
  const head = digits.slice(cc ? 3 : 0, cc ? 5 : 2);
  return `${cc}${head} •• •• •${tail}`;
}

/// Badge policy (module decision §11.3): nothing at 0, neutral at 1, red ≥2.
export function noShowBadge(count?: number | null): 'none' | 'neutral' | 'red' {
  if (!count || count < 1) return 'none';
  return count >= 2 ? 'red' : 'neutral';
}

export function noShowLabel(count: number): string {
  return count === 1 ? '1 absence' : `${count} absences`;
}

export function telHref(phone: string): string {
  return `tel:${phone}`;
}

/// wa.me wants digits only, no plus.
export function waHref(phone: string): string {
  return `https://wa.me/${phone.replace(/[^0-9]/g, '')}`;
}

export function validateTag(tag: string): boolean {
  const t = tag.trim();
  return t.length >= 1 && t.length <= MAX_TAG_LENGTH;
}

/// Toggle a tag in a set, respecting the cap. Returns null when invalid.
export function toggleTag(tags: string[], tag: string): string[] | null {
  const t = tag.trim();
  if (!validateTag(t)) return null;
  if (tags.includes(t)) return tags.filter((x) => x !== t);
  if (tags.length >= MAX_TAGS) return null;
  return [...tags, t];
}
