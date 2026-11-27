import { describe, expect, it } from 'vitest';
import {
  type RevenueAnalytics,
  type RevenueRow,
  addRevenueDays,
  customRangeError,
  formatDayRange,
  formatLedgerWhen,
  formatPeriodDay,
  isRevenueDay,
  nextRevenuePeriod,
  previousRevenuePeriod,
  provisionalRevenueTitle,
  readRevenueAddress,
  revenueApiParams,
  revenueComparisonLabel,
  revenueDetailHref,
  revenueHasFuture,
  revenueIsFuture,
  revenueLedgerHref,
  revenuePeriodTitle,
  revenueQuery,
  revenueSearch,
  switchRevenuePeriod,
} from '../lib/pro/revenue';
import { forwardRevenueParams } from '../lib/pro/revenue-bff';
import { readRevenueAnalytics, readRevenueLedger } from '../lib/pro/revenue-read';
import {
  csvText,
  revenueCsv,
  revenueCsvFilename,
  sortRevenueRows,
} from '../lib/pro/revenue-rows';
import {
  REVENUE_PRICE_FOOTNOTE,
  formatPercent,
  revenueAbsences,
  revenueDelta,
  revenueLedgerLine,
  revenueRateDelta,
  revenueRowLabel,
  revenueToCloseTitle,
} from '../lib/pro/revenue-wording';
import { analytics, ledger, ledgerRow, r2, row } from './revenue-fixtures';

/// docs/design/pro-revenue-analytics.md §3, §5.2, §13.3, §22 — the website's
/// pure half of « Revenus »: the address, the calendar stepped from the
/// answer, the words, the CSV, and the strict reading of the server's
/// answers (the R2 server's own, `tests/revenue-r2/`).

const NNBSP = String.fromCharCode(0x202f);
const NBSP = String.fromCharCode(0x00a0);

function answer(over: Record<string, unknown> = {}): RevenueAnalytics {
  const a = readRevenueAnalytics(analytics(over));
  if (!a) throw new Error('fixture unreadable');
  return a;
}

