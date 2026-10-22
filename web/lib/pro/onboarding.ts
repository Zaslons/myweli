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
import type { KycStatus } from './kyc';

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
};

const MIN_SERVICES = 3;
const MIN_PHOTOS = 3;

export function publishChecklist(
  provider: ProProfile['provider'],
  extras: ChecklistExtras,
): ChecklistItem[] {
  const profileDone = Boolean(
    provider.description?.trim() &&
      provider.address?.trim() &&
      provider.commune?.trim(),
  );
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
    step('profile', 'Profil de l’entreprise', '/pro/profil', doneIf(profileDone), true),
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
