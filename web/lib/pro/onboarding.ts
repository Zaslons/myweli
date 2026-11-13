/// The go-live checklist — the app's eight steps on the web
/// (docs/design/web-pro-golive-signup-like-app.md, owner decision;
/// `mobile/lib/core/utils/onboarding.dart` + `pro_onboarding_screen.dart`),
/// with its labels and its progress line. « Mettre en ligne » waits only for
/// the five steps the server's gate checks (`SalonProvisioningService
/// .publishGate`), and the server stays the authority: this drives the UI.
///
/// **No offer step** (since 2026-10-19, owner decision —
/// docs/design/web-pro-access.md §12): the server starts the 3 free months at
/// the first publish of a salon with no offer, as in the app.

import type { ProProfile } from '../api/pro';
import { countFr, pluralFr } from '../format';
import { allAreas, type LocalityTree } from '../localities';
import { slugify } from '../slug';
import type { KycStatus } from './kyc';
import { COMMUNE_FROM_LIST } from './salon-validation';

export type StepKey =
  | 'profile'
  | 'location'
  | 'services'
  | 'staff'
  | 'availability'
  | 'deposit'
  | 'verification'
  | 'photos';

export type StepStatus = 'done' | 'todo' | 'inProgress' | 'optional';

export type ChecklistItem = {
  key: StepKey;
  label: string;
  sublabel?: string;
  href: string;
  status: StepStatus;
  done: boolean;
  /// One of the five the server's gate checks.
  blocking: boolean;
};

/// What the profile does not carry: the business type (the team is optional
/// for an independent), whether the deposit policy could be read (the app's
/// « configured »), and the KYC status.
export type ChecklistExtras = {
  businessType?: string | null;
  depositConfigured: boolean;
  kyc: Pick<KycStatus, 'status' | 'documents'> | null;
  /// The localities tree (`useLocalities`), for R8. `null`/absent = not read
  /// (loading, failed): the profile step then keeps the rule without the
  /// commune list, and the server decides.
  localities?: LocalityTree | null;
};

/// R8 (docs/design/salon-go-live-approval.md §6.3, web-salon-validation.md
/// §5): the server's `validArea` (`SalonProvisioningService.publishGate`) —
/// an `areaId` (the server only ever stores a resolved one), or a commune that
/// names one of MyWeli's areas by slug, as `seedAreaForCommuneName` matches it
/// (`slug == slugify(commune)` or `slugify(name) == slugify(commune)`; the
/// web's `slugify` is the backend's twin). `null` — the list was not read, so
/// this side cannot tell.
export function communeIsKnown(
  provider: Pick<ProProfile['provider'], 'areaId' | 'commune'>,
  tree: LocalityTree | null | undefined,
): boolean | null {
  if (provider.areaId != null) return true;
  const commune = provider.commune?.trim() ?? '';
  if (!commune) return false;
  if (!tree || tree.countries.length === 0) return null;
  const wanted = slugify(commune);
  return allAreas(tree).some(
    ({ area }) => area.slug === wanted || slugify(area.name) === wanted,
  );
}

const MIN_SERVICES = 3;
const MIN_PHOTOS = 3;

export function publishChecklist(
  provider: ProProfile['provider'],
  extras: ChecklistExtras,
): ChecklistItem[] {
  const profileFilled = Boolean(
    provider.description?.trim() &&
      provider.address?.trim() &&
      provider.commune?.trim(),
  );
  // R8: filled AND an area the server knows. An unread list never blocks.
  const areaKnown = communeIsKnown(provider, extras.localities);
  const profileDone = profileFilled && areaKnown !== false;
  // ACTIVE services, as the server counts them.
  const services = (provider.services ?? []).filter(
    (s) => s.active !== false,
  ).length;
  const photos = (provider.imageUrls ?? []).length;
  const schedule = provider.availability?.weeklySchedule ?? {};
  const open = Object.values(schedule).some(
    (day) => Array.isArray(day) && day.length > 0,
  );
  const staffCount = (provider.artists ?? []).length;
  const independent = extras.businessType === 'other';

  const doneIf = (ok: boolean): StepStatus => (ok ? 'done' : 'todo');
  const staff: StepStatus =
    staffCount >= 1 ? 'done' : independent ? 'optional' : 'todo';
  const kyc = extras.kyc;
  const verification: StepStatus =
    kyc?.status === 'verified'
      ? 'done'
      : kyc?.status === 'pending' && (kyc.documents?.length ?? 0) > 0
        ? 'inProgress'
        : 'todo';

  const step = (
    key: StepKey,
    label: string,
    href: string,
    status: StepStatus,
    blocking: boolean,
    sublabel?: string,
  ): ChecklistItem => ({
    key,
    label,
    href,
    status,
    done: status === 'done',
    blocking,
    ...(sublabel ? { sublabel } : {}),
  });

  return [
    step(
      'profile',
      'Profil de l’entreprise',
      '/pro/profil',
      doneIf(profileDone),
      true,
      profileFilled && areaKnown === false ? COMMUNE_FROM_LIST : undefined,
    ),
    step(
      'location',
      'Position sur la carte',
      '/pro/profil',
      doneIf(provider.latitude != null && provider.longitude != null),
      true,
    ),
    step('services', 'Services (3 minimum)', '/pro/catalogue', doneIf(services >= MIN_SERVICES), true),
    step(
      'staff',
      'Équipe',
      '/pro/catalogue',
      staff,
      false,
      staff === 'optional' ? 'Optionnel pour les indépendants' : undefined,
    ),
    step('availability', 'Disponibilités', '/pro/disponibilites', doneIf(open), true),
    // Never a todo (B7.7, decision 24): done once a choice is saved, else
    // optional — a deposit is not a go-live condition.
    step(
      'deposit',
      'Acompte & annulation',
      '/pro/acompte',
      extras.depositConfigured ? 'done' : 'optional',
      false,
      extras.depositConfigured ? undefined : 'Facultatif',
    ),
    step(
      'verification',
      'Vérification (KYC)',
      '/pro/verification',
      verification,
      false,
      verification === 'inProgress' ? 'En cours' : undefined,
    ),
    step(
      'photos',
      'Photos (3 minimum)',
      '/pro/medias',
      doneIf(photos >= MIN_PHOTOS),
      true,
      'Ajouter des photos du salon',
    ),
  ];
}

/// The server's five — never the team, the deposit or the KYC.
export function canPublish(items: ChecklistItem[]): boolean {
  return items.filter((i) => i.blocking).every((i) => i.done);
}

/// Progress over the actionable steps (an optional one does not count).
export function checklistProgress(items: ChecklistItem[]): {
  done: number;
  total: number;
} {
  const actionable = items.filter((i) => i.status !== 'optional');
  return {
    done: actionable.filter((i) => i.done).length,
    total: actionable.length,
  };
}

/// The app's line: « 3 étapes sur 8 terminées » — French plural, so 0 and 1
/// are singular (« 0 étape sur 8 terminée »).
export function progressLabel({ done, total }: { done: number; total: number }): string {
  return `${countFr(done, 'étape', 'étapes')} sur ${total} ${pluralFr(done, 'terminée', 'terminées')}`;
}
