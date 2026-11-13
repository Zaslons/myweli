import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { GoLiveCard } from '../components/pro/GoLiveCard';
import type { ProProfile } from '../lib/api/pro';
import type { SalonValidation } from '../lib/pro/salon-validation';
import { resetLocalitiesClientCache } from '../lib/use-localities';

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
  resetLocalitiesClientCache();
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

// --- B0.18: where the salon stands with MyWeli's validation ----------------
// docs/design/web-salon-validation.md §4.1 (parent: salon-go-live-approval.md
// §6.1). `validation` absent = a server before B0.18 (the tests above: today's
// card); present = one branch per state.

const TREE = {
  countries: [
    {
      code: 'CI',
      name: 'Côte d’Ivoire',
      cities: [
        {
          slug: 'abidjan',
          name: 'Abidjan',
          areas: [{ id: 'ci-abj-cocody', slug: 'cocody', name: 'Cocody', labelKind: 'commune' }],
        },
      ],
    },
  ],
};

type Answer = { status: number; body?: unknown; raw?: string };

/// The card's reads, plus the localities tree and the publish answer; every
/// call is recorded.
function serve({
  publish = { status: 202, body: { validation: { state: 'pending', submittedAt: '2026-11-13T10:00:00Z', wentLive: false } } } as Answer,
  localities = { status: 200, body: TREE } as Answer,
} = {}) {
  const calls: string[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      calls.push(`${init?.method ?? 'GET'} ${u}`);
      const answer = (a: Answer) =>
        new Response(a.raw ?? JSON.stringify(a.body ?? {}), { status: a.status });
      if (u.startsWith('/api/pro/acompte')) {
        return answer({ status: 200, body: { depositRequired: false, depositPercentage: 0.3, cancellationWindowHours: 24 } });
      }
      if (u === '/api/pro/kyc') return answer({ status: 200, body: { status: 'pending', documents: [] } });
      if (u === '/api/localities') return answer(localities);
      if (u === '/api/pro/publish') return answer(publish);
      return new Response('{}', { status: 404 });
    }),
  );
  return calls;
}

const withState = (
  validation: SalonValidation | null,
  provider: Partial<ProProfile['provider']> = {},
): ProProfile =>
  ({
    ...PROFILE,
    provider: { ...PROFILE.provider, areaId: 'ci-abj-cocody', ...provider },
    validation,
  }) as ProProfile;

const PENDING: SalonValidation = { state: 'pending', submittedAt: '2026-11-12T23:30:00Z', wentLive: false };
const REFUSED = (code: 'photos' | 'outside_ci' | 'other', note?: string): SalonValidation => ({
  state: 'refused',
  submittedAt: '2026-11-12T09:00:00Z',
  decidedAt: '2026-11-13T09:00:00Z',
  wentLive: false,
  refusal: { code, final: code === 'outside_ci', ...(note ? { note } : {}) },
});