describe('the address (§5.2)', () => {
  const TODAY = '2026-11-27';

  it('a bare address is the current month, the session’s comparison', () => {
    const a = readRevenueAddress('', TODAY);
    expect(a).toMatchObject({ period: 'month', date: null, compare: null, tab: null, sort: 'amount' });
    expect(revenueSearch(a)).toBe('');
  });

  it('round-trips every word, in French without accents', () => {
    const search =
      '?periode=semaine&date=2026-11-24&comparer=annee&vue=prestations&tri=nom' +
      '&collaborateur=artist_awa&canal=en-ligne&statut=a-cloturer&instant=2026-11-27T09%3A05%3A53.900Z&salon=p1';
    const a = readRevenueAddress(search, TODAY);
    expect(a).toMatchObject({
      period: 'week',
      date: '2026-11-24',
      compare: 'year',
      tab: 'service',
      sort: 'name',
      artistId: 'artist_awa',
      channel: 'online',
      status: 'toClose',
      asOf: '2026-11-27T09:05:53.900Z',
      salon: 'p1',
    });
    expect(revenueSearch(a)).toBe(search);
  });

  it('never writes a default', () => {
    expect(
      revenueSearch({ period: 'month', compare: 'previous', sort: 'amount', status: 'completed' }),
    ).toBe('');
  });

  it.each([
    ['?periode=trimestre', 'an unknown period'],
    ['?periode=jour&date=2026-02-30', 'a date that is not a day'],
    ['?periode=jour&date=2019-12-31', 'before 2020'],
    ['?periode=jour&date=2027-11-29', 'past today + 366 days'],
    ['?periode=dates&du=2026-11-10&au=2026-11-01', 'a range backwards'],
    ['?periode=dates&du=2025-01-01&au=2026-01-02', 'a range of 367 days'],
    ['?periode=dates&du=2026-11-01', 'a range without its end'],
  ])('%s (%s) falls back to the current month, without an error', (search) => {
    const a = readRevenueAddress(search, TODAY);
    expect(a.period).toBe('month');
    expect(a.date).toBeNull();
    expect(a.from).toBeNull();
  });

  it('keeps a range of exactly 366 days, and today + 366', () => {
    expect(readRevenueAddress('?periode=dates&du=2025-01-01&au=2026-01-01', TODAY).period).toBe('custom');
    expect(readRevenueAddress('?periode=jour&date=2027-11-28', TODAY).date).toBe('2027-11-28');
  });

  it('drops an id the server would refuse, and a prototype word', () => {
    const a = readRevenueAddress('?collaborateur=a%20b&prestation=__proto__x%3B&canal=toString&vue=constructor', TODAY);
    expect(a.artistId).toBeNull();
    expect(a.serviceId).toBeNull();
    expect(a.channel).toBeNull();
    expect(a.tab).toBeNull();
  });

  it('a detail’s path is literal French, the period in the query', () => {
    const q = revenueQuery({ period: 'week', date: '2026-11-24', compare: 'year' });
    expect(revenueDetailHref('artist', null, q, 'p1')).toBe(
      '/pro/revenus/collaborateurs/none?periode=semaine&date=2026-11-24&comparer=annee&salon=p1',
    );
    expect(revenueDetailHref('channel', 'online', q, 'p1')).toBe(
      '/pro/revenus/canaux/en-ligne?periode=semaine&date=2026-11-24&comparer=annee&salon=p1',
    );
    // A detail inside a detail: the parent's filter rides in the query.
    expect(
      revenueDetailHref('service', 'service_tresses', { ...q, artistId: 'artist_awa' }, 'p1'),
    ).toBe(
      '/pro/revenus/prestations/service_tresses?periode=semaine&date=2026-11-24&comparer=annee&collaborateur=artist_awa&salon=p1',
    );
  });

  it('the ledger carries every filter, the status and the figures’ instant', () => {
    const q = revenueQuery({ serviceId: 'service_tresses' });
    expect(revenueLedgerHref(q, 'toClose', 'p1', '2026-11-27T09:05:53.900Z')).toBe(
      '/pro/revenus/rendez-vous?prestation=service_tresses&statut=a-cloturer&instant=2026-11-27T09%3A05%3A53.900Z&salon=p1',
    );
  });

  it('asks the server with its own words; no date means the server’s today', () => {
    expect(revenueApiParams(revenueQuery()).toString()).toBe('period=month&compare=previous');
    expect(
      revenueApiParams(
        revenueQuery({ period: 'custom', from: '2026-10-01', to: '2026-11-27', channel: 'web' }),
      ).toString(),
    ).toBe('period=custom&from=2026-10-01&to=2026-11-27&compare=previous&channel=web');
  });
});

describe('the BFF forwards §7’s parameters and nothing else', () => {
  it('analytics', () => {
    const p = new URLSearchParams('providerId=p1&period=month&compare=year&artistId=a&status=x&page=2&evil=1');
    expect(forwardRevenueParams(p, 'analytics')).toBe('?period=month&compare=year&artistId=a');
  });
  it('ledger: no comparison, pages', () => {
    const p = new URLSearchParams('providerId=p1&period=month&compare=year&status=toClose&page=2&pageSize=20&asOf=x&evil=1');
    expect(forwardRevenueParams(p, 'ledger')).toBe('?period=month&status=toClose&page=2&pageSize=20&asOf=x');
  });
});

