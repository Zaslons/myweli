import { describe, expect, it } from 'vitest';
import type { ProProfile } from '../lib/api/pro';
import {
  type ChecklistExtras,
  canPublish,
  checklistProgress,
  progressLabel,
  publishChecklist,
} from '../lib/pro/onboarding';

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
