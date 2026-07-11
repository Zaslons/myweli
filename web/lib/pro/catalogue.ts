/// Pure helpers for the pro service form. Unit-tested.

/// Audit 3.2: per-hair-length durations (minutes) — {} = no variants.
export type DurationVariants = { court?: number; moyen?: number; long?: number };

export type Service = {
  id: string;
  name: string;
  description?: string;
  price?: number;
  priceMax?: number | null;
  durationMinutes?: number;
  active?: boolean;
  /// Audit 3.1: who can perform it — empty = toute l'équipe.
  artistIds?: string[];
  durationVariants?: DurationVariants;
};

export type ServiceInput = {
  name: string;
  description: string;
  price: number;
  priceMax: number | null;
  durationMinutes: number;
  active: boolean;
  artistIds: string[];
  durationVariants: DurationVariants;
};

export type ServiceForm = {
  name: string;
  description: string;
  price: string;
  priceMax: string;
  durationMinutes: string;
  active: boolean;
  artistIds: string[];
  /// The app's toggle: off saves {} (clears); on saves only the filled keys.
  hasVariants: boolean;
  variantCourt: string;
  variantMoyen: string;
  variantLong: string;
};

export const emptyServiceForm: ServiceForm = {
  name: '',
  description: '',
  price: '',
  priceMax: '',
  durationMinutes: '',
  active: true,
  artistIds: [],
  hasVariants: false,
  variantCourt: '',
  variantMoyen: '',
  variantLong: '',
};

export function serviceToForm(s: Service): ServiceForm {
  const v = s.durationVariants ?? {};
  const hasVariants = v.court != null || v.moyen != null || v.long != null;
  return {
    name: s.name ?? '',
    description: s.description ?? '',
    price: s.price != null ? String(s.price) : '',
    priceMax: s.priceMax != null ? String(s.priceMax) : '',
    durationMinutes: s.durationMinutes != null ? String(s.durationMinutes) : '',
    active: s.active ?? true,
    artistIds: s.artistIds ?? [],
    hasVariants,
    variantCourt: v.court != null ? String(v.court) : '',
    variantMoyen: v.moyen != null ? String(v.moyen) : '',
    variantLong: v.long != null ? String(v.long) : '',
  };
}

/// Returns a French error message, or null when valid (mirrors the app's rules).
export function validateService(f: ServiceForm): string | null {
  if (!f.name.trim()) return 'Le nom est requis.';
  const price = Number(f.price);
  if (!f.price.trim() || Number.isNaN(price) || price <= 0) {
    return 'Le prix de départ est requis.';
  }
  if (f.priceMax.trim()) {
    const max = Number(f.priceMax);
    if (Number.isNaN(max)) return 'Prix maximum invalide.';
    if (max < price) return 'Le prix maximum doit être ≥ au prix de départ.';
  }
  const dur = Number(f.durationMinutes);
  if (!f.durationMinutes.trim() || Number.isNaN(dur) || dur <= 0) {
    return 'La durée est requise.';
  }
  return null;
}

/// Mirrors the app's parser: blank/invalid/≤0 minute fields are omitted.
function parseVariant(text: string): number | undefined {
  const n = Number(text.trim());
  return text.trim() && Number.isInteger(n) && n > 0 ? n : undefined;
}

export function buildServicePayload(f: ServiceForm): ServiceInput {
  const variants: DurationVariants = f.hasVariants
    ? {
        ...(parseVariant(f.variantCourt) != null
          ? { court: parseVariant(f.variantCourt) }
          : {}),
        ...(parseVariant(f.variantMoyen) != null
          ? { moyen: parseVariant(f.variantMoyen) }
          : {}),
        ...(parseVariant(f.variantLong) != null
          ? { long: parseVariant(f.variantLong) }
          : {}),
      }
    : {};
  return {
    name: f.name.trim(),
    description: f.description.trim(),
    price: Number(f.price),
    priceMax: f.priceMax.trim() ? Number(f.priceMax) : null,
    durationMinutes: Number(f.durationMinutes),
    active: f.active,
    artistIds: f.artistIds,
    durationVariants: variants,
  };
}

// --- artistes (équipe, 7.3b) -------------------------------------------------

export type Artist = {
  id: string;
  name: string;
  specialization?: string | null;
  /// Audit 3.4: per-staff weekly hours — {} = inherits the salon's.
  workingHours?: Record<string, { startTime: string; endTime: string }[]>;
};

export type ArtistInput = {
  name: string;
  specialization: string | null;
  workingHours: Record<string, { startTime: string; endTime: string }[]>;
};

export type ArtistForm = {
  name: string;
  specialization: string;
  workingHours: Record<string, { startTime: string; endTime: string }[]>;
};

export const emptyArtistForm: ArtistForm = {
  name: '',
  specialization: '',
  workingHours: {},
};

export function artistToForm(a: Artist): ArtistForm {
  return {
    name: a.name ?? '',
    specialization: a.specialization ?? '',
    workingHours: a.workingHours ?? {},
  };
}

export function validateArtist(f: ArtistForm): string | null {
  if (!f.name.trim()) return 'Le nom est requis.';
  return null;
}

export function buildArtistPayload(f: ArtistForm): ArtistInput {
  return {
    name: f.name.trim(),
    specialization: f.specialization.trim() ? f.specialization.trim() : null,
    workingHours: f.workingHours,
  };
}
