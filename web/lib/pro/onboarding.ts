/// The web mirror of the server's go-live gate (docs/design/
/// pro-salon-lifecycle.md; `SalonProvisioningService.publishGate`) — the
/// server stays the authority, this only drives the checklist UI. Thresholds
/// = the app's onboarding (PRD FR-PRO-ONB-001): profile · ≥3 services ·
/// ≥3 photos · ≥1 open weekday.

import type { ProProfile } from '../api/pro';

export type ChecklistItem = {
  key: 'profile' | 'location' | 'services' | 'photos' | 'availability' | 'offer';
  label: string;
  href: string;
  done: boolean;
};

export function publishChecklist(
  provider: ProProfile['provider'],
  opts?: { offerLive?: boolean },
): ChecklistItem[] {
  const profileDone = Boolean(
    provider.description?.trim() &&
      provider.address?.trim() &&
      provider.commune?.trim(),
  );
  const services = (provider.services ?? []).filter(
    (s) => s.active !== false,
  ).length;
  const photos = (provider.imageUrls ?? []).length;
  const schedule = provider.availability?.weeklySchedule ?? {};
  const open = Object.values(schedule).some(
    (day) => Array.isArray(day) && day.length > 0,
  );
  return [
    {
      key: 'profile',
      label: 'Profil complet (description, adresse, commune)',
      href: '/pro/profil',
      done: profileDone,
    },
    {
      key: 'location',
      label: 'Position sur la carte',
      href: '/pro/profil',
      done: provider.latitude != null && provider.longitude != null,
    },
    {
      key: 'services',
      label: `Au moins 3 prestations (${services}/3)`,
      href: '/pro/catalogue',
      done: services >= 3,
    },
    {
      key: 'photos',
      label: `Au moins 3 photos (${photos}/3)`,
      href: '/pro/medias',
      done: photos >= 3,
    },
    {
      key: 'availability',
      label: 'Horaires d’ouverture',
      href: '/pro/disponibilites',
      done: open,
    },
    // Pricing pivot (team access R5a): publishing requires a live offer —
    // the server gate's `offer` missing-key, mirrored.
    {
      key: 'offer',
      label: 'Choisissez votre offre',
      href: '/pro/abonnement',
      done: Boolean(opts?.offerLive),
    },
  ];
}

export function canPublish(items: ChecklistItem[]): boolean {
  return items.every((i) => i.done);
}