describe('the calendar, stepped from the answer (§3.5, §4.3)', () => {
  const q = revenueQuery();

  it('days, a calendar’s', () => {
    expect(isRevenueDay('2028-02-29')).toBe(true);
    expect(isRevenueDay('2026-02-29')).toBe(false);
    expect(addRevenueDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addRevenueDays('2026-03-01', -1)).toBe('2026-02-28');
  });

  it('‹ › by kind', () => {
    const month = answer();
    expect(previousRevenuePeriod(month, q)).toMatchObject({ period: 'month', date: '2026-10-01' });
    expect(nextRevenuePeriod(month, q)).toMatchObject({ period: 'month', date: '2026-12-01' });
    const week = answer({ period: 'week', from: '2026-11-23', to: '2026-11-29' });
    expect(previousRevenuePeriod(week, q)).toMatchObject({ period: 'week', date: '2026-11-16' });
    const year = answer({ period: 'year', from: '2026-01-01', to: '2026-12-31' });
    expect(previousRevenuePeriod(year, q)).toMatchObject({ period: 'year', date: '2025-01-01' });
    const day = answer({ period: 'day', from: '2026-11-27', to: '2026-11-27' });
    expect(nextRevenuePeriod(day, q)).toMatchObject({ period: 'day', date: '2026-11-28' });
  });

  it('a range steps by its own length', () => {
    const custom = answer({ period: 'custom', from: '2026-10-01', to: '2026-10-10' });
    expect(previousRevenuePeriod(custom, q)).toMatchObject({
      period: 'custom',
      from: '2026-09-21',
      to: '2026-09-30',
      date: null,
    });
    expect(nextRevenuePeriod(custom, q)).toMatchObject({ from: '2026-10-11', to: '2026-10-20' });
  });

  it('‹ stops at 2020; a week straddling it is asked by its first valid day', () => {
    const jan2020 = answer({ period: 'month', from: '2020-01-01', to: '2020-01-31' });
    expect(previousRevenuePeriod(jan2020, q)).toBeNull();
    const week = answer({ period: 'week', from: '2020-01-06', to: '2020-01-12' });
    expect(previousRevenuePeriod(week, q)).toMatchObject({ date: '2020-01-01' });
  });

  it('› stops at the salon’s today + 366 days (the answer’s today, not the device’s)', () => {
    const far = answer({ period: 'day', from: '2027-11-28', to: '2027-11-28', inProgress: false });
    expect(nextRevenuePeriod(far, q)).toBeNull();
    const before = answer({ period: 'day', from: '2027-11-27', to: '2027-11-27', inProgress: false });
    expect(nextRevenuePeriod(before, q)).toMatchObject({ date: '2027-11-28' });
  });

  it('another kind keeps « now » in progress, else the period’s first day', () => {
    expect(switchRevenuePeriod(answer(), q, 'week')).toMatchObject({ period: 'week', date: null });
    const past = answer({ from: '2026-09-01', to: '2026-09-30', inProgress: false });
    expect(switchRevenuePeriod(past, q, 'week')).toMatchObject({ period: 'week', date: '2026-09-01' });
  });

  it('« Dates… »: 366 days at most, never backwards', () => {
    expect(customRangeError('2025-01-01', '2026-01-01')).toBeNull();
    expect(customRangeError('2025-01-01', '2026-01-02')).toBe('366 jours au plus');
    expect(customRangeError('2026-11-10', '2026-11-01')).toBe(
      'La date de fin précède la date de début',
    );
  });

  it('past, present and future (« Prévu » shows from today on)', () => {
    expect(revenueHasFuture(answer())).toBe(true);
    expect(revenueHasFuture(answer({ from: '2026-10-01', to: '2026-10-31', inProgress: false }))).toBe(false);
    expect(revenueIsFuture(answer({ from: '2026-12-01', to: '2026-12-31', inProgress: false }))).toBe(true);
  });
});

describe('the words of a period (§4.3, §21.1 item 9)', () => {
  it('titles', () => {
    expect(revenuePeriodTitle(answer())).toBe('Novembre 2026');
    expect(revenuePeriodTitle(answer({ period: 'week', from: '2026-11-23', to: '2026-11-29' }))).toBe(
      '23 – 29 nov. 2026',
    );
    expect(revenuePeriodTitle(answer({ period: 'year', from: '2026-01-01', to: '2026-12-31' }))).toBe('2026');
    expect(revenuePeriodTitle(answer({ period: 'day', from: '2026-11-25', to: '2026-11-25' }))).toBe(
      'Mercredi 25 novembre',
    );
    expect(formatPeriodDay('2025-11-24', 2026)).toBe('Lundi 24 novembre 2025');
    expect(formatDayRange('2026-10-03', '2026-11-25')).toBe('3 oct. – 25 nov. 2026');
    expect(formatDayRange('2025-12-29', '2026-01-04')).toBe('29 déc. 2025 – 4 janv. 2026');
    expect(formatDayRange('2026-11-01', '2026-11-01')).toBe('1er nov. 2026');
  });

  it('a provisional title from the query, so the bar changes at once', () => {
    expect(provisionalRevenueTitle(revenueQuery({ period: 'week', date: '2026-11-27' }), null)).toBe(
      '23 – 29 nov. 2026',
    );
    expect(provisionalRevenueTitle(revenueQuery(), '2026-11-27')).toBe('Novembre 2026');
    expect(provisionalRevenueTitle(revenueQuery(), null)).toBeNull();
  });

  it('the comparison, in words', () => {
    expect(revenueComparisonLabel(answer())).toBe('1er – 27 oct. 2026, même avancement');
    expect(
      revenueComparisonLabel(
        answer({
          comparison: { mode: 'previous', from: '2026-10-01', to: '2026-10-31', likeForLike: false, cutoff: null },
        }),
      ),
    ).toBe('octobre 2026');
    expect(
      revenueComparisonLabel(
        answer({
          comparison: { mode: 'year', from: '2025-01-01', to: '2025-12-31', likeForLike: false, cutoff: null },
        }),
      ),
    ).toBe('2025');
    expect(
      revenueComparisonLabel(
        answer({ comparison: { mode: 'none', from: null, to: null, likeForLike: false, cutoff: null } }),
      ),
    ).toBeNull();
  });

  it('a booking’s start in the salon’s time', () => {
    expect(formatLedgerWhen('2026-11-25T14:30:00.000Z', 'Africa/Abidjan')).toBe('mer. 25 nov. · 14:30');
    // Libreville is UTC+1: 23:30 UTC is the next salon day.
    expect(formatLedgerWhen('2026-11-25T23:30:00.000Z', 'Africa/Libreville')).toBe('jeu. 26 nov. · 00:30');
  });
});

