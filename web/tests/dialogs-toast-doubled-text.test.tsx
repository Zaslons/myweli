import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import resolveConfig from 'tailwindcss/resolveConfig';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/pro',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('@sentry/nextjs', () => ({ captureMessage: vi.fn(), captureException: vi.fn() }));
vi.mock('next/dynamic', () => ({ default: () => () => null }));

import tailwindConfig from '../tailwind.config';
import { Modal } from '../components/Modal';
import { Toast } from '../components/Toast';
import { AccountClient } from '../components/account/AccountClient';
import { ChangeRoleDialog } from '../components/pro/ChangeRoleDialog';
import { EquipeClient } from '../components/pro/EquipeClient';
import { InviteMemberDialog } from '../components/pro/InviteMemberDialog';
import { ManualBookingDialog } from '../components/pro/ManualBookingDialog';
import type { ProProfile } from '../lib/api/pro';
import type { TeamMember } from '../lib/pro/team';
import { spacing } from '../styles/tokens';

/// The dialogs, the toast and `/mon-compte` at doubled text
/// (docs/design/web-dialogs-toast-doubled-text.md; WEB-SYSTEM §8, §9).
///
/// jsdom lays nothing out, so this file holds the STRUCTURE that makes the
/// geometry right; `type-overflow.spec.ts` (« the dialogs, the toast and
/// /mon-compte at doubled text ») measures it in a real browser. Measured on
/// #902's head before the change, at 320×568: a dialog taller than the screen
/// was cut at both ends with nothing to scroll (« Changer le rôle » 988 px tall
/// in the Android mode, « Inviter un membre » 716 px at normal text); a row of
/// a field and a button, and a footer of two buttons, ran off the screen; the
/// toast's pill ran off both edges with a one-word salon name; `/mon-compte`
/// grew to 466 px, then to 324.

const classes = (el: Element | null) => (el?.getAttribute('class') ?? '').split(/\s+/).filter(Boolean);

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

// --- The shared dialog --------------------------------------------------------

describe('Modal — a panel taller than the screen scrolls inside it', () => {
  const panelOf = () => screen.getByRole('dialog').querySelector(':scope > [tabindex="-1"]');

  it.each([
    ['the default panel', undefined],
    ['a dialog’s own panel (BlockedDatesDialog’s shape)', 'w-full max-w-md rounded-xl border border-border bg-secondary p-m sm:p-l'],
    ['a dialog’s own panel (BeforeAfterViewer’s shape)', 'w-full max-w-3xl rounded-xl border border-border bg-secondary p-m'],
  ])('%s: at most the screen’s height, scrolling, the page behind not scrolled on', (_, panelClassName) => {
    render(
      <Modal title="Changer le rôle" onClose={() => {}} panelClassName={panelClassName}>
        <button type="button">Annuler</button>
      </Modal>,
    );
    // Outside `panelClassName`, so no dialog can lose them by passing its own.
    expect(classes(panelOf())).toEqual(expect.arrayContaining(['max-h-full', 'overflow-y-auto', 'overscroll-contain']));
  });

  it('« Nouveau rendez-vous » no longer carries its own viewport-relative scroll box: the Modal’s rule is the one', () => {
    const source = readFileSync(join(__dirname, '../components/pro/ManualBookingDialog.tsx'), 'utf8');
    expect(source).not.toMatch(/max-h-\[90vh\]/);
  });
});

/// Every file that renders a `<Modal>` — discovered, not listed, so the next
/// dialog written is the one this exists for (SYSTEM.md §21 row 66's shape).
function dialogSources(): [file: string, source: string][] {
  const root = join(__dirname, '..');
  const out: [string, string][] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) walk(path);
      else if (/\.tsx$/.test(name)) {
        const source = readFileSync(path, 'utf8');
        if (/<Modal\b/.test(source)) out.push([relative(root, path), source]);
      }
    }
  };
  walk(join(root, 'components'));
  walk(join(root, 'app'));
  return out;
}

