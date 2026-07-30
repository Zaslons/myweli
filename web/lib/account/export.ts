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
