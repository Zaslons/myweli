import { describe, expect, it } from 'vitest';
import type { ProProfile } from '../lib/api/pro';
import {
  type ChecklistExtras,
  canPublish,
  checklistProgress,
  communeIsKnown,
  progressLabel,
  publishChecklist,
} from '../lib/pro/onboarding';
import type { LocalityTree } from '../lib/localities';

/// The go-live checklist — the app's eight steps on the web
/// (docs/design/web-pro-golive-signup-like-app.md, owner decision), its
/// labels, its progress line; « Mettre en ligne » still waits only for the
/// server's five (`publishGate`), which stays the authority.

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
    artists: [{ id: 'a1', name: 'Awa' }],
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

const ALL: ChecklistExtras = {
  businessType: 'salon',
  depositConfigured: true,
  kyc: { status: 'verified', documents: [] },
};

const byKey = (items: ReturnType<typeof publishChecklist>, key: string) =>
  items.find((i) => i.key === key)!;

describe('publishChecklist — the app’s eight steps', () => {
  it('in the app’s order, with the app’s words', () => {
    const items = publishChecklist(provider(), ALL);
    expect(items.map((i) => [i.key, i.label])).toEqual([
      ['profile', 'Profil de l’entreprise'],
      ['location', 'Position sur la carte'],
      ['services', 'Services (3 minimum)'],
      ['staff', 'Équipe'],
      ['availability', 'Disponibilités'],
      ['deposit', 'Acompte & annulation'],
      ['verification', 'Vérification (KYC)'],
      ['photos', 'Photos (3 minimum)'],
    ]);
    expect(byKey(items, 'photos').sublabel).toBe('Ajouter des photos du salon');
  });

  it('each deep-links to the page that completes it', () => {
    expect(publishChecklist(provider(), ALL).map((i) => i.href)).toEqual([
      '/pro/profil',
      '/pro/profil',
      '/pro/catalogue',
      '/pro/catalogue',
      '/pro/disponibilites',
      '/pro/acompte',
      '/pro/verification',
      '/pro/medias',
    ]);
  });

  it('the five the server gates block; team, deposit and KYC never do', () => {
    const items = publishChecklist(provider({ artists: [] }), {
      businessType: 'salon',
      depositConfigured: false,
      kyc: { status: 'pending', documents: [] },
    });
    expect(byKey(items, 'staff').status).toBe('todo');
    // B7.7: never a todo — optional until a choice is saved, and said.
    expect(byKey(items, 'deposit').status).toBe('optional');
    expect(byKey(items, 'deposit').sublabel).toBe('Facultatif');
    expect(byKey(items, 'verification').status).toBe('todo');
    expect(canPublish(items)).toBe(true);
    expect(items.filter((i) => i.blocking).map((i) => i.key)).toEqual([
      'profile',
      'location',
      'services',
      'availability',
      'photos',
    ]);
  });

  it('each missing blocking piece flips its step and blocks publish', () => {
    const check = (over: Partial<ProProfile['provider']>, key: string) => {
      const items = publishChecklist(provider(over), ALL);
      expect(byKey(items, key).done, key).toBe(false);
      expect(canPublish(items), key).toBe(false);
    };
    check({ description: '' }, 'profile');
    check({ commune: null }, 'profile');
    check({ latitude: null }, 'location');
    check(
      {
        services: [
          { id: 's1', name: 'A', price: 1, active: true },
          { id: 's2', name: 'B', price: 1, active: true },
          { id: 's3', name: 'C', price: 1, active: false }, // the server counts active ones
        ] as ProProfile['provider']['services'],
      },
      'services',
    );
    check({ imageUrls: ['a.jpg'] }, 'photos');
    check(
      {
        availability: {
          providerId: 'p1',
          weeklySchedule: {},
          blockedDates: [],
          bufferMinutes: 0,
        },
      } as Partial<ProProfile['provider']>,
      'availability',
    );
  });

  it('a submitted KYC still pending: « En cours »', () => {
    const items = publishChecklist(provider(), {
      ...ALL,
      kyc: { status: 'pending', documents: [{ type: 'idCard', key: 'k' }] },
    } as ChecklistExtras);
    expect(byKey(items, 'verification').status).toBe('inProgress');
    expect(byKey(items, 'verification').sublabel).toBe('En cours');
  });

  it('an independent: the team is optional — said, and not counted', () => {
    const items = publishChecklist(provider({ artists: [] }), {
      ...ALL,
      businessType: 'other',
    });
    expect(byKey(items, 'staff').status).toBe('optional');
    expect(byKey(items, 'staff').sublabel).toBe('Optionnel pour les indépendants');
    expect(checklistProgress(items)).toEqual({ done: 7, total: 7 });
  });
});

