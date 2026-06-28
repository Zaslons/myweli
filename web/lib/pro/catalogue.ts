/// Pure helpers for the pro service form. Unit-tested.

export type Service = {
  id: string;
  name: string;
  description?: string;
  price?: number;
  priceMax?: number | null;
  durationMinutes?: number;
  active?: boolean;
};

export type ServiceInput = {
  name: string;
  description: string;
  price: number;
  priceMax: number | null;
  durationMinutes: number;
  active: boolean;
};

export type ServiceForm = {
  name: string;
  description: string;
  price: string;
  priceMax: string;
  durationMinutes: string;
  active: boolean;
};

export const emptyServiceForm: ServiceForm = {
  name: '',
  description: '',
  price: '',
  priceMax: '',
  durationMinutes: '',
  active: true,
};

export function serviceToForm(s: Service): ServiceForm {
  return {
    name: s.name ?? '',
    description: s.description ?? '',
    price: s.price != null ? String(s.price) : '',
    priceMax: s.priceMax != null ? String(s.priceMax) : '',
    durationMinutes: s.durationMinutes != null ? String(s.durationMinutes) : '',
    active: s.active ?? true,
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

export function buildServicePayload(f: ServiceForm): ServiceInput {
  return {
    name: f.name.trim(),
    description: f.description.trim(),
    price: Number(f.price),
    priceMax: f.priceMax.trim() ? Number(f.priceMax) : null,
    durationMinutes: Number(f.durationMinutes),
    active: f.active,
  };
}
