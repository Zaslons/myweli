/// Where a salon stands with MyWeli's validation, on the website's Pro space
/// (BACKLOG B0.18 — docs/design/salon-go-live-approval.md §6,
/// docs/design/web-salon-validation.md). The pure half: the state derived
/// once, and EVERY French string the validation shows, so the copy has one
/// home and one ban test (no « vérif » here — that word is KYC's).
///
/// **The two servers (web-salon-validation.md §1).** A backend before B0.18
/// sends no `validation` key at all: `undefined` → `legacy`, today's screens
/// and words. The B0.18 backend always sends the key — `null` while the salon
/// never asked. Only the KEY's presence opens the new states.

import type { components } from '../api/schema';
import { formatDateFr } from '../format';
import { SALON_UNPUBLISHED_FOR_BILLING } from './subscription-plans';

export type SalonValidation = components['schemas']['SalonValidation'];
export type SalonRefusal = NonNullable<SalonValidation['refusal']>;
export type RefusalCode = SalonRefusal['code'];

export type GoLiveState =
  /// A server before B0.18 (no `validation` key): today's screens.
  | 'legacy'
  | 'suspended'
  | 'live'
  | 'neverAsked'
  /// `pending`, or `approved` while the admin's validation finishes.
  | 'pending'
  | 'refused'
  | 'refusedFinal'
  /// Validated and live once, back to `draft`, its offer live: « Remettre en
  /// ligne » (the publish answers 200).
  | 'offlineRepublish'
  /// The same, its offer lapsed: the billing pointer.
  | 'offlineUnpaid'
  /// The same, seen by a member who is not the owner (`offerLive` is the
  /// owner's only): the line, never a card.
  | 'offline';

/// §2's table, first match wins. `suspended` before `live` and before the
/// validation (a pending salon an admin suspends reads « Suspendu »); `live`
/// before the validation (an `active` salon is public whatever its row says).
export function goLiveState(
  status: string | null | undefined,
  validation: SalonValidation | null | undefined,
): GoLiveState {
  if (validation === undefined) return 'legacy';
  if (status === 'suspended') return 'suspended';
  if (!status || status === 'active') return 'live';
  if (validation === null) return 'neverAsked';
  switch (validation.state) {
    case 'pending':
      return 'pending';
    case 'refused':
      return validation.refusal?.final ? 'refusedFinal' : 'refused';
    case 'approved':
      if (!validation.wentLive) return 'pending';
      if (validation.offerLive === true) return 'offlineRepublish';
      if (validation.offerLive === false) return 'offlineUnpaid';
      return 'offline';
    default:
      // A state this client does not know: never claim one.
      return 'neverAsked';
  }
}

// --- The words (approved word for word: parent §6.1, §4.3; Q9) -----------

/// The sentence the salon reads for each refusal code — the backend's
/// `kRefusalSentences` (backend/lib/src/validation/salon_validation_copy.dart),
/// pinned equal to it by tests/salon-validation.test.ts. `other` is the
/// admin's note alone.
export const REFUSAL_SENTENCES: Record<RefusalCode, string | null> = {
  incomplete_info: 'Certaines informations du salon sont incomplètes ou peu claires.',
  photos: 'Les photos ne montrent pas assez clairement le salon et son travail.',
  unconfirmed: 'Nous n’avons pas pu confirmer l’existence de ce salon.',
  outside_ci:
    'MyWeli n’est pas encore disponible dans votre pays. Si votre salon est en Côte d’Ivoire, écrivez-nous depuis « Aide & Support ».',
  test_salon: 'Ce salon est un salon de test : il ne sera pas mis en ligne.',
  other: null,
};

export const RESUBMIT_SENTENCE = 'Modifiez votre salon, puis renvoyez-le pour validation.';

/// After a request the server recorded (202).
export const REQUEST_SENT = 'Demande envoyée. Nous vous préviendrons de la décision.';

/// The line on each salon row of « Mes salons » (the sidebar's switcher).
export const STATE_LINE: Record<Exclude<GoLiveState, 'legacy'>, string> = {
  neverAsked: 'Brouillon — pas encore en ligne',
  pending: 'En cours de validation',
  refused: 'Mise en ligne refusée',
  refusedFinal: 'Mise en ligne refusée',
  live: 'En ligne',
  offlineRepublish: 'Plus en ligne',
  offlineUnpaid: 'Plus en ligne',
  offline: 'Plus en ligne',
  suspended: 'Suspendu',
};

/// The card's buttons, by state. `legacy` keeps today's.
export const PUBLISH_LABEL = {
  legacy: 'Mettre en ligne',
  neverAsked: 'Demander la mise en ligne',
  refused: 'Renvoyer pour validation',
  offlineRepublish: 'Remettre en ligne',
} as const;

/// The hint beside a disabled button. `legacy` keeps today's.
export const LEGACY_HINT = 'Complétez les étapes essentielles pour mettre votre profil en ligne.';
export const REQUEST_HINT = 'Complétez les étapes essentielles pour demander la mise en ligne.';

/// The billing pointer's label: « Mon abonnement »'s own title.
export const BILLING_POINTER = 'Mon abonnement';

/// R8's sub-line (owner, 2026-11-13 — web-salon-validation.md §9 Q3): the
/// profile is filled but its commune is not one of MyWeli's.
export const COMMUNE_FROM_LIST = 'Choisissez la commune dans la liste';

/// « Demande envoyée le 13 novembre 2026 » — the salon's clock; nothing when
/// the request has no time (a row the 0044 backfill wrote).
export function requestSentLine(
  submittedAt: string | null | undefined,
  tz?: string | null,
): string | null {
  if (!submittedAt || Number.isNaN(Date.parse(submittedAt))) return null;
  return `Demande envoyée le ${formatDateFr(submittedAt, tz ?? undefined)}`;
}

