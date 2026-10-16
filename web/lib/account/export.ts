import type { Me } from '../api/account';
import type { Appointment } from './appointments';

/// The user's data-export document (parity 11.2 — the exact shape the app
/// builds in `core/utils/data_export.dart`). Pure and unit-tested; assembled
/// from already-loaded state, no dedicated endpoint.
export function buildUserDataExport({
  me,
  appointments,
  favoriteProviderNames,
  generatedAt,
}: {
  me: Me;
  appointments: Appointment[];
  favoriteProviderNames: string[];
  generatedAt?: Date;
}): Record<string, unknown> {
  return {
    generatedAt: (generatedAt ?? new Date()).toISOString(),
    profile: {
      id: me.id,
      phoneNumber: me.phoneNumber ?? null,
      name: me.name ?? null,
      email: me.email ?? null,
    },
    appointments: appointments.map((a) => ({
      id: a.id,
      providerId: a.providerId,
      date: a.appointmentDate,
      status: a.status,
      totalPrice: a.totalPrice ?? null,
      depositAmount: a.depositAmount ?? null,
      serviceIds: a.serviceIds ?? [],
    })),
    favorites: favoriteProviderNames,
  };
}

/// The export's own reads, in the order the file and the copy name them.
export type ExportSection = 'profile' | 'appointments' | 'favorites';

const SECTION_ORDER: ExportSection[] = ['profile', 'appointments', 'favorites'];

const SECTION_NAME: Record<ExportSection, string> = {
  profile: 'votre profil',
  appointments: 'vos rendez-vous',
  favorites: 'vos favoris',
};

/// The refusal when a read fails (docs/design/consumer-export-completeness.md
/// §4): nothing is offered, and the user is told which data is missing. The
/// app says the same sentence (`dataExportFailureMessage`).
export function exportFailureMessage(failed: ExportSection[]): string {
  const names = SECTION_ORDER.filter((s) => failed.includes(s)).map(
    (s) => SECTION_NAME[s],
  );
  const list =
    names.length > 1
      ? `${names.slice(0, -1).join(', ')} et ${names[names.length - 1]}`
      : names.join('');
  return `Impossible de charger ${list}. Vos données ne sont proposées que complètes : vérifiez votre connexion et réessayez.`;
}

/// The browser refused the clipboard. The download needs no permission, so
/// that is the way out.
export const EXPORT_COPY_FAILED =
  'La copie a échoué. Téléchargez le fichier avec « Télécharger (JSON) ».';
