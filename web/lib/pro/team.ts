/// Team-access pure helpers (module `access` R5 —
/// docs/design/web-team-access-r5.md): French role labels/summaries, the
/// SHARED machine-code → copy table (mirrors the app's
/// team_error_messages.dart so copy can never drift between surfaces),
/// invite validation and roster presentation helpers.

import type { components } from '../api/schema';

export type Membership = components['schemas']['Membership'];
export type TeamMember = components['schemas']['TeamMember'];
export type TeamInvitation = components['schemas']['TeamInvitation'];
/// One « Mes salons » entry (module `access` R6 — GET /me/salons).
export type SalonMembership = components['schemas']['SalonMembership'];

export type TeamRole = 'owner' | 'manager' | 'reception' | 'staff';
export type TeamRoleInput = 'manager' | 'reception' | 'staff';

export const ROLE_LABELS: Record<TeamRole, string> = {
  owner: 'Propriétaire',
  manager: 'Manager',
  reception: 'Réception',
  staff: 'Collaborateur',
};

/// Plain-French capability summaries — spec-locked (R3 §7).
export const ROLE_SUMMARIES: Record<TeamRoleInput, string> = {
  manager:
    'Gère les rendez-vous, le catalogue et les disponibilités. Ne voit pas les revenus.',
  reception:
    'Gère le planning et le fichier clients. Pas de catalogue ni de réglages.',
  staff: 'Voit uniquement son propre planning.',
};

/// The demo account's 403 (`demo_account_locked`) — the store-review demo
/// account is refused the actions a weekly reset cannot undo, account
/// deletion included (docs/design/demo-account-deletion-lock.md). The SAME
/// sentence as the app's `demoAccountLockedMessage`
/// (mobile/lib/core/utils/team_error_messages.dart), which the store review
/// notes quote word for word; tests/pro-team.test.ts compares the two.
export const DEMO_ACCOUNT_LOCKED_MESSAGE =
  'Compte de démonstration — cette action est désactivée.';

/// Machine code → French copy. `ctx: 'resend'` swaps the shared
/// invite_rate_limited code for the per-invitation budget message.
/// `fallback` replaces the generic sentence for an unknown or absent code —
/// the app's `teamErrorMessage(code, fallback:)`.
export function teamErrorMessage(
  code: string | undefined,
  ctx?: 'invite' | 'resend',
  fallback?: string,
): string {
  switch (code) {
    case 'member_exists':
      return 'Cette personne est déjà dans l’équipe.';
    case 'offer_required':
      return 'Choisissez d’abord votre offre pour inviter votre équipe.';
    case 'seat_limit':
      return 'Toutes les places de votre offre sont occupées.';
    case 'invite_rate_limited':
      return ctx === 'resend'
        ? 'Budget de renvois épuisé pour cette invitation.'
        : 'Trop d’invitations envoyées aujourd’hui. Réessayez demain.';
    case 'owner_protected':
      return 'Le propriétaire ne peut pas être modifié.';
    case 'invitation_expired':
      return 'Cette invitation a expiré. Demandez au salon de la renvoyer.';
    case 'invalid_role':
      return 'Rôle invalide.';
    case 'artist_required':
      return 'Choisissez la fiche employé du collaborateur.';
    case 'artist_not_found':
      return 'Fiche employé introuvable. Actualisez et réessayez.';
    case 'trial_used':
      return 'Votre essai gratuit a déjà été utilisé. Contactez-nous pour activer votre offre.';
    case 'not_a_member':
      return 'Votre accès à ce salon a été retiré.';
    case 'not_found':
      return 'Introuvable. Actualisez et réessayez.';
    // R6 multi-salons (« Ajouter un salon »).
    case 'reseau_required':
      return 'L’offre Réseau est requise pour ajouter un salon. Passez à l’offre Réseau depuis « Mon abonnement ».';
    case 'salon_limit':
      return 'Limite de salons atteinte. Contactez-nous pour aller plus loin.';
    case 'forbidden':
      return 'Action réservée au propriétaire du salon.';
    case 'demo_account_locked':
      return DEMO_ACCOUNT_LOCKED_MESSAGE;
    default:
      return fallback ?? 'Une erreur est survenue. Réessayez.';
  }
}