describe('labels (§3.3), row by row', () => {
  const label = (axis: 'artist' | 'service' | 'channel', key: string | null, l: string | null, state: RevenueRow['state']) =>
    revenueRowLabel(axis, { key, label: l, state });

  it.each([
    ['artist', 'artist_awa', 'Awa Koné', 'active', 'Awa Koné'],
    ['artist', 'artist_x', 'Konan Serge', 'removed', 'Konan Serge · a quitté l’équipe'],
    ['artist', 'artist_x', null, 'removed', 'Ancien collaborateur'],
    ['artist', null, null, 'unassigned', 'Sans collaborateur attribué'],
    ['artist', 'none', null, 'active', 'Sans collaborateur attribué'],
    ['service', 'service_t', 'Tresses', 'active', 'Tresses'],
    ['service', 'service_n', 'Nattes', 'removed', 'Nattes · prestation supprimée'],
    ['service', 'service_n', null, 'removed', 'Prestation supprimée'],
    ['channel', 'app', null, 'active', 'Application MyWeli'],
    ['channel', 'web', null, 'active', 'Site MyWeli'],
    ['channel', 'salon', null, 'active', 'Ajouté par le salon'],
    ['channel', 'online', null, 'legacy', 'En ligne (avant le suivi)'],
  ] as const)('%s %s %s %s → %s', (axis, key, l, state, expected) => {
    expect(label(axis, key, l, state)).toBe(expected);
  });
});

describe('deltas (§3.6)', () => {
  it('a percent, the sign and the sentence', () => {
    expect(revenueDelta(112, 100, 'octobre 2026')).toEqual({
      text: `+12${NNBSP}%`,
      spoken: `en hausse de 12${NNBSP}% par rapport à octobre 2026`,
      tone: 'good',
      up: true,
    });
    expect(revenueDelta(92, 100)).toMatchObject({ text: `−8${NNBSP}%`, tone: 'bad', up: false });
    expect(revenueDelta(100.2, 100)).toMatchObject({ text: 'stable', tone: 'neutral', up: null });
    expect(revenueDelta(5, 0)).toMatchObject({ text: 'nouveau', up: true });
    expect(revenueDelta(0, 0)).toBeNull();
    expect(revenueDelta(5, null)).toBeNull();
  });

  it('a range is « la période … »', () => {
    expect(revenueDelta(112, 100, '1er – 27 oct. 2026, même avancement')?.spoken).toBe(
      `en hausse de 12${NNBSP}% par rapport à la période 1er – 27 oct. 2026, même avancement`,
    );
  });

  it('half rounds away from zero, as the app (−2,5 % → −3 %)', () => {
    expect(revenueDelta(97.5, 100)?.text).toBe(`−3${NNBSP}%`);
    expect(revenueDelta(102.5, 100)?.text).toBe(`+3${NNBSP}%`);
  });

  it('« Taux d’absence » in points; up is bad', () => {
    expect(revenueRateDelta(0.059, 0.071)).toMatchObject({ text: '−1,2 pt', tone: 'good', up: false });
    expect(revenueRateDelta(0.1, 0.05)?.spoken).toBe('en hausse de 5,0 points');
    expect(revenueRateDelta(null, 0.05)).toBeNull();
  });

  it('percentages keep their sign on the number’s line', () => {
    expect(formatPercent(0.059, 1)).toBe(`5,9${NNBSP}%`);
  });
});

