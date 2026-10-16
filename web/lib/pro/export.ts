/// The salon's data-export document (audit 11.5 — AUTH-005 for pros): the
/// account identity, the public listing, the catalogue and the salon's own
/// records. Pure and deterministic (unit-tested); assembled client-side from
/// the owner-scoped reads, like the consumer export.

import type { ProProfile } from '../api/pro';
import type { SalonClientList, SalonClientListItem } from './clients';
import type { EarningsData } from './earnings';
import type { ProAppointment } from './today';

export function buildProviderDataExport({
  profile,
  appointments,
  clients,
  earnings,
  generatedAt,
}: {
  profile: ProProfile;
  appointments: ProAppointment[];
  clients: SalonClientListItem[];
  earnings: EarningsData | null;
  generatedAt?: Date;
}) {
  const { account, provider } = profile;
  return {
    generatedAt: (generatedAt ?? new Date()).toISOString(),
    account: {
      id: account.id,
      businessName: account.businessName,
      businessType: account.businessType ?? null,
      phoneNumber: account.phoneNumber,
      verificationStatus: account.verificationStatus ?? 'pending',
    },
    salon: {
      id: provider.id,
      name: provider.name,
      description: provider.description ?? null,
      address: provider.address ?? null,
      commune: provider.commune ?? null,
      category: provider.category ?? null,
    },
    services: (provider.services ?? []).map((s) => ({
      name: s.name,
      price: s.price ?? null,
      durationMinutes: s.durationMinutes ?? null,
    })),
    artists: (provider.artists ?? []).map((a) => ({
      name: a.name,
      specialization: a.specialization ?? null,
    })),
    appointments: appointments.map((a) => ({
      id: a.id,
      date: a.appointmentDate,
      status: a.status,
      totalPrice: a.totalPrice ?? null,
    })),
    clients: clients.map((c) => ({
      name: c.displayName,
      phone: c.phone ?? null,
      tags: c.tags ?? [],
      visits: c.visits,
    })),
    earnings: earnings
      ? {
          totalEarnings: earnings.totalEarnings,
          transactions: earnings.transactions.length,
        }
      : null,
  };
}

/// The export's own reads, in the order the file and the copy name them.
export type ExportSection = 'appointments' | 'clients' | 'earnings';

export const SECTION_ORDER: ExportSection[] = ['appointments', 'clients', 'earnings'];

const SECTION_NAME: Record<ExportSection, string> = {
  appointments: 'les rendez-vous',
  clients: 'le fichier clients',
  earnings: 'les revenus',
};

/// The refusal when a read fails (docs/design/web-pro-export-completeness.md
/// §4): no file is made, and the salon is told which data is missing. The
/// buttons stay, and they are the retry.
export function exportFailureMessage(failed: ExportSection[]): string {
  const names = SECTION_ORDER.filter((s) => failed.includes(s)).map(
    (s) => SECTION_NAME[s],
  );
  const list =
    names.length > 1
      ? `${names.slice(0, -1).join(', ')} et ${names[names.length - 1]}`
      : names.join('');
  return `Export interrompu : impossible de charger ${list}. Aucun fichier n'a été créé. Réessayez.`;
}

/// The browser refused the clipboard. The download needs no permission, so
/// that is the way out.
export const EXPORT_COPY_FAILED =
  'La copie a échoué. Téléchargez le fichier avec « Exporter (JSON) ».';

/// The client base, from every page of one walk — or null when the walk does
/// not add up (§5). An offset walk over a list that moves (a client added, a
/// visit re-sorting the list) can repeat one row and skip another; a skipped
/// row is exactly the hole the export must not ship. So every page has to
/// report the same `total`, and the distinct ids have to reach it.
export function wholeClientBase(
  pages: SalonClientList[],
): SalonClientListItem[] | null {
  if (pages.length === 0) return null;
  const total = pages[0].total;
  if (pages.some((p) => p.total !== total)) return null;
  const byId = new Map<string, SalonClientListItem>();
  for (const page of pages) {
    for (const c of page.items) {
      if (!byId.has(c.id)) byId.set(c.id, c);
    }
  }
  return byId.size === total ? [...byId.values()] : null;
}
