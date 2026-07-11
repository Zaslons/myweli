import { describe, expect, it } from 'vitest';
import { buildUserDataExport } from '../lib/account/export';

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