describe('counts and the ledger line (§4.13)', () => {
  it('French puts 0 in the singular', () => {
    expect(revenueAbsences(0)).toBe(`0${NBSP}absence`);
    expect(revenueToCloseTitle(4)).toBe(`4${NBSP}rendez-vous passés à clôturer`);
  });

  it('a booking’s line; a missing client, service or collaborateur reads generically', () => {
    const ok = readRevenueLedger(ledger([ledgerRow()]))!.items[0];
    expect(revenueLedgerLine(ok)).toBe('Fatou B. · Tresses · Awa Koné');
    const bare = readRevenueLedger(
      ledger([
        ledgerRow({ clientDisplayName: undefined, serviceNames: [null, 'Coupe'], artistLabel: null, artistState: 'unassigned' }),
      ]),
    )!.items[0];
    expect(revenueLedgerLine(bare)).toBe('Client · Prestation supprimée, Coupe · Sans collaborateur');
  });

  it('the footnote denies custody, and is the one « encaiss »', () => {
    expect(REVENUE_PRICE_FOOTNOTE).toContain('MyWeli n’encaisse rien');
  });
});

describe('« Trier par » (§4.7)', () => {
  const rows = (
    readRevenueAnalytics(
      analytics({
        groups: [
          {
            ...(analytics().groups as Record<string, unknown>[])[0],
            byArtist: [
              row({ key: 'a', label: 'Zoé', current: { completedAmount: 90000, completedCount: 2, averageTicket: 45000 } }),
              row({ key: 'b', label: 'Élodie', current: { completedAmount: 50000, completedCount: 5, averageTicket: 10000 } }),
              row({ key: 'c', label: 'Awa', current: { completedAmount: 0, completedCount: 0, averageTicket: null } }),
              row({ key: 'd', label: 'Eve', current: { completedAmount: 50000, completedCount: 5, averageTicket: 10000 } }),
            ],
          },
        ],
      }),
    )!.groups[0].byArtist
  );
  const keys = (r: RevenueRow[]) => r.map((x) => x.key);

  it('Montant is the server’s order', () => {
    expect(keys(sortRevenueRows(rows, 'artist', 'amount'))).toEqual(['a', 'b', 'c', 'd'].filter((k) => k !== 'c').concat('c'));
  });
  it('Rendez-vous: the most first, ties in the server’s order; a row at 0 stays last', () => {
    expect(keys(sortRevenueRows(rows, 'artist', 'count'))).toEqual(['b', 'd', 'a', 'c']);
  });
  it('Nom: French order (É with E), a row at 0 still last', () => {
    expect(keys(sortRevenueRows(rows, 'artist', 'name'))).toEqual(['b', 'd', 'a', 'c']);
  });
});

