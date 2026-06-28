// FR/CI formatting helpers (mirror the app's core/utils formatters).

const fcfa = new Intl.NumberFormat('fr-FR');

export function formatFcfa(amount: number): string {
  return `${fcfa.format(Math.round(amount))} FCFA`;
}

/// "15 000 – 25 000 FCFA" when a max is set above the base, else "15 000 FCFA".
export function priceRange(price: number, priceMax?: number | null): string {
  if (priceMax != null && priceMax > price) {
    return `${fcfa.format(Math.round(price))} – ${formatFcfa(priceMax)}`;
  }
  return formatFcfa(price);
}

/// "1 h 30" · "2 h" · "45 min".
export function formatDuration(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m} min`;
  return m === 0 ? `${h} h` : `${h} h ${m.toString().padStart(2, '0')}`;
}

export function formatDateFr(iso: string): string {
  const d = new Date(iso);
  return new Intl.DateTimeFormat('fr-FR', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  }).format(d);
}

/// Weekly-schedule keys are "0".."6" = Mon..Sun.
export const weekdaysFr = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
] as const;
