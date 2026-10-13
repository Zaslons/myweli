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

/// « +225 07 00 00 01 01 » — a stored number, for reading.
///
/// The hand-written twin of `Formatters.formatPhoneNumber` (mobile
/// `core/utils/formatters.dart`), same rule line for line: a Côte d'Ivoire
/// number — `+225` followed by exactly 10 national digits (today's plan) or 8
/// (the legacy one) — is grouped in pairs; **every other input is returned
/// unchanged**, as the very string that came in. Another country (« +241… »,
/// Gabon, is a live market), a wrong length, a number without its prefix: all
/// stay as stored. That is why this is not `formatPhoneNumberIntl` from
/// `react-phone-number-input` — a library that formats every country is a
/// different rule from the app's.
///
/// - **For display only.** `tel:` and `wa.me` links, and anything sent to the
///   API, keep the stored number (`telHref` / `waHref` in `lib/pro/clients.ts`).
/// - **The gaps are plain spaces (U+0020)**, as in the app, so a copied number
///   pastes with ordinary spaces. A phone number may not break across lines
///   (SYSTEM.md §13.3); that is the caller's job, with `whitespace-nowrap` —
///   never a no-break space in the string.
/// - The cleaning expression is the app's, `[^\d+]` and not `\D`: it keeps a
///   `+` wherever it sits, exactly as the Dart does.
///
/// Nothing but the shared test vectors (`tests/format.test.ts` ↔
/// `mobile/test/unit/formatters_test.dart`) holds the two copies together.
export function formatPhoneNumber(phone: string): string {
  const cleaned = phone.replace(/[^\d+]/g, '');
  if (cleaned.startsWith('+225')) {
    const digits = cleaned.slice(4); // strip +225
    if (digits.length === 10 || digits.length === 8) {
      const groups: string[] = [];
      for (let i = 0; i < digits.length; i += 2) {
        groups.push(digits.slice(i, i + 2));
      }
      return `+225 ${groups.join(' ')}`;
    }
  }
  return phone; // other country / unexpected length → as-is
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