describe('the CSV (Q10, §13.3)', () => {
  const a = readRevenueAnalytics(analytics())!;
  const g = a.groups[0];

  it('opens in Excel: BOM, `;`, CRLF, integers, a French comma on the share', () => {
    const csv = revenueCsv(
      [
        ...g.byArtist,
        {
          ...g.byArtist[0],
          label: 'Konan; « Le Grand »',
          state: 'removed',
          share: 0.3425,
          current: { completedAmount: 26250.4, completedCount: 1, averageTicket: 26250.4 },
          previous: null,
          estimated: true,
        },
      ],
      'artist',
      g,
    );
    expect(csv.charCodeAt(0)).toBe(0xfeff);
    const lines = csv.slice(1).split('\r\n');
    expect(lines[0]).toBe(
      'Nom;Rendez-vous terminés;Réalisé;Part (%);Panier moyen;Réalisé sur la période comparée;Devise;Estimé',
    );
    expect(lines[1]).toBe('Awa Koné;2;50000;100,00;25000;40000;XOF;non');
    expect(lines[2]).toBe('"Konan; « Le Grand » · a quitté l’équipe";1;26250;34,25;26250;;XOF;oui');
    expect(lines[3]).toBe('');
  });

  it('a name that starts like a formula stays text', () => {
    expect(csvText('=HYPERLINK("http://x")')).toBe('"\'=HYPERLINK(""http://x"")"');
    expect(csvText('+225')).toBe("'+225");
    expect(csvText('-5')).toBe("'-5");
    expect(csvText('@cmd')).toBe("'@cmd");
    expect(csvText('Awa')).toBe('Awa');
  });

  it('never carries a client name', () => {
    const csv = revenueCsv(g.byService, 'service', g);
    expect(csv).not.toContain('Fatou');
    expect(csv).not.toContain('Client');
  });

  it('is named after the table and the period', () => {
    expect(revenueCsvFilename(a, 'artist')).toBe('revenus-collaborateurs-2026-11.csv');
    expect(revenueCsvFilename({ period: 'year', from: '2026-01-01', to: '2026-12-31' }, 'service')).toBe(
      'revenus-prestations-2026.csv',
    );
    expect(revenueCsvFilename({ period: 'day', from: '2026-11-25', to: '2026-11-25' }, 'channel')).toBe(
      'revenus-canaux-2026-11-25.csv',
    );
    expect(revenueCsvFilename({ period: 'week', from: '2026-11-23', to: '2026-11-29' }, 'artist', 'Awa Koné')).toBe(
      'revenus-awa-kone-collaborateurs-2026-11-23_2026-11-29.csv',
    );
  });
});

describe('the strict reading (§7, §21)', () => {
  it.each([
    'analytics_month',
    'analytics_week',
    'analytics_year',
    'analytics_custom_from_2026-10-01_to_2026-11-27',
    'analytics_month_service_svc-Tresses',
  ])('reads the R2 server’s %s', (name) => {
    const body = r2(name);
    const a = readRevenueAnalytics(body);
    expect(a).not.toBeNull();
    expect(a!.groups.length).toBe((body.groups as unknown[]).length);
  });

  it.each(['ledger_completed', 'ledger_toclose'])('reads the R2 server’s %s', (name) => {
    const l = readRevenueLedger(r2(name));
    expect(l).not.toBeNull();
    expect(l!.items.length).toBeGreaterThan(0);
  });

  it('the R2 month adds up: figures, rows and series agree', () => {
    const a = readRevenueAnalytics(r2('analytics_month'))!;
    const g = a.groups[0];
    const sum = (xs: number[]) => xs.reduce((s, x) => s + x, 0);
    expect(sum(g.byArtist.map((r) => r.current.completedAmount))).toBe(g.current.completedAmount);
    expect(sum(g.series.map((p) => p.completedAmount))).toBe(g.current.completedAmount);
    expect(revenuePeriodTitle(a)).toBe('Novembre 2026');
  });

  it.each([
    ['no groups', (b: Record<string, unknown>) => delete b.groups],
    ['an unknown period', (b: Record<string, unknown>) => (b.period = 'quarter')],
    ['a figure as text', (b: Record<string, unknown>) => {
      ((b.groups as Record<string, Record<string, unknown>>[])[0].current as Record<string, unknown>).completedAmount = '50000';
    }],
    ['a row state the contract does not list', (b: Record<string, unknown>) => {
      ((b.groups as Record<string, unknown>[])[0].byArtist as Record<string, unknown>[])[0].state = 'ghost';
    }],
    ['a date that is not a day', (b: Record<string, unknown>) => (b.from = '2026-11-31')],
    ['no comparison', (b: Record<string, unknown>) => delete b.comparison],
  ])('an answer with %s is unreadable, never zeros', (_, mutate) => {
    const body = r2('analytics_month');
    mutate(body);
    expect(readRevenueAnalytics(body)).toBeNull();
  });

  it('a ledger without its instant, or with an unknown channel, is unreadable', () => {
    const noAsOf = r2('ledger_completed');
    delete noAsOf.asOf;
    expect(readRevenueLedger(noAsOf)).toBeNull();
    const odd = r2('ledger_completed');
    (odd.items as Record<string, unknown>[])[0].channel = 'fax';
    expect(readRevenueLedger(odd)).toBeNull();
  });
});
