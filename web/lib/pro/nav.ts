/// The capability-filtered pro sidebar model (team access R5b —
/// docs/design/web-team-access-r5.md §2.4). Pure: the sidebar renders
/// `navForMembership`; the server stays the authority (a deep link to a
/// hidden page renders its error state off the 403).

import { type Membership, hasCap } from './team';

export type ProNavEntry = {
  label: string;
  href: string;
  /// The capability that unlocks the entry — null = visible for every role.
  cap: string | null;
};

/// Same order as the historical owner sidebar. Aujourd'hui / Rendez-vous /
/// Profil are for ALL roles (the staff journal is server-filtered to their
/// own column; the member Profil is the slim personal view).
export const PRO_NAV: ProNavEntry[] = [
  { label: 'Aujourd’hui', href: '/pro', cap: null },
  { label: 'Rendez-vous', href: '/pro/rendez-vous', cap: null },
  { label: 'Clients', href: '/pro/clients', cap: 'clients.view' },
  { label: 'Catalogue', href: '/pro/catalogue', cap: 'catalogue.manage' },
  {
    label: 'Disponibilités',
    href: '/pro/disponibilites',
    cap: 'availability.manage',
  },
  { label: 'Équipe', href: '/pro/equipe', cap: 'members.manage' },
  { label: 'Avis', href: '/pro/avis', cap: 'profile.manage' },
  { label: 'Revenus', href: '/pro/revenus', cap: 'finances.view' },
  { label: 'Profil', href: '/pro/profil', cap: null },
  { label: 'Abonnement', href: '/pro/abonnement', cap: 'subscription.manage' },
];

/// An ABSENT membership (legacy owner payload) keeps the full sidebar —
/// hasCap's owner-shaped fallback.
export function navForMembership(
  membership: Membership | null | undefined,
): ProNavEntry[] {
  return PRO_NAV.filter((e) => e.cap === null || hasCap(membership, e.cap));
}
