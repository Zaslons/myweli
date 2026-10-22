import { cleanup, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { GoLiveCard } from '../components/pro/GoLiveCard';
import type { ProProfile } from '../lib/api/pro';

/// The draft card with the app's checklist (web-pro-golive-signup-like-app.md):
/// eight steps, the bar and « N étapes sur T terminées », « Mettre en ligne »
/// waiting only for the server's five.

const PROFILE = {
  account: { id: 'acc', businessName: 'Salon Awa', businessType: 'salon', phoneNumber: '+2250700000000', verificationStatus: 'pending' },
  provider: {
    id: 'p1',
    name: 'Salon Awa',
    status: 'draft',
    description: 'Un salon.',
    address: 'Rue des Jardins',
    commune: 'Cocody',
    latitude: 5.3,
    longitude: -3.9,
    services: [
      { id: 's1', name: 'A', price: 1, active: true },
      { id: 's2', name: 'B', price: 1, active: true },
      { id: 's3', name: 'C', price: 1, active: true },
    ],
    artists: [],
    imageUrls: ['a', 'b', 'c'],
    availability: { providerId: 'p1', weeklySchedule: { '0': [{ startTime: '09:00', endTime: '18:00' }] }, blockedDates: [], bufferMinutes: 0 },
  },
} as unknown as ProProfile;

/// The deposit policy defaults to a CHOSEN one (off, at the form's 30 %); a
/// test passes the server's never-chosen defaults (off, 0) to see the step
/// stay « Facultatif » (B7.7).
function stub({
  deposit = 200,
  kyc = { status: 'pending', documents: [] },
  policy = { depositRequired: false, depositPercentage: 0.3, cancellationWindowHours: 24 },
} = {}) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const u = String(url);
      if (u.startsWith('/api/pro/acompte')) {
        return new Response(JSON.stringify(policy), { status: deposit });
      }
      if (u === '/api/pro/kyc') return new Response(JSON.stringify(kyc), { status: 200 });
      return new Response('{}', { status: 404 });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('GoLiveCard — « Acompte & annulation » follows a SAVED choice (B7.7)', () => {
  it('never chosen (the server’s defaults: off, 0) → « Facultatif », and not counted', async () => {
    stub({ policy: { depositRequired: false, depositPercentage: 0, cancellationWindowHours: 24 } });
    render(<GoLiveCard profile={PROFILE} onPublished={() => {}} />);
    expect(await screen.findByText('5 étapes sur 7 terminées')).toBeInTheDocument();
    expect(screen.getByText('Facultatif')).toBeInTheDocument();
  });

  it('deposits ON → done', async () => {
    stub({ policy: { depositRequired: true, depositPercentage: 0.3, cancellationWindowHours: 24 } });
    render(<GoLiveCard profile={PROFILE} onPublished={() => {}} />);
    expect(await screen.findByText('6 étapes sur 8 terminées')).toBeInTheDocument();
    expect(screen.queryByText('Facultatif')).toBeNull();
  });
});

describe('GoLiveCard — the app’s checklist', () => {
  it('eight steps, and the progress the app shows', async () => {
    stub();
    render(<GoLiveCard profile={PROFILE} onPublished={() => {}} />);
    // Done: profile, location, services, availability, deposit, photos (6);
    // to do: team, KYC.
    expect(await screen.findByText('6 étapes sur 8 terminées')).toBeInTheDocument();
    // Named by the visible line — no new words (the app's own).
    const bar = screen.getByRole('progressbar', { name: /^6\sétapes sur 8 terminées$/ });
    expect(bar).toHaveAttribute('aria-valuenow', '6');
    expect(bar).toHaveAttribute('aria-valuemax', '8');
    const list = screen.getByRole('list');
    expect(within(list).getAllByRole('listitem')).toHaveLength(8);
    expect(within(list).getByText('Vérification (KYC)')).toBeInTheDocument();
  });

  it('« Mettre en ligne » waits only for the server’s five — the team and KYC can wait', async () => {
    stub();
    render(<GoLiveCard profile={PROFILE} onPublished={() => {}} />);
    await screen.findByText('6 étapes sur 8 terminées');
    expect(screen.getByRole('button', { name: 'Mettre en ligne' })).toBeEnabled();
  });

  it('a blocking step missing: the button waits, and the app’s sentence says why', async () => {
    stub();
    render(
      <GoLiveCard
        profile={{ ...PROFILE, provider: { ...PROFILE.provider, imageUrls: ['a'] } } as ProProfile}
        onPublished={() => {}}
      />,
    );
    await screen.findByText('5 étapes sur 8 terminées');
    expect(screen.getByRole('button', { name: 'Mettre en ligne' })).toBeDisabled();
    expect(
      screen.getByText('Complétez les étapes essentielles pour mettre votre profil en ligne.'),
    ).toBeInTheDocument();
  });
});
