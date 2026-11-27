/// « Répartition »'s rows on the website: their order (« Trier par ») and
/// their CSV (docs/design/pro-revenue-analytics.md §4.7, §5.1, §13.3, Q10).
/// Pure; unit-tested.

import {
  type RevenueAnalytics,
  type RevenueAxis,
  type RevenueGroup,
  type RevenueRow,
  type RevenueSort,
  dayParts,
} from './revenue';
import { revenueAxisTitle, revenueLabelOf } from './revenue-wording';

/// The rows of [axis] in [group].
export function rowsOf(group: RevenueGroup, axis: RevenueAxis): RevenueRow[] {
  switch (axis) {
    case 'artist':
      return group.byArtist;
    case 'service':
      return group.byService;
    case 'channel':
      return group.byChannel;
  }
}

/// The rows in [sort]'s order. « Montant » is the server's order (amount,
/// then label, then key — a total order, §7.1). Rows at 0 this period
/// (present for the comparison) stay at the bottom whatever the sort, so a
/// collaborateur who dropped to zero is seen (§4.7).
export function sortRevenueRows(
  rows: readonly RevenueRow[],
  axis: RevenueAxis,
  sort: RevenueSort,
): RevenueRow[] {
  const order = new Map(rows.map((r, i) => [r, i]));
  const byServer = (x: RevenueRow, y: RevenueRow) => order.get(x)! - order.get(y)!;
  const live = rows.filter((r) => r.current.completedAmount > 0);
  const zero = rows.filter((r) => r.current.completedAmount <= 0);
  if (sort === 'count') {
    live.sort(
      (x, y) => y.current.completedCount - x.current.completedCount || byServer(x, y),
    );
  } else if (sort === 'name') {
    const byName = (x: RevenueRow, y: RevenueRow) =>
      revenueLabelOf(axis, x).localeCompare(revenueLabelOf(axis, y), 'fr', {
        sensitivity: 'base',
      }) || byServer(x, y);
    live.sort(byName);
    zero.sort(byName);
  }
  return [...live, ...zero];
}

// ── CSV (Q10) ────────────────────────────────────────────────────────────────

/// Opens in Excel as French spreadsheets expect: `;` between fields, a UTF-8
/// byte-order mark (Excel reads accents wrong without it), CRLF lines.
const BOM = String.fromCharCode(0xfeff);
const SEP = ';';
const EOL = '\r\n';

/// One text cell. **A cell that starts like a formula is neutralised** with
/// a leading apostrophe: a collaborateur's or a prestation's name is typed
/// by a member, and « =HYPERLINK(…) » must stay text in the owner's
/// spreadsheet (CSV injection). Quotes when the cell holds `;`, `"` or a
/// line break.
export function csvText(value: string): string {
  const safe = /^[=+\-@\t\r]/.test(value) ? `'${value}` : value;
  return /[;"\r\n]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
}

/// An amount as an integer (XOF and XAF have no minor unit).
function csvAmount(v: number | null | undefined): string {
  return v == null ? '' : String(Math.round(v));
}

/// A share (0–1) as a percentage with two decimals and a French comma.
function csvShare(share: number): string {
  return (Math.round(share * 10000) / 100).toFixed(2).replace('.', ',');
}

export const REVENUE_CSV_HEADER = [
  'Nom',
  'Rendez-vous terminés',
  'Réalisé',
  'Part (%)',
  'Panier moyen',
  'Réalisé sur la période comparée',
  'Devise',
  'Estimé',
];

/// The CSV of [rows] (already in the order on screen) of [group]'s currency.
/// No client name ever leaves in this file (§10): the breakdown tables only.
export function revenueCsv(
  rows: readonly RevenueRow[],
  axis: RevenueAxis,
  group: Pick<RevenueGroup, 'currency'>,
): string {
  const lines = [REVENUE_CSV_HEADER.map(csvText).join(SEP)];
  for (const r of rows) {
    lines.push(
      [
        csvText(revenueLabelOf(axis, r)),
        String(r.current.completedCount),
        csvAmount(r.current.completedAmount),
        csvShare(r.share),
        csvAmount(r.current.averageTicket),
        csvAmount(r.previous?.completedAmount),
        csvText(group.currency),
        r.estimated ? 'oui' : 'non',
      ].join(SEP),
    );
  }
  return `${BOM}${lines.join(EOL)}${EOL}`;
}

/// Lower-case, no accents, words joined by « - »: « Awa Koné » → « awa-kone ».
export function fileSlug(text: string): string {
  return text
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/// « revenus-collaborateurs-2026-11.csv »; a detail adds its name
/// (« revenus-awa-kone-prestations-2026-11.csv »). The period as dates:
/// a month « 2026-11 », a year « 2026 », a day « 2026-11-25 », a week or a
/// range « 2026-11-24_2026-11-30 ».
export function revenueCsvFilename(
  a: Pick<RevenueAnalytics, 'period' | 'from' | 'to'>,
  axis: RevenueAxis,
  detail?: string | null,
): string {
  const { y, m } = dayParts(a.from);
  const period =
    a.period === 'month'
      ? `${y}-${String(m).padStart(2, '0')}`
      : a.period === 'year'
        ? String(y)
        : a.period === 'day'
          ? a.from
          : `${a.from}_${a.to}`;
  const who = detail ? fileSlug(detail) : '';
  const what = fileSlug(revenueAxisTitle(axis));
  return `revenus-${who ? `${who}-` : ''}${what}-${period}.csv`;
}
