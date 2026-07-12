import { describe, expect, it } from 'vitest';
import type { Membership } from '../lib/pro/team';
import { PRO_NAV, navForMembership } from '../lib/pro/nav';

/// Team access R5b — the capability-filtered sidebar model. Presets mirror
/// the backend matrix (capabilities.dart rolePresets).

const OWNER_CAPS = [
  'availability.manage',
  'catalogue.manage',
  'clients.view',
  'deposit.manage',
  'finances.view',
  'journal.manage.all',
  'journal.manage.own',
  'journal.view.all',
  'journal.view.own',
  'members.manage',
  'profile.manage',
  'salon.publish',
  'subscription.manage',
];
const MANAGER_CAPS = [
  'availability.manage',
  'catalogue.manage',
  'clients.view',
  'journal.manage.all',
  'journal.manage.own',
  'journal.view.all',
  'journal.view.own',
  'profile.manage',
];
const RECEPTION_CAPS = [
  'clients.view',
  'journal.manage.all',
  'journal.manage.own',
  'journal.view.all',
  'journal.view.own',
];
const STAFF_CAPS = ['journal.manage.own', 'journal.view.own'];

function membership(role: Membership['role'], caps: string[]): Membership {
  return { role, capabilities: caps };
}

const labels = (m: Membership | null | undefined) =>
  navForMembership(m).map((e) => e.label);

describe('navForMembership', () => {
  it('owner → the full 10-entry sidebar', () => {
    expect(labels(membership('owner', OWNER_CAPS))).toEqual(
      PRO_NAV.map((e) => e.label),
    );
  });

  it('LEGACY null membership → owner-shaped (full sidebar)', () => {
    expect(labels(null)).toHaveLength(10);
    expect(labels(undefined)).toHaveLength(10);
  });

  it('manager → no Équipe / Revenus / Abonnement', () => {
    expect(labels(membership('manager', MANAGER_CAPS))).toEqual([
      'Aujourd’hui',
      'Rendez-vous',
      'Clients',
      'Catalogue',
      'Disponibilités',
      'Avis',
      'Profil',
    ]);
  });

  it('réception → planning + clients + profil only', () => {
    expect(labels(membership('reception', RECEPTION_CAPS))).toEqual([
      'Aujourd’hui',
      'Rendez-vous',
      'Clients',
      'Profil',
    ]);
  });

  it('staff (Collaborateur) → the minimal three', () => {
    expect(labels(membership('staff', STAFF_CAPS))).toEqual([
      'Aujourd’hui',
      'Rendez-vous',
      'Profil',
    ]);
  });

  it('every entry deep-links under /pro', () => {
    for (const e of PRO_NAV) expect(e.href.startsWith('/pro')).toBe(true);
  });
});
