import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  DEMO_ACCOUNT_LOCKED_MESSAGE,
  GENERIC_ERROR_MESSAGE,
  INVITATION_ACCEPT_FAILED_MESSAGE,
  INVITATION_DECLINE_FAILED_MESSAGE,
  NO_CONNECTION_MESSAGE,
  ROLE_LABELS,
  ROLE_SUMMARIES,
  type TeamMember,
  hasCap,
  invitationActionError,
  joinedSalonMessage,
  memberStatusBadge,
  revokedAccessMessage,
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
      // The store-review demo account's refusals (T69).
      demo_account_locked: /^Compte de démonstration — cette action est désactivée\.$/,
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

describe('the demo account sentence — app/web parity', () => {
  /// The store review notes quote ONE sentence, and the app owns it
  /// (`demoAccountLockedMessage`). The web cannot import a Dart constant, so
  /// it carries a copy — and a copy drifts unless something reads both. Same
  /// posture as availability-parity.test.ts: read the mobile source.
  const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const dart = readFileSync(
    join(REPO_ROOT, 'mobile/lib/core/utils/team_error_messages.dart'),
    'utf-8',
  );

  it('is, character for character, the app\u2019s demoAccountLockedMessage', () => {
    const m = /const String demoAccountLockedMessage =\s*'([^']+)';/.exec(dart);
    expect(m, 'the Dart constant was not found — did it move?').not.toBeNull();
    expect(DEMO_ACCOUNT_LOCKED_MESSAGE).toBe(m![1]);
  });

  it('is what the shared table answers for the code — and has no CTA', () => {
    expect(teamErrorMessage('demo_account_locked')).toBe(
      DEMO_ACCOUNT_LOCKED_MESSAGE,
    );
    expect(teamErrorMessage('demo_account_locked', 'invite')).toBe(
      DEMO_ACCOUNT_LOCKED_MESSAGE,
    );
    expect(teamErrorCta('demo_account_locked')).toBeNull();
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

describe('the invitee’s sentences — the app’s, never invented (rejoin gate)', () => {
  /// docs/design/pro-rejoin-gate.md §4: every sentence the gate shows already
  /// exists in the app or on the web. The web cannot import a Dart string, so
  /// it carries copies — and these read the whole app source so a copy can
  /// neither drift nor be made up. Scanned rather than pinned to one file: the
  /// app is free to move a string between files without breaking this.
  const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const LIB = join(REPO_ROOT, 'mobile/lib');
  const appSource = (readdirSync(LIB, { recursive: true }) as string[])
    .filter((f) => f.endsWith('.dart'))
    .map((f) => readFileSync(join(LIB, f), 'utf-8'))
    .join('\n');

  it.each([
    INVITATION_ACCEPT_FAILED_MESSAGE,
    INVITATION_DECLINE_FAILED_MESSAGE,
    NO_CONNECTION_MESSAGE,
    GENERIC_ERROR_MESSAGE,
  ])('« %s » is a string literal in the app', (sentence) => {
    expect(typeof sentence).toBe('string');
    expect(appSource).toContain(`'${sentence}'`);
  });

  it('« Vous avez rejoint {salon} » is the app’s success line', () => {
    expect(appSource).toContain("'Vous avez rejoint $");
    expect(joinedSalonMessage('Beauté Divine')).toBe(
      'Vous avez rejoint Beauté Divine',
    );
  });

  it('the lost salon’s line names it, as the app’s login banner does', () => {
    expect(revokedAccessMessage('Beauté Divine')).toBe(
      'Votre accès à Beauté Divine a été retiré.',
    );
  });

  it('an invitee never reads the owner’s « forbidden » sentence', () => {
    expect(invitationActionError('forbidden', 'accept')).toBe(
      'Invitation impossible à accepter.',
    );
    expect(invitationActionError('forbidden', 'decline')).toBe(
      'Refus impossible.',
    );
    // The codes that tell the invitee something true keep the shared table.
    expect(invitationActionError('invitation_expired', 'accept')).toBe(
      teamErrorMessage('invitation_expired'),
    );
    expect(invitationActionError('not_found', 'decline')).toBe(
      teamErrorMessage('not_found'),
    );
    // No code (a bare 5xx) → the action's own failure line.
    expect(invitationActionError(undefined, 'accept')).toBe(
      'Invitation impossible à accepter.',
    );
    expect(invitationActionError(undefined, 'decline')).toBe(
      'Refus impossible.',
    );
  });
});