describe('GoLiveCard — B0.18, each state of §6.1', () => {
  it('never asked: today’s heading, « Demander la mise en ligne »', async () => {
    serve();
    render(<GoLiveCard profile={withState(null)} onPublished={() => {}} />);
    await screen.findByText('6 étapes sur 8 terminées');
    expect(screen.getByText('Votre salon n’est pas encore en ligne')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Demander la mise en ligne' })).toBeEnabled();
    expect(screen.queryByRole('button', { name: 'Mettre en ligne' })).toBeNull();
  });

  it('never asked, a step missing: the button waits, and the hint names the request', async () => {
    serve();
    render(<GoLiveCard profile={withState(null, { imageUrls: ['a'] })} onPublished={() => {}} />);
    await screen.findByText('5 étapes sur 8 terminées');
    expect(screen.getByRole('button', { name: 'Demander la mise en ligne' })).toBeDisabled();
    expect(
      screen.getByText('Complétez les étapes essentielles pour demander la mise en ligne.'),
    ).toBeInTheDocument();
  });

  it('pending: the banner, « Demande envoyée le … » in the salon’s clock, no button — the steps stay', async () => {
    serve();
    render(
      <GoLiveCard
        profile={withState(PENDING, { timezone: 'Africa/Libreville' })}
        onPublished={() => {}}
      />,
    );
    await screen.findByText('6 étapes sur 8 terminées');
    expect(screen.getByText('En cours de validation')).toBeInTheDocument();
    expect(
      screen.getByText(
        'Nous examinons votre salon avant sa mise en ligne. Nous vous préviendrons dès que c’est fait.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByText('Demande envoyée le 13 novembre 2026')).toBeInTheDocument();
    expect(screen.queryByRole('button')).toBeNull();
    expect(screen.queryByText('Votre salon n’est pas encore en ligne')).toBeNull();
    // Every step stays editable while pending (parent §6.2).
    expect(within(screen.getByRole('list')).getAllByRole('listitem')).toHaveLength(8);
    expect(screen.getByRole('link', { name: 'Aperçu de ma page' })).toHaveAttribute('href', '/pro/apercu');
  });

  it('validated, still finishing: read as pending', async () => {
    serve();
    render(
      <GoLiveCard
        profile={withState({ state: 'approved', submittedAt: '2026-11-12T10:00:00Z', wentLive: false })}
        onPublished={() => {}}
      />,
    );
    await screen.findByText('6 étapes sur 8 terminées');
    expect(screen.getByText('En cours de validation')).toBeInTheDocument();
    expect(screen.getByText('Demande envoyée le 12 novembre 2026')).toBeInTheDocument();
  });

  it('refused, fixable: the reason, the note on its own line, « Renvoyer pour validation »', async () => {
    serve();
    render(
      <GoLiveCard profile={withState(REFUSED('photos', 'Plus de lumière.'))} onPublished={() => {}} />,
    );
    await screen.findByText('6 étapes sur 8 terminées');
    expect(screen.getByText('Mise en ligne refusée')).toBeInTheDocument();
    expect(
      screen.getByText('Les photos ne montrent pas assez clairement le salon et son travail.'),
    ).toBeInTheDocument();
    expect(screen.getByText('Plus de lumière.')).toBeInTheDocument();
    expect(
      screen.getByText('Modifiez votre salon, puis renvoyez-le pour validation.'),
    ).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Renvoyer pour validation' })).toBeEnabled();
  });

  it('refused « Autre »: the note alone, as text — never markup', async () => {
    serve();
    render(
      <GoLiveCard
        profile={withState(REFUSED('other', '<b>Nom</b> différent'))}
        onPublished={() => {}}
      />,
    );
    await screen.findByText('6 étapes sur 8 terminées');
    expect(screen.getByText('<b>Nom</b> différent')).toBeInTheDocument();
    expect(document.querySelector('b')).toBeNull();
  });

  it('refused for good: the reason and the note, no button, no hint', async () => {
    serve();
    render(
      <GoLiveCard
        profile={withState(REFUSED('outside_ci', 'Le pin est à Dakar.'), { imageUrls: ['a'] })}
        onPublished={() => {}}
      />,
    );
    await screen.findByText('5 étapes sur 8 terminées');
    expect(screen.getByText(/MyWeli n’est pas encore disponible dans votre pays/)).toBeInTheDocument();
    expect(screen.getByText('Le pin est à Dakar.')).toBeInTheDocument();
    expect(screen.queryByRole('button')).toBeNull();
    expect(screen.queryByText(/renvoy/i)).toBeNull();
    expect(screen.queryByText(/Complétez les étapes essentielles/)).toBeNull();
  });

  it('no longer online, offer live: « Vous pouvez le remettre en ligne. » and « Remettre en ligne »', async () => {
    serve();
    render(
      <GoLiveCard
        profile={withState({ state: 'approved', wentLive: true, offerLive: true })}
        onPublished={() => {}}
      />,
    );
    await screen.findByText('6 étapes sur 8 terminées');
    expect(screen.getByText('Votre salon n’est plus en ligne')).toBeInTheDocument();
    expect(screen.getByText('Vous pouvez le remettre en ligne.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Remettre en ligne' })).toBeEnabled();
  });

  it('no longer online, offer lapsed: the billing sentence and « Mon abonnement » — no publish', async () => {
    serve();
    render(
      <GoLiveCard
        profile={withState({ state: 'approved', wentLive: true, offerLive: false })}
        onPublished={() => {}}
      />,
    );
    await screen.findByText('6 étapes sur 8 terminées');
    expect(
      screen.getByText(
        'Votre salon n’est plus visible des clients. Contactez-nous pour réactiver — vos données sont intactes.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Mon abonnement' })).toHaveAttribute(
      'href',
      '/pro/abonnement',
    );
    expect(screen.queryByRole('button')).toBeNull();
  });

  it('suspended (new server): the banner alone — no checklist, no button, no reads', async () => {
    const calls = serve();
    render(
      <GoLiveCard
        profile={withState(null, { status: 'suspended' })}
        onPublished={() => {}}
      />,
    );
    expect(screen.getByText('Votre salon est suspendu')).toBeInTheDocument();
    expect(screen.getByText('Contactez MyWeli pour en savoir plus.')).toBeInTheDocument();
    expect(screen.queryByRole('progressbar')).toBeNull();
    expect(screen.queryByRole('button')).toBeNull();
    // Its only control: on the 48px floor (SYSTEM §13).
    expect(screen.getByRole('link', { name: 'Aperçu de ma page' }).className).toMatch(/\bmin-h-12\b/);
    await new Promise((r) => setTimeout(r, 20));
    expect(calls).toEqual([]);
  });
});

describe('GoLiveCard — B0.18, what the publish answered', () => {
  async function tap(profile: ProProfile, publish: Answer) {
    const onPublished = vi.fn();
    const onStale = vi.fn();
    serve({ publish });
    render(<GoLiveCard profile={profile} onPublished={onPublished} onStale={onStale} />);
    await screen.findByText(/étapes? sur \d+ terminées?/);
    fireEvent.click(screen.getByRole('button'));
    return { onPublished, onStale };
  }

  it('202 → a REQUEST, with the body’s validation', async () => {
    const v = { state: 'pending', submittedAt: '2026-11-13T10:00:00Z', wentLive: false };
    const { onPublished } = await tap(withState(null), { status: 202, body: { validation: v } });
    await waitFor(() =>
      expect(onPublished).toHaveBeenCalledWith({ kind: 'requested', validation: v }),
    );
  });

  it('a 202 whose body cannot be read is still a request (the page re-reads)', async () => {
    const { onPublished } = await tap(withState(null), { status: 202, raw: '<html>' });
    await waitFor(() =>
      expect(onPublished).toHaveBeenCalledWith({ kind: 'requested', validation: undefined }),
    );
  });

  it('200 → live (the republish)', async () => {
    const { onPublished } = await tap(
      withState({ state: 'approved', wentLive: true, offerLive: true }),
      { status: 200, body: { id: 'p1', status: 'active' } },
    );
    await waitFor(() => expect(onPublished).toHaveBeenCalledWith({ kind: 'live' }));
  });

  it('a card loaded from the old server gets a 202 (the backend deployed meanwhile) → a request', async () => {
    const { onPublished } = await tap(PROFILE, {
      status: 202,
      body: { validation: { state: 'pending', wentLive: false } },
    });
    await waitFor(() =>
      expect(onPublished).toHaveBeenCalledWith({
        kind: 'requested',
        validation: { state: 'pending', wentLive: false },
      }),
    );
  });

  it('the old server’s 200 stays « live » (today)', async () => {
    const { onPublished } = await tap(PROFILE, { status: 200, body: { id: 'p1', status: 'active' } });
    await waitFor(() => expect(onPublished).toHaveBeenCalledWith({ kind: 'live' }));
  });

  it('409 validation_refused_final → said, and the page re-reads (the card was older than the decision)', async () => {
    const { onPublished, onStale } = await tap(withState(REFUSED('photos')), {
      status: 409,
      body: { error: 'validation_refused_final' },
    });
    await waitFor(() => expect(onStale).toHaveBeenCalledTimes(1));
    expect(onPublished).not.toHaveBeenCalled();
    // Said even if the re-read never lands: a write never fails in silence.
    expect(screen.getByRole('alert')).toHaveTextContent('Mise en ligne refusée');
  });

  it('409 incomplete keeps today’s line', async () => {
    const { onPublished } = await tap(withState(null), {
      status: 409,
      body: { error: 'incomplete', missing: ['photos'] },
    });
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Certaines étapes ne sont pas terminées. Vérifiez la liste.',
    );
    expect(onPublished).not.toHaveBeenCalled();
  });
});

