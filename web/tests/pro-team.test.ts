import { describe, expect, it } from 'vitest';
import {
  ROLE_LABELS,
  ROLE_SUMMARIES,
  type TeamMember,
  hasCap,
  memberStatusBadge,
  seatsLabel,
  teamErrorCta,
  teamErrorMessage,
  validateInviteEmail,
} from '../lib/pro/team';

/// The shared team helpers (team access R5a). The error table MUST mirror the
/// app's team_error_messages.dart so copy never drifts across surfaces.

describe('role labels & summaries', () => {
  it('are the four French roles', () => {
    expect(ROLE_LABELS.owner).toBe('Propriétaire');
    expect(ROLE_LABELS.manager).toBe('Manager');
    expect(ROLE_LABELS.reception).toBe('Réception');
    expect(ROLE_LABELS.staff).toBe('Collaborateur');
  });

  it('summarise the three invitable roles', () => {
    expect(ROLE_SUMMARIES.manager).toMatch(/revenus/i);
    expect(ROLE_SUMMARIES.reception).toMatch(/planning|clients/i);
    expect(ROLE_SUMMARIES.staff).toMatch(/propre planning/i);
  });
});

describe('teamErrorMessage', () => {
  it('maps every known machine code', () => {
    const codes: Record<string, RegExp> = {
      member_exists: /déjà dans l’équipe/,
      offer_required: /offre/,
      seat_limit: /places/,
      owner_protected: /propriétaire/i,
      invitation_expired: /expiré/,
      invalid_role: /Rôle invalide/,
      artist_required: /fiche employé/,
      artist_not_found: /Fiche employé introuvable/,
      trial_used: /essai gratuit/i,
      not_a_member: /accès à ce salon a été retiré/,
      not_found: /Introuvable/,
      forbidden: /propriétaire du salon/,
      // R6 multi-salons.
      reseau_required: /offre Réseau est requise/,
      salon_limit: /Limite de salons atteinte/,
    };
    for (const [code, re] of Object.entries(codes)) {
      expect(teamErrorMessage(code)).toMatch(re);
    }
  });

  it('rate-limit copy differs by context (invite vs resend)', () => {
    expect(teamErrorMessage('invite_rate_limited', 'invite')).toMatch(
      /Trop d’invitations/,
    );
    expect(teamErrorMessage('invite_rate_limited', 'resend')).toMatch(
      /Budget de renvois/,
    );
  });

  it('unknown code → the generic fallback', () => {
    expect(teamErrorMessage(undefined)).toBe('Une erreur est survenue. Réessayez.');
    expect(teamErrorMessage('nonsense')).toBe(
      'Une erreur est survenue. Réessayez.',
    );
  });
});

describe('teamErrorCta', () => {
  it('offer gates carry a picker CTA', () => {
    expect(teamErrorCta('offer_required')).toEqual({
      label: 'Choisir mon offre',
      href: '/pro/abonnement',
    });
    expect(teamErrorCta('seat_limit')?.href).toBe('/pro/abonnement');
  });

  it('reseau_required routes to the offer picker', () => {
    expect(teamErrorCta('reseau_required')).toEqual({
      label: 'Passer à l’offre Réseau',
      href: '/pro/abonnement',
    });
  });

  it('other codes carry none', () => {
    expect(teamErrorCta('member_exists')).toBeNull();
    expect(teamErrorCta(undefined)).toBeNull();
  });
});

describe('validateInviteEmail', () => {
  it('trims + lowercases a valid address', () => {
    expect(validateInviteEmail('  Awa@Salon.TEST ')).toEqual({
      ok: true,
      email: 'awa@salon.test',
    });
  });

  it('rejects malformed input', () => {
    expect(validateInviteEmail('nope').ok).toBe(false);
    expect(validateInviteEmail('a@b').ok).toBe(false);
    expect(validateInviteEmail('').ok).toBe(false);
  });
});

describe('memberStatusBadge', () => {
  const fmt = (iso: string) => `le ${iso.slice(0, 10)}`;
  const base: Pick<TeamMember, 'status' | 'expired' | 'expiresAt'> = {
    status: 'active',
    expired: false,
    expiresAt: null,
  };

  it('active → no badge', () => {
    expect(memberStatusBadge(base, fmt)).toBeNull();
  });

  it('invited → sent + expiry (default tone)', () => {
    const b = memberStatusBadge(
      { ...base, status: 'invited', expiresAt: '2026-08-01T00:00:00.000Z' },
      fmt,
    );
    expect(b?.tone).toBe('default');
    expect(b?.label).toMatch(/Invitation envoyée · expire/);
  });

  it('expired invitation → error tone', () => {
    const b = memberStatusBadge(
      { ...base, status: 'invited', expired: true },
      fmt,
    );
    expect(b).toEqual({ label: 'Expirée', tone: 'error' });
  });

  it('revoked → error tone', () => {
    const b = memberStatusBadge({ ...base, status: 'revoked' }, fmt);
    expect(b).toEqual({ label: 'Accès révoqué', tone: 'error' });
  });
});

describe('seatsLabel & hasCap', () => {
  it('renders used / cap places', () => {
    expect(seatsLabel({ cap: 5, used: 2 })).toBe('2 / 5 places');
  });

  it('hasCap: absent membership reads as owner-shaped (legacy fallback)', () => {
    expect(hasCap(undefined, 'members.manage')).toBe(true);
    expect(hasCap(null, 'anything')).toBe(true);
  });

  it('hasCap: present membership gates by the capability list', () => {
    const membership = {
      role: 'manager' as const,
      capabilities: ['catalogue.manage', 'journal.manage.all'],
    };
    expect(hasCap(membership, 'catalogue.manage')).toBe(true);
    expect(hasCap(membership, 'finances.view')).toBe(false);
  });
});
