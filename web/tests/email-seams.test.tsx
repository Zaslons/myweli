import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/pro',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('@sentry/nextjs', () => ({ captureMessage: vi.fn(), captureException: vi.fn() }));
vi.mock('next/dynamic', () => ({ default: () => () => null }));

import MentionsPage from '../app/mentions-legales/page';
import SupportPage from '../app/support/page';
import { AccountClient } from '../components/account/AccountClient';
import { DataExportClient } from '../components/account/DataExportClient';
import { Email } from '../components/legal/LegalPage';
import { ChangeRoleDialog } from '../components/pro/ChangeRoleDialog';
import { EmailAlertsPreference } from '../components/pro/EmailAlertsPreference';
import { EquipeClient } from '../components/pro/EquipeClient';
import { ProMembershipProvider } from '../components/pro/ProMembershipContext';
import { ProfilClient } from '../components/pro/ProfilClient';
import { ProSidebar } from '../components/pro/ProSidebar';
import type { TeamMember } from '../lib/pro/team';

/// Every place on the website that draws an e-mail address, other than the
/// sign-ins' code step (docs/design/web-email-seams.md; that step is
/// `code-sent-to.test.tsx`'s). §9's rule: an address breaks only before its
/// « @ » or a « . » of its name part, and a sentence that names one gives it
/// a line of its own.
///
/// jsdom draws nothing, so this file holds the STRUCTURE: what a screen reader
/// is given, what is drawn, and where the drawing may break. Where the lines
/// fall is measured by `type-overflow.spec.ts` in a real browser.
///
/// **Why a screen reader is given its own copy.** Chromium makes one text node
/// of the accessibility tree per DOM text node, so a drawing cut by `<wbr>`s
/// reaches it as « aminata », « .kone », « @exemple.ci »; and a link named from
/// such a drawing gets a space at each `<wbr>` (« support@ myweli.com », read
/// off CDP on 2026-11-27). So what is heard must hold the address in ONE text
/// node, or be a link's `aria-label`.

/// [address, the pieces a <wbr> separates].
const ADDRESSES: [address: string, pieces: string[]][] = [
  ['aminata.kone@exemple.ci', ['aminata', '.kone', '@exemple.ci']],
  ['awa.kone.nouvelle@exemple.ci', ['awa', '.kone', '.nouvelle', '@exemple.ci']],
];
const SUPPORT_ADDRESS = 'support@myweli.com';
const SUPPORT_PIECES = ['support', '@myweli.com'];

const hidden = (node: Node) =>
  (node.nodeType === Node.ELEMENT_NODE ? (node as Element) : node.parentElement)?.closest(
    '[aria-hidden="true"]',
  ) != null;
const classes = (el: Element | null) => (el?.getAttribute('class') ?? '').split(/\s+/);

/// The text nodes a screen reader is given under `root`: every one outside an
/// `aria-hidden` drawing, in order.
function heardNodes(root: Element): Text[] {
  const out: Text[] = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  for (let t = walker.nextNode(); t; t = walker.nextNode()) {
    if (!hidden(t)) out.push(t as Text);
  }
  return out;
}
const heardText = (root: Element) =>
  heardNodes(root)
    .map((t) => t.nodeValue)
    .join('')
    .replace(/\s+/g, ' ')
    .trim();
const count = (text: string, part: string) => text.split(part).length - 1;

/// Heard once, and whole: the address appears once in what is heard under
/// `root`, inside ONE text node (never assembled from pieces).
function expectHeardWhole(root: Element, address: string) {
  expect(count(heardText(root), address), `« ${address} » is not heard exactly once`).toBe(1);
  expect(
    heardNodes(root).some((t) => t.nodeValue?.includes(address)),
    `no single text node a screen reader reads holds « ${address} » whole`,
  ).toBe(true);
}

/// The element that DRAWS the address, cut by <wbr>s: its text is the address
/// alone, it holds a <wbr>, and a screen reader does not read it — it is inside
/// an `aria-hidden` drawing, or inside a link that names itself.
function drawnAddress(address: string, root: ParentNode = document.body): HTMLElement | undefined {
  const all = [...root.querySelectorAll<HTMLElement>('*')].filter(
    (el) =>
      el.textContent === address &&
      el.querySelector('wbr') !== null &&
      (hidden(el) || el.closest(`a[aria-label="${address}"]`) !== null),
  );
  return all.find((el) => !all.some((other) => other !== el && el.contains(other)));
}