describe('GoLiveCard — R8: « Profil de l’entreprise » follows the server’s commune list', () => {
  // The list's answer must have LANDED before a test reads the step: while
  // it loads, the rule is today's (never blocked), so an assertion made
  // then would pass whatever the list does.
  let calls: string[] = [];
  const free = (commune: string, localities?: Answer) => {
    calls = serve(localities ? { localities } : {});
    render(
      <GoLiveCard
        profile={withState(null, { areaId: null, commune })}
        onPublished={() => {}}
      />,
    );
  };
  const listAnswered = async () => {
    await waitFor(() => expect(calls).toContain('GET /api/localities'));
    await new Promise((r) => setTimeout(r, 30));
  };
  const profileRow = () =>
    screen.getByText('Profil de l’entreprise').closest('li') as HTMLElement;

  it('a commune from the list, by slug (accents and case aside) → done', async () => {
    free('  COCODY ');
    await listAnswered();
    await screen.findByText('6 étapes sur 8 terminées');
    expect(within(profileRow()).queryByRole('link', { name: 'Compléter' })).toBeNull();
    expect(screen.getByRole('button', { name: 'Demander la mise en ligne' })).toBeEnabled();
  });

  it('a commune not in the list → to do, with why, and the button waits', async () => {
    free('Quartier Inconnu');
    await screen.findByText('5 étapes sur 8 terminées');
    expect(within(profileRow()).getByRole('link', { name: 'Compléter' })).toHaveAttribute(
      'href',
      '/pro/profil',
    );
    expect(within(profileRow()).getByText('Choisissez la commune dans la liste')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Demander la mise en ligne' })).toBeDisabled();
  });

  it('an areaId → done whatever the commune’s text (the server stores only resolved ones)', async () => {
    serve();
    render(
      <GoLiveCard
        profile={withState(null, { areaId: 'ci-abj-cocody', commune: 'Texte libre' })}
        onPublished={() => {}}
      />,
    );
    await screen.findByText('6 étapes sur 8 terminées');
    expect(screen.queryByText('Choisissez la commune dans la liste')).toBeNull();
  });

  it('the list could not be read → today’s rule: never blocked by a failed read', async () => {
    free('Quartier Inconnu', { status: 500, body: {} });
    await listAnswered();
    await screen.findByText('6 étapes sur 8 terminées');
    expect(screen.queryByText('Choisissez la commune dans la liste')).toBeNull();
    expect(screen.getByRole('button', { name: 'Demander la mise en ligne' })).toBeEnabled();
  });

  it('nothing filled → to do, without the commune line', async () => {
    free('');
    await screen.findByText('5 étapes sur 8 terminées');
    expect(screen.queryByText('Choisissez la commune dans la liste')).toBeNull();
  });
});
