import { describe, expect, it } from 'vitest';
import { buildProviderDataExport } from '../lib/pro/export';

describe('buildProviderDataExport (audit 11.5 — AUTH-005 for pros)', () => {
  it('assembles the salon document from the owner-scoped reads', () => {
    const doc = buildProviderDataExport({
      profile: {
        account: {
          id: 'acc1',
          businessName: 'Salon X',
          phoneNumber: '+22500',
          verificationStatus: 'verified',
        },
        provider: {
          id: 'p1',
          name: 'Salon X',
          commune: 'Cocody',
          services: [{ id: 's1', name: 'Tresses', price: 15000, durationMinutes: 120 }],
          artists: [{ id: 'a1', name: 'Awa', specialization: 'Tresses' }],
        },
      },
      appointments: [
        {
          id: 'x1',
          serviceIds: ['s1'],
          appointmentDate: '2026-07-01T09:00:00.000Z',
          status: 'completed',
          totalPrice: 15000,
        },
      ],
      clients: [
        {
          id: 'sc1',
          displayName: 'Koffi',
          phone: '+22501',
          tags: ['VIP'],
          linked: true,
          createdAt: '2026-01-01T00:00:00.000Z',
          visits: 4,
          noShows: 0,
        },
      ],
      earnings: { totalEarnings: 45000, transactions: [] as never[] },
      generatedAt: new Date('2026-07-11T00:00:00.000Z'),
    });

    expect(doc.generatedAt).toBe('2026-07-11T00:00:00.000Z');
    expect(doc.account.businessName).toBe('Salon X');
    expect(doc.services[0]).toEqual({
      name: 'Tresses',
      price: 15000,
      durationMinutes: 120,
    });
    expect(doc.clients[0]).toEqual({
      name: 'Koffi',
      phone: '+22501',
      tags: ['VIP'],
      visits: 4,
    });
    expect(doc.earnings).toEqual({ totalEarnings: 45000, transactions: 0 });
  });

  it('tolerates a bare profile (no catalogue, no earnings)', () => {
    const doc = buildProviderDataExport({
      profile: {
        account: { id: 'acc1', businessName: 'X', phoneNumber: '+22500' },
        provider: { id: 'p1', name: 'X' },
      },
      appointments: [],
      clients: [],
      earnings: null,
    });
    expect(doc.services).toEqual([]);
    expect(doc.earnings).toBeNull();
    expect(doc.account.verificationStatus).toBe('pending');
  });
});