// --- the invitee's side (team access R5a; the rejoin gate) -----------------
// docs/design/pro-rejoin-gate.md §4: every sentence below is the APP's, copied
// — none is invented here. tests/pro-team.test.ts reads the app source to keep
// it that way.

/// The app's accept refusal (pro_invitations_screen.dart).
export const INVITATION_ACCEPT_FAILED_MESSAGE =
  'Invitation impossible à accepter.';
/// The app's decline refusal (pro_invitations_screen.dart).
export const INVITATION_DECLINE_FAILED_MESSAGE = 'Refus impossible.';
/// The app's no-network sentence (every api_*_service.dart).
export const NO_CONNECTION_MESSAGE = 'Pas de connexion. Réessayez.';

/// The app's accept success line.
export function joinedSalonMessage(salonName: string): string {
  return `Vous avez rejoint ${salonName}`;
}

/// The app's login banner when it knows which salon was lost. The web's
/// `?motif=acces-retire` banner stays generic (`not_a_member`): a salon name
/// never travels in a URL.
export function revokedAccessMessage(salonName: string): string {
  return `Votre accès à ${salonName} a été retiré.`;
}

/// An invitee's refused accept/decline → copy. `forbidden` is the roster's
/// owner sentence (« Action réservée au propriétaire du salon. »); to an
/// invitee it means the invitation is not theirs to act on (T37), so they read
/// the action's own failure line instead. Codes that tell them something true
/// (expired, gone, demo) keep the shared table.
export function invitationActionError(
  code: string | undefined,
  action: 'accept' | 'decline',
): string {
  const failed =
    action === 'accept'
      ? INVITATION_ACCEPT_FAILED_MESSAGE
      : INVITATION_DECLINE_FAILED_MESSAGE;
  if (code === 'forbidden') return failed;
  return teamErrorMessage(code, undefined, failed);
}

/// The offer gates carry a CTA to the picker.
export function teamErrorCta(
  code?: string,
): { label: string; href: string } | null {
  if (code === 'offer_required') {
    return { label: 'Choisir mon offre', href: '/pro/abonnement' };
  }
  if (code === 'seat_limit') {
    return { label: 'Changer d’offre', href: '/pro/abonnement' };
  }
  if (code === 'reseau_required') {
    return { label: 'Passer à l’offre Réseau', href: '/pro/abonnement' };
  }
  return null;
}

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export function validateInviteEmail(raw: string): {
  ok: boolean;
  email: string;
} {
  const email = raw.trim().toLowerCase();
  return { ok: EMAIL_RE.test(email), email };
}

/// The roster status badge — null for a plain active member.
export function memberStatusBadge(
  m: Pick<TeamMember, 'status' | 'expired' | 'expiresAt'>,
  formatDate: (iso: string) => string,
): { label: string; tone: 'default' | 'error' } | null {
  if (m.status === 'revoked') {
    return { label: 'Accès révoqué', tone: 'error' };
  }
  if (m.status === 'invited') {
    if (m.expired) return { label: 'Expirée', tone: 'error' };
    return {
      label: m.expiresAt
        ? `Invitation envoyée · expire le ${formatDate(m.expiresAt)}`
        : 'Invitation envoyée',
      tone: 'default',
    };
  }
  return null;
}

export function seatsLabel(seats: { cap: number; used: number }): string {
  return `${seats.used} / ${seats.cap} places`;
}

/// Capability gate. An ABSENT membership (legacy payload) reads as
/// owner-shaped — mirrors the app's fallback; the server 403s regardless.
export function hasCap(
  membership: Membership | null | undefined,
  cap: string,
): boolean {
  if (!membership) return true;
  return membership.capabilities.includes(cap);
}