/// The address's text, cut wherever a <wbr> stands.
function piecesOf(el: HTMLElement): string[] {
  const pieces = [''];
  const walk = (node: Node) => {
    for (const child of Array.from(node.childNodes)) {
      if (child.nodeType === Node.TEXT_NODE) pieces[pieces.length - 1] += child.nodeValue ?? '';
      else if ((child as Element).tagName === 'WBR') pieces.push('');
      else walk(child);
    }
  };
  walk(el);
  return pieces;
}

/// Drawn, cut at exactly its seams; `break-words` as the fallback for a piece
/// wider than a line; never `break-all`, which cuts anywhere.
function expectDrawnAtItsSeams(address: string, pieces: string[], root: ParentNode = document.body) {
  const drawn = drawnAddress(address, root);
  expect(drawn, `« ${address} » is not drawn with seams`).toBeDefined();
  expect(piecesOf(drawn!)).toEqual(pieces);
  expect(drawn!.closest('.break-words'), 'no break-words fallback').not.toBeNull();
  expect(drawn!.closest('.break-all'), 'break-all cuts anywhere').toBeNull();
  return drawn!;
}

/// The innermost element holding `text` among those a screen reader reads.
function innermostHeard(text: string): HTMLElement {
  const all = [...document.querySelectorAll<HTMLElement>('body *')].filter(
    (el) => !hidden(el) && heardText(el).includes(text),
  );
  const inner = all.filter((el) => !all.some((other) => other !== el && el.contains(other)));
  expect(inner.length, `« ${text} » is not heard`).toBeGreaterThan(0);
  return inner[0];
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

// --- Équipe ------------------------------------------------------------------

const OWNER_PROFILE = {
  account: { id: 'acc1', email: 'proprietaire@beaute-divine.test' },
  provider: { id: 'p1', name: 'Beauté Divine', artists: [{ id: 'a1', name: 'Awa' }] },
  membership: {
    role: 'owner',
    capabilities: ['members.manage', 'profile.manage', 'subscription.manage'],
  },
};
const memberRow = (email: string): TeamMember =>
  ({
    id: 'm-long',
    providerId: 'p1',
    accountId: null,
    email,
    role: 'staff',
    artistId: 'a1',
    artistName: 'Awa',
    status: 'invited',
    invitedAt: '2026-11-20T00:00:00.000Z',
    acceptedAt: null,
    revokedAt: null,
    expiresAt: '2026-12-20T00:00:00.000Z',
    expired: false,
    resendsLeft: 3,
  }) as unknown as TeamMember;

function serveTeam(email: string) {
  const owner = { ...memberRow(OWNER_PROFILE.account.email), id: 'm-owner', role: 'owner', status: 'active' };
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      const method = init?.method ?? 'GET';
      if (u === '/api/pro/me') return new Response(JSON.stringify(OWNER_PROFILE), { status: 200 });
      if (u === '/api/pro/members' && method === 'GET') {
        return new Response(JSON.stringify({ items: [owner, memberRow(email)] }), { status: 200 });
      }
      if (u === '/api/pro/members' && method === 'POST') {
        const body = JSON.parse(String(init?.body));
        return new Response(JSON.stringify({ ...memberRow(body.email), id: 'm-new' }), { status: 201 });
      }
      if (u.startsWith('/api/pro/salon-subscription')) {
        return new Response(
          JSON.stringify({
            tier: 'pro',
            status: 'trial',
            trialEndsAt: '2026-12-12T00:00:00.000Z',
            paidUntil: null,
            graceEndsAt: null,
            unpublishedForBilling: false,
            seats: { cap: 5, used: 2 },
          }),
          { status: 200 },
        );
      }
      if (u === '/api/pro/members/m-long/resend' || u === '/api/pro/members/m-long/revoke') {
        const status = u.endsWith('revoke') ? 'revoked' : 'invited';
        return new Response(JSON.stringify({ ...memberRow(email), status }), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

async function openTeam(email: string) {
  serveTeam(email);
  render(<EquipeClient />);
  return screen.findByRole('button', { name: `Actions pour ${email}` });
}

/// The roster's cell for a member: the table cell that holds the address.
function rosterCell(email: string) {
  const cell = screen
    .getAllByRole('cell')
    .find((c) => heardText(c).includes(email));
  expect(cell, 'no roster cell holds the address').toBeDefined();
  return cell!;
}

describe.each(ADDRESSES)('Équipe — « %s »', (address, pieces) => {
  it('the roster: the address heard once and whole, drawn at its seams, its flex item allowed to narrow', async () => {
    await openTeam(address);
    const cell = rosterCell(address);
    expectHeardWhole(cell, address);
    const drawn = expectDrawnAtItsSeams(address, pieces, cell);
    // The cell is a flex row (initials + address): `break-words` cannot
    // narrow a flex item whose min-width is its min-content.
    let item: HTMLElement = drawn;
    while (item.parentElement && !classes(item.parentElement).includes('flex')) item = item.parentElement;
    expect(classes(item), 'the address’s flex item has no min-w-0').toContain('min-w-0');
  });

  it('the roster gives « Membre » 5 parts of the row — 3 was narrower than « @exemple.ci » at 200 %', async () => {
    await openTeam(address);
    const header = screen.getByRole('columnheader', { name: 'Membre' }).parentElement as HTMLElement;
    expect(header.getAttribute('style')).toMatch(/grid-template-columns: minmax\(0, 5fr\) minmax\(0, 2fr\)/);
  });

  it('« Changer le rôle »: the address heard once and whole, drawn at its seams', async () => {
    serveTeam(address);
    render(
      <ChangeRoleDialog
        member={memberRow(address)}
        providerId="p1"
        artists={[{ id: 'a1', name: 'Awa' } as never]}
        onArtistCreated={() => {}}
        onClose={() => {}}
        onChanged={() => {}}
      />,
    );
    const dialog = screen.getByRole('dialog');
    expectHeardWhole(dialog, address);
    expectDrawnAtItsSeams(address, pieces, dialog);
  });

  it('« Révoquer l’accès »: the sentence heard as it always was; the address drawn on a line of its own, in ink, first', async () => {
    const dots = await openTeam(address);
    fireEvent.click(dots);
    fireEvent.click(screen.getByRole('button', { name: 'Révoquer l’accès' }));
    const dialog = screen.getByRole('dialog');
    const sentence = `${address} perdra immédiatement l’accès à Beauté Divine. Son compte MyWeli n’est pas supprimé.`;
    const p = innermostHeard('perdra immédiatement');
    expect(heardText(p)).toBe(sentence);
    expectHeardWhole(p, address);

    const drawn = expectDrawnAtItsSeams(address, pieces, dialog);
    expect(classes(drawn)).toEqual(expect.arrayContaining(['block', 'text-textPrimary']));
    const drawing = drawn.closest('[aria-hidden="true"]') as HTMLElement;
    expect(drawing.firstElementChild, 'the address does not open the drawing').toBe(drawn);
    expect((drawing.textContent ?? '').slice(address.length).replace(/\s+/g, ' ').trim()).toBe(
      'perdra immédiatement l’accès à Beauté Divine. Son compte MyWeli n’est pas supprimé.',
    );
  });

  it('the toasts say what happened without the address (decision 2, 2026-11-27)', async () => {
    let dots = await openTeam(address);
    fireEvent.click(dots);
    fireEvent.click(screen.getByRole('button', { name: /Renvoyer l’invitation/ }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Invitation renvoyée.'));
    expect(screen.getByRole('status').textContent).toBe('Invitation renvoyée.');

    dots = screen.getByRole('button', { name: `Actions pour ${address}` });
    fireEvent.click(dots);
    fireEvent.click(screen.getByRole('button', { name: 'Révoquer l’accès' }));
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Révoquer' }));
    await waitFor(() => expect(screen.getByRole('status').textContent).toBe('Accès révoqué.'));
  });

  it('the invitation toast says what happened without the address', async () => {
    await openTeam(address);
    fireEvent.click(screen.getByRole('button', { name: '+ Inviter un membre' }));
    fireEvent.change(screen.getByPlaceholderText('collaborateur@exemple.com'), {
      target: { value: `n.${address}` },
    });
    fireEvent.click(screen.getByRole('button', { name: /^Manager/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer l’invitation' }));
    await waitFor(() => expect(screen.getByRole('status').textContent).toBe('Invitation envoyée.'));
  });
});

// --- A member's own address: the sidebar and Profil -------------------------

function serveMember(email: string) {
  const profile = {
    account: { id: 'acc-r', email },
    provider: { id: 'p1', name: 'Beauté Divine', status: 'active' },
    membership: { role: 'reception', capabilities: ['clients.view', 'journal.manage.all', 'journal.view.all'] },
  };
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const u = String(url);
      if (u === '/api/pro/me') return new Response(JSON.stringify(profile), { status: 200 });
      if (u === '/api/pro/salons') {
        return new Response(
          JSON.stringify({
            items: [{ salonId: 'p1', salonName: 'Beauté Divine', role: 'reception', salonStatus: 'active' }],
            canAddSalon: false,
          }),
          { status: 200 },
        );
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

describe.each(ADDRESSES)('the member’s own address — « %s »', (address, pieces) => {
  it('the Pro sidebar: heard once and whole, drawn at its seams', async () => {
    serveMember(address);
    render(
      <ProMembershipProvider>
        <ProSidebar />
      </ProMembershipProvider>,
    );
    await waitFor(() => expect(document.querySelector('aside')?.textContent).toContain(address));
    const aside = document.querySelector('aside') as HTMLElement;
    expectHeardWhole(aside, address);
    expectDrawnAtItsSeams(address, pieces, aside);
  });

  it('Profil (the member’s slim view): heard once and whole, drawn at its seams', async () => {
    serveMember(address);
    render(<ProfilClient />);
    await screen.findByText('Salon : Beauté Divine');
    const card = screen.getByText('Salon : Beauté Divine').parentElement as HTMLElement;
    expectHeardWhole(card, address);
    expectDrawnAtItsSeams(address, pieces, card);
  });
});

// --- « Alertes par e-mail » ---------------------------------------------------

const ALERTS_LEAD =
  'Si une notification de l’app MyWeli Pro ne peut pas vous parvenir (nouvelle demande, report, annulation, justificatif d’acompte), nous vous écrivons à';

function servePrefs() {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) =>
      String(url) === '/api/pro/notification-preferences'
        ? new Response(
            JSON.stringify({ reminders: true, marketing: true, push: true, emailAlerts: true }),
            { status: 200 },
          )
        : new Response('{}', { status: 404 }),
    ),
  );
}

describe.each(ADDRESSES)('« Alertes par e-mail » — « %s »', (address, pieces) => {
  it('heard as one sentence, the address whole, period included', async () => {
    servePrefs();
    render(<EmailAlertsPreference email={address} />);
    await screen.findByRole('switch', { name: 'Alertes par e-mail' });
    const p = innermostHeard('nous vous écrivons à');
    expect(heardText(p)).toBe(`${ALERTS_LEAD} ${address}.`);
    expectHeardWhole(p, address);
  });

  it('drawn with the address last, on a line of its own, in ink, no period; the row lets it narrow', async () => {
    servePrefs();
    render(<EmailAlertsPreference email={address} />);
    await screen.findByRole('switch', { name: 'Alertes par e-mail' });
    const drawn = expectDrawnAtItsSeams(address, pieces);
    expect(classes(drawn)).toEqual(expect.arrayContaining(['block', 'text-textPrimary']));
    const drawing = drawn.closest('[aria-hidden="true"]') as HTMLElement;
    expect(drawing.lastElementChild, 'something is drawn after the address').toBe(drawn);
    // The lead, then the address on its own line: nothing between, nothing after.
    expect(drawing.textContent).toBe(`${ALERTS_LEAD}${address}`);
    // The text column beside the switch is a flex item.
    const column = drawing.closest('p')!.parentElement as HTMLElement;
    expect(classes(column), 'the text column beside the switch has no min-w-0').toContain('min-w-0');
  });
});

describe('« Alertes par e-mail » — no address known', () => {
  it('the same sentence ends « à votre adresse e-mail. »', async () => {
    servePrefs();
    render(<EmailAlertsPreference email={null} />);
    await screen.findByRole('switch', { name: 'Alertes par e-mail' });
    expect(screen.getByText(`${ALERTS_LEAD} votre adresse e-mail.`)).toBeInTheDocument();
  });
});

// --- The client's account ----------------------------------------------------

function serveConsumer(email: string) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const path = String(url).split('?')[0];
      if (path === '/api/me') {
        return new Response(JSON.stringify({ id: 'u1', name: 'Awa', email, authProvider: 'email' }), { status: 200 });
      }
      if (path === '/api/appointments') return new Response(JSON.stringify({ items: [] }), { status: 200 });
      if (path === '/api/me/favorites') return new Response(JSON.stringify({ favorites: [] }), { status: 200 });
      if (path === '/api/localities') return new Response(JSON.stringify({ countries: [] }), { status: 200 });
      return new Response('{}', { status: 404 });
    }),
  );
}

describe.each(ADDRESSES)('the client’s account — « %s »', (address, pieces) => {
  it('/mon-compte: under the name, heard once and whole, drawn at its seams', async () => {
    serveConsumer(address);
    render(<AccountClient />);
    await screen.findByRole('heading', { level: 2, name: 'Mes rendez-vous' });
    await waitFor(() => expect(document.body.textContent).toContain(address));
    const holder = innermostHeard(address).parentElement as HTMLElement;
    expectHeardWhole(holder, address);
    expectDrawnAtItsSeams(address, pieces, holder);
  });

  it('/mon-compte/donnees: the « Profil » row wraps, its value heard whole and drawn at its seams', async () => {
    serveConsumer(address);
    render(<DataExportClient />);
    const term = await screen.findByText('Profil', { selector: 'dt' });
    const row = term.parentElement as HTMLElement;
    expect(classes(row), 'the row cannot put the address under « Profil »').toContain('flex-wrap');
    const value = row.querySelector('dd') as HTMLElement;
    expect(classes(value), 'the value cannot narrow below its longest piece').toContain('min-w-0');
    expectHeardWhole(value, address);
    expectDrawnAtItsSeams(address, pieces, value);
  });
});

describe('/mon-compte/donnees — a profile with a phone and no e-mail', () => {
  it('shows the number, untouched', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        const path = String(url).split('?')[0];
        if (path === '/api/me') {
          return new Response(JSON.stringify({ id: 'u1', name: 'Awa', phoneNumber: '+2250700000000' }), { status: 200 });
        }
        if (path === '/api/appointments') return new Response(JSON.stringify({ items: [] }), { status: 200 });
        if (path === '/api/me/favorites') return new Response(JSON.stringify({ favorites: [] }), { status: 200 });
        return new Response('{}', { status: 404 });
      }),
    );
    render(<DataExportClient />);
    const term = await screen.findByText('Profil', { selector: 'dt' });
    expect(term.parentElement!.querySelector('dd')!.textContent).toBe('+2250700000000');
  });
});