describe('every dialog’s row of buttons wraps (WEB-SYSTEM §9 rule 1)', () => {
  const sources = dialogSources();

  it('finds the dialogs (the vacuity guard)', () => {
    expect(sources.length).toBeGreaterThanOrEqual(10);
  });

  it.each(sources)('%s: a `justify-end` row of more than one control is `flex-wrap`', (_, source) => {
    // A row with a gap holds more than one control; a row of one (the
    // before/after viewer's « Fermer ») has nothing to wrap.
    const rows = [...source.matchAll(/className="([^"]*)"/g)]
      .map((m) => m[1].split(/\s+/))
      .filter((c) => c.includes('flex') && c.includes('justify-end') && c.some((x) => x.startsWith('gap-')));
    expect(rows.filter((c) => !c.includes('flex-wrap')).map((c) => c.join(' '))).toEqual([]);
  });
});

// --- The team's dialogs -------------------------------------------------------

const ARTISTS = [
  { id: 'a1', name: 'Awa' },
  { id: 'a2', name: 'Binta' },
] as never[];

const member = (over: Partial<Record<string, unknown>> = {}): TeamMember =>
  ({
    id: 'm1',
    providerId: 'p1',
    accountId: 'acc2',
    email: 'awa@example.com',
    role: 'reception',
    artistId: null,
    artistName: null,
    status: 'active',
    invitedAt: '2026-11-20T00:00:00.000Z',
    acceptedAt: '2026-11-21T00:00:00.000Z',
    revokedAt: null,
    expiresAt: null,
    expired: false,
    resendsLeft: 3,
    ...over,
  }) as unknown as TeamMember;

/// The field and its button: the row that holds `field`.
function rowOf(field: HTMLElement) {
  const row = field.parentElement as HTMLElement;
  expect(row.contains(field)).toBe(true);
  return row;
}

/// The row holds a field and a button and wraps; the field may narrow and
/// keeps its natural width when there is room (`flex-auto`, not `flex-1`,
/// whose zero basis would squeeze it beside the button instead of wrapping).
function expectFieldRowWraps(field: HTMLElement) {
  const row = rowOf(field);
  expect(within(row).getByRole('button')).toBeInTheDocument();
  expect(classes(row), 'the row does not wrap').toEqual(expect.arrayContaining(['flex', 'flex-wrap']));
  expect(classes(field), 'the field cannot narrow below its intrinsic width').toContain('min-w-0');
  expect(classes(field)).toContain('flex-auto');
  expect(classes(field)).not.toContain('flex-1');
}

/// The footer: the row that holds the dialog's last button.
function expectFooterWraps(dialog: HTMLElement, action: string) {
  const footer = within(dialog).getByRole('button', { name: action }).parentElement as HTMLElement;
  expect(within(footer).getByRole('button', { name: 'Annuler' })).toBeInTheDocument();
  expect(classes(footer), `« ${action} »'s footer does not wrap`).toEqual(
    expect.arrayContaining(['flex', 'flex-wrap', 'justify-end']),
  );
}

describe('« Changer le rôle »', () => {
  const open = (role = 'reception') =>
    render(
      <ChangeRoleDialog
        member={member({ role })}
        providerId="p1"
        artists={ARTISTS as never}
        onArtistCreated={() => {}}
        onClose={() => {}}
        onChanged={() => {}}
      />,
    );

  it('its footer wraps', () => {
    open();
    expectFooterWraps(screen.getByRole('dialog'), 'Enregistrer');
  });

  it('the fiche row (the select and « Créer une fiche ») wraps; its select may narrow', () => {
    open();
    fireEvent.click(screen.getByRole('button', { name: /^Collaborateur/ }));
    expectFieldRowWraps(screen.getByLabelText('Fiche employé'));
  });

  it('the name row (the field and « Créer ») wraps; its field may narrow', () => {
    open('staff');
    fireEvent.click(screen.getByRole('button', { name: 'Créer une fiche' }));
    expectFieldRowWraps(screen.getByPlaceholderText('Nom de l’employé'));
  });
});

