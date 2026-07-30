/// Pure helpers for the pro Profil edit form. Unit-tested.

const E164 = /^\+[1-9]\d{7,14}$/; // mirrors backend isValidE164

export const PROFILE_CATEGORIES = [
  { key: 'salon', label: 'Salon de coiffure' },
  { key: 'barber', label: 'Barbier' },
  { key: 'spa', label: 'Spa' },
  { key: 'nails', label: 'Onglerie' },
  { key: 'massage', label: 'Massage & bien-être' },
] as const;

export type ProviderProfile = {
  name?: string;
  description?: string;
  address?: string;
  commune?: string | null;
  city?: string | null;
  /// Multi-pays MP1: the locality-tree area the salon points at.
  areaId?: string | null;
  phoneNumber?: string;
  whatsapp?: string | null;
  category?: string;
  latitude?: number | null;
  longitude?: number | null;
};

export type ProfileForm = {
  name: string;
  description: string;
  address: string;
  /// The picked locality area (multi-pays MP3) — the server derives
  /// commune/city/timezone/currency from it (T57).
  areaId: string | null;
  /// Free-text fallback, used ONLY when the locality tree is unavailable
  /// (the backend self-heals names to areas).
  commune: string;
  city: string;
  phoneNumber: string;
  whatsapp: string;
  category: string;
  /// The map pin (pro-salon-lifecycle L1) — PAIRED, saved only when placed.
  latitude: number | null;
  longitude: number | null;
};

export function profileToForm(p?: ProviderProfile): ProfileForm {
  return {
    name: p?.name ?? '',
    description: p?.description ?? '',
    address: p?.address ?? '',
    areaId: p?.areaId ?? null,
    commune: p?.commune ?? '',
    city: p?.city ?? '',
    phoneNumber: p?.phoneNumber ?? '',
    whatsapp: p?.whatsapp ?? '',
    category: p?.category ?? 'salon',
    latitude: p?.latitude ?? null,
    longitude: p?.longitude ?? null,
  };
}

export function validateProfile(f: ProfileForm): string | null {
  if (!f.name.trim()) return 'Le nom est requis.';
  if (!E164.test(f.phoneNumber.trim())) {
    return 'Téléphone invalide (format international, ex. +2250700000000).';
  }
  if (f.whatsapp.trim() && !E164.test(f.whatsapp.trim())) {
    return 'WhatsApp invalide (format international).';
  }
  return null;
}

/// Allowlisted editable fields; empty optionals → null. The pin rides along
/// only once placed (the backend requires the pair). An areaId REPLACES the
/// name fields (the server derives the display names — sending both would
/// just be overwritten); the free-text commune is the tree-down fallback.
export function buildProfilePayload(f: ProfileForm): Record<string, unknown> {
  return {
    name: f.name.trim(),
    description: f.description.trim(),
    address: f.address.trim(),
    ...(f.areaId
      ? { areaId: f.areaId }
      : {
          commune: f.commune.trim() || null,
          city: f.city.trim() || null,
        }),
    phoneNumber: f.phoneNumber.trim(),
    whatsapp: f.whatsapp.trim() || null,
    category: f.category,
    ...(f.latitude != null && f.longitude != null
      ? { latitude: f.latitude, longitude: f.longitude }
      : {}),
  };
}