/// A refusal's lines: the code's sentence, then the note on its own line.
/// Either is left out when absent (`other` has no sentence; a member who is
/// not the owner gets no note).
export function refusalLines(refusal: SalonRefusal | null | undefined): string[] {
  if (!refusal) return [];
  const lines: string[] = [];
  const sentence = REFUSAL_SENTENCES[refusal.code] ?? null;
  if (sentence) lines.push(sentence);
  const note = refusal.note?.trim();
  if (note) lines.push(note);
  return lines;
}

export type BannerTone = 'neutral' | 'error' | 'warning';

export type StateBanner = { tone: BannerTone; title: string; lines: string[] };

/// The card's banner (§6.1's « Banner title » and « Banner text »), or null
/// for the states without one (`legacy` and `neverAsked` keep the card's
/// heading; `live` and `offline` have no card).
export function stateBanner(
  state: GoLiveState,
  validation: SalonValidation | null | undefined,
): StateBanner | null {
  switch (state) {
    case 'pending':
      return {
        tone: 'neutral',
        title: 'En cours de validation',
        lines: [
          'Nous examinons votre salon avant sa mise en ligne. Nous vous préviendrons dès que c’est fait.',
        ],
      };
    case 'refused':
      return {
        tone: 'error',
        title: 'Mise en ligne refusée',
        lines: [...refusalLines(validation?.refusal), RESUBMIT_SENTENCE],
      };
    case 'refusedFinal':
      return {
        tone: 'error',
        title: 'Mise en ligne refusée',
        lines: refusalLines(validation?.refusal),
      };
    case 'offlineUnpaid':
      return {
        tone: 'warning',
        title: 'Votre salon n’est plus en ligne',
        lines: [SALON_UNPUBLISHED_FOR_BILLING],
      };
    case 'offlineRepublish':
      return {
        tone: 'warning',
        title: 'Votre salon n’est plus en ligne',
        lines: ['Vous pouvez le remettre en ligne.'],
      };
    case 'suspended':
      return {
        tone: 'error',
        title: 'Votre salon est suspendu',
        lines: ['Contactez MyWeli pour en savoir plus.'],
      };
    default:
      return null;
  }
}

/// The tone's tokens — the KYC page's banner (VerificationClient).
export const BANNER_TONE_CLASS: Record<BannerTone, string> = {
  neutral: 'border-border bg-surface text-textSecondary',
  error: 'border-error/40 bg-error/10 text-error',
  warning: 'border-warning/40 bg-warning/10 text-warning',
};

// --- « Aperçu de ma page » (owner, 2026-11-13 — §9 Q1) ---------------------

const PREVIEW_DRAFT =
  'Aperçu — votre salon n’est pas encore en ligne. Voici ce que verront vos clients.';
const PREVIEW_LIVE = 'Votre salon est en ligne — ceci est votre page publique.';
/// Today's suspended sentence, kept for a server before B0.18.
const PREVIEW_SUSPENDED_LEGACY =
  'Votre salon est suspendu. Contactez MyWeli pour le réactiver — vos rendez-vous sont intacts.';
const PREVIEW_REFUSED = 'Aperçu — la mise en ligne de votre salon a été refusée.';

export function previewBanner(
  status: string | null | undefined,
  validation: SalonValidation | null | undefined,
): string {
  const state = goLiveState(status, validation);
  switch (state) {
    case 'legacy':
      if (status === 'suspended') return PREVIEW_SUSPENDED_LEGACY;
      return !status || status === 'active' ? PREVIEW_LIVE : PREVIEW_DRAFT;
    case 'live':
      return PREVIEW_LIVE;
    case 'suspended':
      return 'Votre salon est suspendu. Contactez MyWeli pour en savoir plus.';
    case 'pending':
      return 'Aperçu — votre salon est en cours de validation. Voici ce que verront vos clients.';
    case 'refused':
      return `${PREVIEW_REFUSED} Voici ce que verront vos clients une fois votre salon validé.`;
    case 'refusedFinal':
      return PREVIEW_REFUSED;
    case 'offlineRepublish':
    case 'offlineUnpaid':
    case 'offline':
      return 'Aperçu — votre salon n’est plus en ligne. Voici ce que verront vos clients.';
    case 'neverAsked':
      return PREVIEW_DRAFT;
  }
}

// --- The Pro data export (parent §6.4, web-salon-validation.md §6) ---------

export type ExportedValidation = {
  state: SalonValidation['state'];
  submittedAt: string | null;
  decidedAt: string | null;
  wentLive: boolean;
  refusal: {
    code: RefusalCode;
    final: boolean;
    note: string | null;
    /// The sentence the salon reads — null for `other` (the note alone).
    reason: string | null;
  } | null;
};

/// The export's `validation`: `null` when never asked; the wire's values plus
/// the refusal's sentence. `offerLive` is billing state and stays out. The
/// caller leaves the key out when the server sent none (`undefined`).
export function validationForExport(
  validation: SalonValidation | null,
): ExportedValidation | null {
  if (validation === null) return null;
  const r = validation.refusal;
  return {
    state: validation.state,
    submittedAt: validation.submittedAt ?? null,
    decidedAt: validation.decidedAt ?? null,
    wentLive: validation.wentLive,
    refusal: r
      ? {
          code: r.code,
          final: r.final,
          note: r.note ?? null,
          reason: REFUSAL_SENTENCES[r.code] ?? null,
        }
      : null,
  };
}