describe('« Inviter un membre »', () => {
  const open = () =>
    render(
      <InviteMemberDialog providerId="p1" artists={ARTISTS as never} onArtistCreated={() => {}} onClose={() => {}} onInvited={() => {}} />,
    );

  it('its footer wraps', () => {
    open();
    expectFooterWraps(screen.getByRole('dialog'), 'Envoyer l’invitation');
  });

  it('the fiche row wraps; its select may narrow', () => {
    open();
    fireEvent.click(screen.getByRole('button', { name: /^Collaborateur/ }));
    expectFieldRowWraps(screen.getByLabelText('Fiche employé'));
  });

  it('the name row wraps; its field may narrow', () => {
    open();
    fireEvent.click(screen.getByRole('button', { name: /^Collaborateur/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Créer une fiche' }));
    expectFieldRowWraps(screen.getByPlaceholderText('Nom de l’employé'));
  });
});

describe('« Révoquer l’accès »', () => {
  it('its footer wraps', async () => {
    const owner = member({ id: 'm-owner', email: 'proprietaire@beaute-divine.test', role: 'owner' });
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        const u = String(url);
        if (u === '/api/pro/me') {
          return new Response(
            JSON.stringify({
              account: { id: 'acc1', email: 'proprietaire@beaute-divine.test' },
              provider: { id: 'p1', name: 'Beauté Divine', artists: [{ id: 'a1', name: 'Awa' }] },
              membership: { role: 'owner', capabilities: ['members.manage', 'profile.manage', 'subscription.manage'] },
            }),
            { status: 200 },
          );
        }
        if (u === '/api/pro/members') return new Response(JSON.stringify({ items: [owner, member()] }), { status: 200 });
        if (u.startsWith('/api/pro/salon-subscription')) {
          return new Response(
            JSON.stringify({ tier: 'pro', status: 'trial', trialEndsAt: '2026-12-12T00:00:00.000Z', paidUntil: null, graceEndsAt: null, unpublishedForBilling: false, seats: { cap: 5, used: 2 } }),
            { status: 200 },
          );
        }
        return new Response('{}', { status: 404 });
      }),
    );
    render(<EquipeClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Actions pour awa@example.com' }));
    fireEvent.click(screen.getByRole('button', { name: 'Révoquer l’accès' }));
    expectFooterWraps(screen.getByRole('dialog'), 'Révoquer');
  });
});

describe('« Nouveau rendez-vous »', () => {
  // Found by the e2e gate written for this change (not in the measurements
  // before it): at 320 with NORMAL text the date and the time, two `flex-1`
  // fields whose automatic minimum is their intrinsic width, ran « Heure du
  // rendez-vous » to x 340, past the panel and the screen.
  it('the date-and-time row wraps; both fields may narrow', () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(JSON.stringify({ items: [] }), { status: 200 })),
    );
    const profile = {
      account: { id: 'acc-1', email: 'x@salon.test' },
      provider: { id: 'p1', name: 'Beauté Divine', status: 'active', timezone: 'Africa/Abidjan', currency: 'XOF', services: [] },
    } as unknown as ProProfile;
    render(<ManualBookingDialog providerId="p1" profile={profile} onClose={() => {}} onCreated={() => {}} />);
    const date = screen.getByLabelText('Date du rendez-vous');
    const time = screen.getByLabelText('Heure du rendez-vous');
    const row = date.parentElement as HTMLElement;
    expect(row.contains(time)).toBe(true);
    expect(classes(row), 'the row does not wrap').toEqual(expect.arrayContaining(['flex', 'flex-wrap']));
    for (const field of [date, time]) {
      expect(classes(field)).toEqual(expect.arrayContaining(['min-w-0', 'flex-auto']));
      expect(classes(field)).not.toContain('flex-1');
    }
  });

  it('its footer wraps', () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(JSON.stringify({ items: [] }), { status: 200 })),
    );
    const profile = {
      account: { id: 'acc-1', email: 'x@salon.test' },
      provider: { id: 'p1', name: 'Beauté Divine', status: 'active', timezone: 'Africa/Abidjan', currency: 'XOF', services: [] },
    } as unknown as ProProfile;
    render(<ManualBookingDialog providerId="p1" profile={profile} onClose={() => {}} onCreated={() => {}} />);
    expectFooterWraps(screen.getByRole('dialog'), 'Créer');
  });
});

// --- The toast ----------------------------------------------------------------

