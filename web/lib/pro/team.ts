/// Team-access pure helpers (module `access` R5 —
/// docs/design/web-team-access-r5.md): French role labels/summaries, the
/// SHARED machine-code → copy table (mirrors the app's
/// team_error_messages.dart so copy can never drift between surfaces),
/// invite validation and roster presentation helpers.

import type { components } from '../api/schema';

export type Membership = components['schemas']['Membership'];
export type TeamMember = components['schemas']['TeamMember'];
export type TeamInvitation = components['schemas']['TeamInvitation'];

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

/// Machine code → French copy. `ctx: 'resend'` swaps the shared
/// invite_rate_limited code for the per-invitation budget message.
export function teamErrorMessage(
  code: string | undefined,
  ctx?: 'invite' | 'resend',
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
    case 'forbidden':
      return 'Action réservée au propriétaire du salon.';
    default:
      return 'Une erreur est survenue. Réessayez.';
  }
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
