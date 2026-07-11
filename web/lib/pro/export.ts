/// The salon's data-export document (audit 11.5 — AUTH-005 for pros): the
/// account identity, the public listing, the catalogue and the salon's own
/// records. Pure and deterministic (unit-tested); assembled client-side from
/// the owner-scoped reads, like the consumer export.

import type { ProProfile } from '../api/pro';
import type { SalonClientListItem } from './clients';
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
