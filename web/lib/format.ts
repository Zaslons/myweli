// FR/CI formatting helpers (mirror the app's core/utils formatters).
// Design: docs/design/timezone-salon-time.md — dates/times render in SALON
// time via lib/time.ts, never the browser's zone.

import { SALON_TZ, salonFormatter } from './time';

const fcfa = new Intl.NumberFormat('fr-FR');

/// « 0 visite » · « 1 visite » · « 2 visites » — a count and its noun (A13).
///
/// The web twin of `Formatters.count` (mobile `core/utils/formatters.dart`),
/// and it exists for the same one fact: **French puts 0 in the SINGULAR.**
/// A13's sweep found mobile had grown four idioms that disagree at exactly that
/// value; the same slice's review found the web claim "every web site already
/// uses `> 1`" was false — `JournalPanel` hard-coded « visites »/« absences »
/// unguarded, so a client with one visit read « 1 visites ».
///
/// `Intl.PluralRules('fr')` rather than a ternary, so CLDR owns the rule and
/// the locale is named rather than inherited.
const frPlural = new Intl.PluralRules('fr-FR');

export function countFr(n: number, one: string, other: string): string {
  return `${n} ${frPlural.select(n) === 'one' ? one : other}`;
}

/// XOF and XAF (the two CFA francs) both read « FCFA » — the colloquial name
/// across the zone (docs/modules/multi-pays.md §4); any other ISO code
/// renders as itself. Defaults to XOF (Côte d'Ivoire).
export function formatFcfa(amount: number, currency = 'XOF'): string {
  const suffix = currency === 'XOF' || currency === 'XAF' ? 'FCFA' : currency;
  return `${fcfa.format(Math.round(amount))} ${suffix}`;
}

/// "15 000 – 25 000 FCFA" when a max is set above the base, else "15 000 FCFA".
export function priceRange(
  price: number,
  priceMax?: number | null,
  currency = 'XOF',
): string {
  if (priceMax != null && priceMax > price) {
    return `${fcfa.format(Math.round(price))} – ${formatFcfa(priceMax, currency)}`;
  }
  return formatFcfa(price, currency);
}

/// "1 h 30" · "2 h" · "45 min".
export function formatDuration(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m} min`;
  return m === 0 ? `${h} h` : `${h} h ${m.toString().padStart(2, '0')}`;
}

/// Date (e.g. "1 décembre 2026"), in SALON time.
export function formatDateFr(iso: string, tz: string = SALON_TZ): string {
  return salonFormatter(
    { day: 'numeric', month: 'long', year: 'numeric' },
    tz,
  ).format(new Date(iso));
}

/// Date + time (e.g. "1 décembre 2026 à 09:00"), in SALON time.
export function formatDateTimeFr(iso: string, tz: string = SALON_TZ): string {
  const d = new Date(iso);
  const date = salonFormatter(
    { day: 'numeric', month: 'long', year: 'numeric' },
    tz,
  ).format(d);
  const time = salonFormatter({ hour: '2-digit', minute: '2-digit' }, tz).format(
    d,
  );
  return `${date} à ${time}`;
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