// --- The support address on the legal pages ----------------------------------

/// A link that draws the address names itself with it: its `aria-label` is
/// the address, and its words are the address too (WCAG 2.5.3), with no
/// second copy in the page's text, which crawlers read.
function expectSupportLink(link: HTMLAnchorElement) {
  expect(link.getAttribute('href')).toBe('mailto:support@myweli.com');
  expect(link.getAttribute('aria-label'), 'the link takes its name from a drawing cut by <wbr>s').toBe(SUPPORT_ADDRESS);
  expect(link.textContent).toBe(SUPPORT_ADDRESS);
  expectDrawnAtItsSeams(SUPPORT_ADDRESS, SUPPORT_PIECES, link);
}

describe('the support address — before its « @ », named whole', () => {
  it('Email (/pro/suppression-compte)', () => {
    render(<Email />);
    expectSupportLink(screen.getByRole('link') as HTMLAnchorElement);
  });

  it('/mentions-legales « Nous contacter »', () => {
    const { container } = render(<MentionsPage />);
    const links = [...container.querySelectorAll<HTMLAnchorElement>('a[href="mailto:support@myweli.com"]')];
    expect(links.length).toBe(1);
    expectSupportLink(links[0]);
  });

  it('/support « Nous écrire », its flex link letting the address narrow', () => {
    const { container } = render(<SupportPage />);
    const link = container.querySelector<HTMLAnchorElement>('a[href="mailto:support@myweli.com"]')!;
    expectSupportLink(link);
    const drawn = drawnAddress(SUPPORT_ADDRESS, link)!;
    let item: HTMLElement = drawn;
    while (item.parentElement && item.parentElement !== link) item = item.parentElement;
    expect(classes(item), 'the address’s flex item has no min-w-0').toContain('min-w-0');
  });
});
