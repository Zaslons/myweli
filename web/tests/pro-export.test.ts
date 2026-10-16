import { describe, expect, it } from 'vitest';
import {
  buildProviderDataExport,
  exportFailureMessage,
  wholeClientBase,
} from '../lib/pro/export';
import type { SalonClientList } from '../lib/pro/clients';

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

/// docs/design/web-pro-export-completeness.md §4 — the refusal names every
/// missing section, in the file's order, whatever order they failed in.
describe('exportFailureMessage', () => {
  it.each([
    [['clients'], 'le fichier clients'],
    [['earnings', 'appointments'], 'les rendez-vous et les revenus'],
    [
      ['earnings', 'clients', 'appointments'],
      'les rendez-vous, le fichier clients et les revenus',
    ],
  ] as const)('%j → « %s »', (failed, names) => {
    expect(exportFailureMessage([...failed])).toBe(
      `Export interrompu : impossible de charger ${names}. Aucun fichier n'a été créé. Réessayez.`,
    );
  });
});

/// §5 — a walk is whole, or it is not used.
describe('wholeClientBase', () => {
  const c = (id: string) => ({
    id,
    displayName: id,
    tags: [],
    linked: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    visits: 0,
    noShows: 0,
  });
  const page = (
    n: number,
    total: number,
    ids: string[],
  ): SalonClientList => ({ items: ids.map(c), page: n, pageSize: 2, total });

  it('every page, every id once → the base, in walk order', () => {
    const base = wholeClientBase([
      page(1, 3, ['a', 'b']),
      page(2, 3, ['c']),
    ]);
    expect(base?.map((x) => x.id)).toEqual(['a', 'b', 'c']);
  });

  it('an empty base is whole', () => {
    expect(wholeClientBase([page(1, 0, [])])).toEqual([]);
  });

  it('no page at all is not a base', () => {
    expect(wholeClientBase([])).toBeNull();
  });

  it('a total that moved between pages → null', () => {
    expect(
      wholeClientBase([page(1, 3, ['a', 'b']), page(2, 4, ['c', 'd'])]),
    ).toBeNull();
  });

  it('a repeated row (so another was skipped) → null', () => {
    expect(
      wholeClientBase([page(1, 3, ['a', 'b']), page(2, 3, ['b'])]),
    ).toBeNull();
  });

  it('pages that fall short of the total → null', () => {
    expect(wholeClientBase([page(1, 3, ['a', 'b'])])).toBeNull();
  });
});