describe('the progress line — the app’s', () => {
  it('« N étapes sur T terminées », French plural (0 and 1 are singular)', () => {
    expect(progressLabel({ done: 0, total: 8 })).toBe('0\u00a0étape sur 8 terminée');
    expect(progressLabel({ done: 1, total: 8 })).toBe('1\u00a0étape sur 8 terminée');
    expect(progressLabel({ done: 3, total: 8 })).toBe('3\u00a0étapes sur 8 terminées');
  });

  it('counts the done steps over the actionable ones', () => {
    const items = publishChecklist(provider({ artists: [] }), {
      businessType: 'salon',
      depositConfigured: false,
      kyc: null,
    });
    // The deposit not chosen is optional — not counted (B7.7).
    expect(checklistProgress(items)).toEqual({ done: 5, total: 7 });
  });
});

/// R8 (docs/design/salon-go-live-approval.md §6.3, web-salon-validation.md §5):
/// « Profil de l’entreprise » reads the server's `validArea` — an `areaId`, or a
/// commune naming one of MyWeli's areas by slug (`seedAreaForCommuneName`).
/// Before, the step ticked on any commune text, and the button could be
/// enabled and then refused with every row ticked.
describe('R8 — the profile step follows the server’s commune list', () => {
  const TREE = {
    countries: [
      {
        code: 'CI',
        name: 'Côte d’Ivoire',
        cities: [
          {
            slug: 'abidjan',
            name: 'Abidjan',
            areas: [
              { id: 'a1', slug: 'cocody', name: 'Cocody', labelKind: 'commune' },
              { id: 'a2', slug: 'port-bouet', name: 'Port-Bouët', labelKind: 'commune' },
            ],
          },
        ],
      },
    ],
  } as unknown as LocalityTree;

  it('communeIsKnown: the server’s match — slug, or slugified name', () => {
    expect(communeIsKnown({ areaId: null, commune: 'Cocody' }, TREE)).toBe(true);
    expect(communeIsKnown({ areaId: null, commune: 'cocody' }, TREE)).toBe(true);
    expect(communeIsKnown({ areaId: null, commune: 'Port Bouet' }, TREE)).toBe(true);
    expect(communeIsKnown({ areaId: null, commune: 'Port-Bouët' }, TREE)).toBe(true);
    expect(communeIsKnown({ areaId: null, commune: 'Riviera Golf' }, TREE)).toBe(false);
  });

  it('an areaId is known whatever the text — the server only stores a resolved one', () => {
    expect(communeIsKnown({ areaId: 'a9', commune: 'Texte libre' }, TREE)).toBe(true);
    expect(communeIsKnown({ areaId: 'a9', commune: 'Texte libre' }, null)).toBe(true);
  });

  it('no commune → not known; the list unread (or empty) → cannot tell', () => {
    expect(communeIsKnown({ areaId: null, commune: '  ' }, TREE)).toBe(false);
    expect(communeIsKnown({ areaId: null, commune: 'Riviera Golf' }, null)).toBeNull();
    expect(communeIsKnown({ areaId: null, commune: 'Riviera Golf' }, undefined)).toBeNull();
    expect(
      communeIsKnown({ areaId: null, commune: 'Riviera Golf' }, { countries: [] } as LocalityTree),
    ).toBeNull();
  });

  it('a commune not in the list: the step stays to do, says why, and blocks', () => {
    const items = publishChecklist(provider({ areaId: null, commune: 'Riviera Golf' }), {
      ...ALL,
      localities: TREE,
    });
    expect(byKey(items, 'profile')).toMatchObject({
      status: 'todo',
      sublabel: 'Choisissez la commune dans la liste',
    });
    expect(canPublish(items)).toBe(false);
  });

  it('the list unread: today’s rule — the server decides', () => {
    const items = publishChecklist(provider({ areaId: null, commune: 'Riviera Golf' }), ALL);
    expect(byKey(items, 'profile').status).toBe('done');
    expect(canPublish(items)).toBe(true);
  });

  it('a field missing, even with an unknown commune: to do, without the commune line', () => {
    // The commune line is about the commune alone: say it only once the rest
    // is filled, or the owner fixes the commune and still finds the step to do.
    for (const missing of [{ description: '' }, { address: '' }]) {
      const items = publishChecklist(
        provider({ areaId: null, commune: 'Riviera Golf', ...missing }),
        { ...ALL, localities: TREE },
      );
      expect(byKey(items, 'profile').status, JSON.stringify(missing)).toBe('todo');
      expect(byKey(items, 'profile').sublabel, JSON.stringify(missing)).toBeUndefined();
    }
  });
});
