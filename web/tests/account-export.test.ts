import { describe, expect, it } from 'vitest';
import {
  buildUserDataExport,
  exportFailureMessage,
} from '../lib/account/export';

/// Parity 11.2 — the web export mirrors the app's data_export.dart shape.
describe('buildUserDataExport', () => {
  it('assembles profile + appointments + favorites', () => {
    const doc = buildUserDataExport({
      me: {
        id: 'u1',
        name: 'Awa',
        email: 'awa@example.com',
        phoneNumber: '+2250700000000',
      },
      appointments: [
        {
          id: 'a1',
          providerId: 'p1',
          appointmentDate: '2026-12-01T09:00:00.000Z',
          status: 'confirmed',
          totalPrice: 15000,
          depositAmount: 0,
          serviceIds: ['s1'],
        },
      ],
      favoriteProviderNames: ['Beauté Divine'],
      generatedAt: new Date('2026-07-11T00:00:00.000Z'),
    });
    expect(doc.generatedAt).toBe('2026-07-11T00:00:00.000Z');
    expect((doc.profile as { email: string }).email).toBe('awa@example.com');
    expect((doc.appointments as unknown[]).length).toBe(1);
    expect(doc.favorites).toEqual(['Beauté Divine']);
  });

  it('nulls the optionals (no undefined leaks into the JSON)', () => {
    const doc = buildUserDataExport({
      me: { id: 'u1' },
      appointments: [
        {
          id: 'a1',
          providerId: 'p1',
          appointmentDate: '2026-12-01T09:00:00.000Z',
          status: 'pending',
        },
      ],
      favoriteProviderNames: [],
    });
    const profile = doc.profile as Record<string, unknown>;
    expect(profile.name).toBeNull();
    const appt = (doc.appointments as Record<string, unknown>[])[0];
    expect(appt.totalPrice).toBeNull();
    expect(appt.serviceIds).toEqual([]);
  });
});

/// The refusal when a read fails (docs/design/consumer-export-completeness.md
/// §4) — the app's `dataExportFailureMessage` says the same sentence.
describe('exportFailureMessage', () => {
  const TAIL =
    'Vos données ne sont proposées que complètes : vérifiez votre connexion et réessayez.';

  it('names one section', () => {
    expect(exportFailureMessage(['favorites'])).toBe(
      `Impossible de charger vos favoris. ${TAIL}`,
    );
  });

  it('joins two with « et », in the file order whatever order they failed in', () => {
    expect(exportFailureMessage(['favorites', 'appointments'])).toBe(
      `Impossible de charger vos rendez-vous et vos favoris. ${TAIL}`,
    );
  });

  it('joins three with « , » then « et »', () => {
    expect(
      exportFailureMessage(['favorites', 'profile', 'appointments']),
    ).toBe(
      `Impossible de charger votre profil, vos rendez-vous et vos favoris. ${TAIL}`,
    );
  });
});