describe('Toast — never wider than the screen less its gutters', () => {
  it('the region is capped at the screen less two `m` gutters, the 16 px the placement code keeps from an edge', () => {
    render(<Toast toast={{ message: 'Vous avez rejoint BeautéDivineCocodyRiviera', kind: 'success' }} />);
    expect(classes(screen.getByRole('status'))).toContain('max-w-gutterBound');
    const maxWidth = resolveConfig(tailwindConfig).theme.maxWidth as unknown as Record<string, string>;
    expect(maxWidth.gutterBound).toBe(`calc(100% - 2 * ${spacing.m})`);
    // The placement code's gutter (`EDGE`) is the same token.
    const source = readFileSync(join(__dirname, '../components/Toast.tsx'), 'utf8');
    expect(source).toMatch(/const EDGE = parseFloat\(spacing\.m\);/);
  });

  it('keeps today’s width otherwise: still placed by `left-1/2` and centred, so a pill stays at most half the screen (decisions 91 and 100)', () => {
    render(<Toast toast={{ message: 'Invitation renvoyée.', kind: 'success' }} />);
    expect(classes(screen.getByRole('status'))).toEqual(expect.arrayContaining(['fixed', 'left-1/2', '-translate-x-1/2']));
  });

  it.each([
    ['a message alone', undefined],
    ['a message with its action', { label: 'Annuler', onAction: () => {} }],
  ])('%s: the words sit in an item that may narrow, so a word wider than the cap breaks inside the pill', (_, action) => {
    const message = 'Vous avez rejoint BeautéDivineCocodyRiviera';
    render(<Toast toast={{ message, kind: 'success', action }} />);
    const pill = screen.getByRole('status').firstElementChild as HTMLElement;
    const words = [...pill.children].find((c) => c.textContent === message) as HTMLElement | undefined;
    expect(words, 'the message is not an element of its own in the pill (a bare text item cannot narrow)').toBeDefined();
    expect(classes(words!)).toEqual(expect.arrayContaining(['min-w-0', 'break-words']));
    expect(screen.getByRole('status').textContent).toBe(action ? `${message}Annuler` : message);
  });
});

// --- /mon-compte ---------------------------------------------------------------

function serveConsumer() {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const path = String(url).split('?')[0];
      if (path === '/api/me') {
        return new Response(JSON.stringify({ id: 'u1', name: 'Awa', email: 'awa@example.com', authProvider: 'email' }), { status: 200 });
      }
      if (path === '/api/appointments') return new Response(JSON.stringify({ items: [] }), { status: 200 });
      if (path === '/api/me/favorites') return new Response(JSON.stringify({ favorites: [] }), { status: 200 });
      if (path === '/api/localities') return new Response(JSON.stringify({ countries: [] }), { status: 200 });
      return new Response('{}', { status: 404 });
    }),
  );
}

describe('/mon-compte — « Confidentialité »', () => {
  it('the export row wraps and its link may narrow (it was `shrink-0`: 289 px in a 254 px row at 200 %)', async () => {
    serveConsumer();
    render(<AccountClient />);
    const link = await screen.findByRole('link', { name: 'Exporter mes données' });
    const row = link.parentElement as HTMLElement;
    expect(row.textContent).toContain('Recevoir une copie de vos données');
    expect(classes(row)).toEqual(expect.arrayContaining(['flex', 'flex-wrap']));
    expect(classes(link)).not.toContain('shrink-0');
  });

  it('the heading hyphenates, with `break-words` where a browser has no French hyphenation (the 404’s remedy)', async () => {
    serveConsumer();
    render(<AccountClient />);
    const heading = await screen.findByRole('heading', { level: 2, name: 'Confidentialité' });
    expect(classes(heading)).toEqual(expect.arrayContaining(['hyphens-auto', 'break-words']));
  });
});

// The account page's `lang="fr"` is what `hyphens-auto` reads: set on <html>.
describe('hyphenation has its language', () => {
  it('the root layout declares French', () => {
    const source = readFileSync(join(__dirname, '../app/layout.tsx'), 'utf8');
    expect(source).toMatch(/<html lang="fr"/);
  });
});

