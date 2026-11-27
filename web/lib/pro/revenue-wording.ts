/// The words of « Revenus » (docs/design/pro-revenue-analytics.md §3.3,
/// §3.6, §4.13) — pure, one place, so the pages and their tests read the
/// same sentences as the app (`mobile/lib/core/utils/revenue_wording.dart`).
/// **Never** « encaissé », « chiffre d'affaires » or « paiements reçus »:
/// MyWeli does not see a payment (§4.10). The one « encaiss » is the
/// footnote's negation, « MyWeli n'encaisse rien ».

import { countFr } from '../format';
import {
  NO_ARTIST,
  type RevenueAxis,
  type RevenueChannel,
  type RevenueFilters,
  type RevenueLedgerRow,
  type RevenueLedgerStatus,
  type RevenueRow,
  type RevenueRowState,
  type RevenueSort,
  channelFromApi,
} from './revenue';

// ── Labels (§3.3) ────────────────────────────────────────────────────────────

export const NO_ARTIST_LABEL = 'Sans collaborateur attribué';
export const FORMER_ARTIST_LABEL = 'Ancien collaborateur';
export const DELETED_SERVICE_LABEL = 'Prestation supprimée';

/// A channel's name — the clients name them, the server sends no label.
export function revenueChannelLabel(channel: RevenueChannel): string {
  switch (channel) {
    case 'app':
      return 'Application MyWeli';
    case 'web':
      return 'Site MyWeli';
    case 'salon':
      return 'Ajouté par le salon';
    case 'online':
      return 'En ligne (avant le suivi)';
  }
}

/// The label of one row of [axis] — §3.3's table, row by row.
export function revenueRowLabel(
  axis: RevenueAxis,
  row: { key: string | null; label: string | null; state: RevenueRowState | null },
): string {
  const { key, label, state } = row;
  switch (axis) {
    case 'artist':
      if (state === 'unassigned' || key == null || key === NO_ARTIST) {
        return NO_ARTIST_LABEL;
      }
      if (state === 'removed') {
        return label == null ? FORMER_ARTIST_LABEL : `${label} · a quitté l’équipe`;
      }
      return label ?? FORMER_ARTIST_LABEL;
    case 'service':
      if (state === 'removed') {
        return label == null ? DELETED_SERVICE_LABEL : `${label} · prestation supprimée`;
      }
      return label ?? DELETED_SERVICE_LABEL;
    case 'channel': {
      const channel = channelFromApi(key);
      return channel == null ? (label ?? '') : revenueChannelLabel(channel);
    }
  }
}

export function revenueLabelOf(axis: RevenueAxis, row: RevenueRow): string {
  return revenueRowLabel(axis, row);
}

/// A detail's name, from the answer's filters (§4.8) — the server labels
/// the first filter it has: collaborateur, else prestation, else canal.
export function revenueFilterLabel(axis: RevenueAxis, f: RevenueFilters): string {
  return revenueRowLabel(axis, {
    key: axis === 'artist' ? f.artistId : axis === 'service' ? f.serviceId : f.channel,
    label: f.label,
    state: f.state,
  });
}

/// The kind of row a detail is about — its kicker, and its title until the
/// answer names it.
export function revenueAxisKind(axis: RevenueAxis): string {
  switch (axis) {
    case 'artist':
      return 'Collaborateur';
    case 'service':
      return 'Prestation';
    case 'channel':
      return 'Canal';
  }
}

/// « Répartition »'s tabs (§4.7).
export function revenueAxisTitle(axis: RevenueAxis): string {
  switch (axis) {
    case 'artist':
      return 'Collaborateurs';
    case 'service':
      return 'Prestations';
    case 'channel':
      return 'Canaux';
  }
}

export function revenueSortName(sort: RevenueSort): string {
  switch (sort) {
    case 'amount':
      return 'Montant';
    case 'count':
      return 'Rendez-vous';
    case 'name':
      return 'Nom';
  }
}

