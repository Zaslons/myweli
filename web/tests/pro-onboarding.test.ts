import { describe, expect, it } from 'vitest';
import type { ProProfile } from '../lib/api/pro';
import { canPublish, publishChecklist } from '../lib/pro/onboarding';

/// The go-live checklist (docs/design/pro-salon-lifecycle.md B2) — the web
/// mirror of the server's publishGate; the server stays the authority.

function provider(
  over: Partial<ProProfile['provider']> = {},
): ProProfile['provider'] {
  return {
    id: 'p1',
    name: 'Salon Awa',
    description: 'Un salon complet.',
    address: 'Rue des Jardins',
    commune: 'Cocody',
    latitude: 5.35,
    longitude: -3.99,
    services: [
      { id: 's1', name: 'A', price: 1000, active: true },
      { id: 's2', name: 'B', price: 1000, active: true },
      { id: 's3', name: 'C', price: 1000, active: true },
    ],
    imageUrls: ['a.jpg', 'b.jpg', 'c.jpg'],
    availability: {
      providerId: 'p1',
      weeklySchedule: { '0': [{ startTime: '09:00', endTime: '18:00' }] },
      blockedDates: [],
      bufferMinutes: 0,
    },
    ...over,
  } as ProProfile['provider'];
}

describe('publishChecklist', () => {
  it('a complete salon can publish', () => {
    const items = publishChecklist(provider());
    expect(items.every((i) => i.done)).toBe(true);
    expect(canPublish(items)).toBe(true);
  });

  it('each missing piece flips its item (and blocks publish)', () => {
    const byKey = (p: ProProfile['provider'], key: string) =>
      publishChecklist(p).find((i) => i.key === key)!;

    expect(byKey(provider({ description: '' }), 'profile').done).toBe(false);
    expect(byKey(provider({ commune: null }), 'profile').done).toBe(false);
    expect(
      byKey(
        provider({
          services: [
            { id: 's1', name: 'A', price: 1, active: true },
            { id: 's2', name: 'B', price: 1, active: true },
            { id: 's3', name: 'C', price: 1, active: false }, // inactive
          ],
        }),
        'services',
      ).done,
    ).toBe(false);
    expect(
      byKey(provider({ imageUrls: ['a.jpg', 'b.jpg'] }), 'photos').done,
    ).toBe(false);
    expect(
      byKey(provider({ latitude: null }), 'location').done,
    ).toBe(false);
    expect(
      byKey(
        provider({
          availability: {
            providerId: 'p1',
            weeklySchedule: {},
            blockedDates: [],
            bufferMinutes: 0,
          },
        }),
        'availability',
      ).done,
    ).toBe(false);

    expect(canPublish(publishChecklist(provider({ imageUrls: [] })))).toBe(
      false,
    );
  });

  it('items deep-link to the page that completes them', () => {
    const items = publishChecklist(provider());
    expect(items.map((i) => i.href)).toEqual([
      '/pro/profil',
      '/pro/profil',
      '/pro/catalogue',
      '/pro/medias',
      '/pro/disponibilites',
    ]);
  });
});