export function revenueCompareName(mode: 'previous' | 'year' | 'none'): string {
  switch (mode) {
    case 'previous':
      return 'Période précédente';
    case 'year':
      return 'Même période l’an dernier';
    case 'none':
      return 'Aucune comparaison';
  }
}

// ── Numbers ─────────────────────────────────────────────────────────────────

/// U+202F, the narrow no-break space French puts before « % »: the sign
/// never leaves its number's line.
const NNBSP = String.fromCharCode(0x202f);

/// Rounds half away from zero — Dart's `round()`, so the app and the
/// website print the same « −3 % » for −2,5 (Math.round gives −2).
export function roundHalfAway(x: number): number {
  return Math.sign(x) * Math.round(Math.abs(x));
}

/// « 5,9 % » — a ratio (0–1) as a French percentage.
export function formatPercent(ratio: number, decimals = 0): string {
  const f = new Intl.NumberFormat('fr-FR', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
  return `${f.format(ratio * 100)}${NNBSP}%`;
}

/// « 1,2 » — one decimal, French comma.
export function formatOneDecimal(value: number): string {
  return new Intl.NumberFormat('fr-FR', {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  }).format(value);
}

// ── Deltas (§3.6) ───────────────────────────────────────────────────────────

export type RevenueDeltaTone = 'good' | 'bad' | 'neutral';

export type RevenueDelta = {
  /// « +12 % » · « −8 % » · « stable » · « nouveau » · « −1,2 pt ».
  text: string;
  /// « en hausse de 12 % par rapport à octobre 2026 » (§12.3).
  spoken: string;
  tone: RevenueDeltaTone;
  /// The arrow: up, down, or none (« stable »).
  up: boolean | null;
};

const MINUS = '−';

function against(comparison: string | null | undefined): string {
  if (!comparison) return '';
  // « par rapport au 1er – 25 oct. » reads oddly; a range is « la période ».
  return /^\d/.test(comparison)
    ? ` par rapport à la période ${comparison}`
    : ` par rapport à ${comparison}`;
}

/// The delta of an amount or a count. Null when there is nothing to say: no
/// comparison, or both at 0.
export function revenueDelta(
  current: number,
  previous: number | null | undefined,
  comparison?: string | null,
  upIsGood = true,
): RevenueDelta | null {
  if (previous == null) return null;
  if (previous === 0) {
    if (current <= 0) return null;
    return {
      text: 'nouveau',
      spoken: 'nouveau, rien sur la période comparée',
      tone: upIsGood ? 'good' : 'bad',
      up: true,
    };
  }
  const pct = roundHalfAway(((current - previous) / previous) * 100);
  if (pct === 0) {
    return { text: 'stable', spoken: `stable${against(comparison)}`, tone: 'neutral', up: null };
  }
  const up = pct > 0;
  const figure = `${Math.abs(pct)}${NNBSP}%`;
  return {
    text: `${up ? '+' : MINUS}${figure}`,
    spoken: `${up ? 'en hausse' : 'en baisse'} de ${figure}${against(comparison)}`,
    tone: up === upIsGood ? 'good' : 'bad',
    up,
  };
}

/// « Taux d'absence » moves in **points**, one decimal (« −1,2 pt »); up is
/// bad. Null when either rate is undefined.
export function revenueRateDelta(
  current: number | null | undefined,
  previous: number | null | undefined,
  comparison?: string | null,
): RevenueDelta | null {
  if (current == null || previous == null) return null;
  const tenths = roundHalfAway((current - previous) * 1000);
  if (tenths === 0) {
    return { text: 'stable', spoken: `stable${against(comparison)}`, tone: 'neutral', up: null };
  }
  const up = tenths > 0;
  const points = Math.abs(tenths) / 10;
  const figure = formatOneDecimal(points);
  const unit = points < 2 ? 'point' : 'points';
  return {
    text: `${up ? '+' : MINUS}${figure} pt`,
    spoken: `${up ? 'en hausse' : 'en baisse'} de ${figure} ${unit}${against(comparison)}`,
    tone: up ? 'bad' : 'good',
    up,
  };
}

// ── Counts (§4.13 — plurals through countFr, never « (s) ») ────────────────

export function revenueAbsences(n: number): string {
  return countFr(n, 'absence', 'absences');
}

export function revenueUpcomingLine(n: number): string {
  return `${countFr(n, 'rendez-vous confirmé', 'rendez-vous confirmés')} à venir`;
}

export function revenuePendingLine(n: number): string {
  return `+ ${countFr(n, 'demande', 'demandes')} en attente`;
}

export function revenueToCloseTitle(n: number): string {
  return `${countFr(n, 'rendez-vous passé', 'rendez-vous passés')} à clôturer`;
}

export function revenueAppointments(n: number): string {
  return countFr(n, 'rendez-vous', 'rendez-vous');
}

// ── The ledger (§4.9) ───────────────────────────────────────────────────────

export function revenueLedgerClient(r: RevenueLedgerRow): string {
  return r.clientDisplayName ?? 'Client';
}

export function revenueLedgerServices(r: RevenueLedgerRow): string {
  return r.serviceNames.length === 0
    ? DELETED_SERVICE_LABEL
    : r.serviceNames.map((s) => s ?? DELETED_SERVICE_LABEL).join(', ');
}

export function revenueLedgerArtist(r: RevenueLedgerRow): string {
  return r.artistState === 'unassigned' ? 'Sans collaborateur' : (r.artistLabel ?? FORMER_ARTIST_LABEL);
}

/// « Fatou B. · Tresses, Coupe · Awa Koné ».
export function revenueLedgerLine(r: RevenueLedgerRow): string {
  return `${revenueLedgerClient(r)} · ${revenueLedgerServices(r)} · ${revenueLedgerArtist(r)}`;
}

/// The ledger's filters (§4.9).
export function revenueLedgerStatusLabel(s: RevenueLedgerStatus): string {
  switch (s) {
    case 'completed':
      return 'Terminés';
    case 'upcoming':
      return 'À venir';
    case 'toClose':
      return 'À clôturer';
    case 'noShow':
      return 'Absents';
    case 'cancelled':
      return 'Annulés';
  }
}

/// « Aucun rendez-vous {filtre} sur cette période. » (§4.13).
export function revenueLedgerEmpty(s: RevenueLedgerStatus): string {
  switch (s) {
    case 'completed':
      return 'Aucun rendez-vous terminé sur cette période.';
    case 'upcoming':
      return 'Aucun rendez-vous à venir sur cette période.';
    case 'toClose':
      return 'Aucun rendez-vous à clôturer sur cette période.';
    case 'noShow':
      return 'Aucune absence sur cette période.';
    case 'cancelled':
      return 'Aucun rendez-vous annulé ou refusé sur cette période.';
  }
}

// ── Footnotes (§4.10) ───────────────────────────────────────────────────────

export const REVENUE_PRICE_FOOTNOTE =
  'Montants calculés au prix affiché lors de la réservation. Les paiements se font entre vous et vos clients : MyWeli n’encaisse rien.';

export const REVENUE_SERVICES_FOOTNOTE =
  'Un rendez-vous à plusieurs prestations compte pour chacune.';

/// The day R1 started keeping each booking's lines (deployed 2026-11-26).
export const REVENUE_ESTIMATED_FOOTNOTE =
  'Estimé : réservation faite avant le 26 novembre 2026, répartie selon les prix actuels de vos prestations.';

// ── The currency of a group (§4.11) ─────────────────────────────────────────

export function revenueCurrencyName(code: string): string {
  switch (code) {
    case 'XOF':
      return 'XOF · franc CFA (UEMOA)';
    case 'XAF':
      return 'XAF · franc CFA (CEMAC)';
    default:
      return code;
  }
}
