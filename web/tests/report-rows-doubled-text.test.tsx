import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { AvisClient } from '../components/pro/AvisClient';
import { ReviewList } from '../components/provider/ReviewList';

/// The « Signaler » forms at doubled text
/// (docs/design/web-report-rows-doubled-text.md; WEB-SYSTEM §9 rule 1).
///
/// jsdom lays nothing out, so this file holds the STRUCTURE that makes the
/// geometry right; `type-overflow.spec.ts` (« the « Signaler » forms at
/// doubled text ») measures it in a real browser. Measured on `main` before
/// the change, at 320×568: on the salon page the open form grew the layout
/// viewport to 428×760 in the Android mode, and squeezed the date to three
/// lines at normal text; on `/pro/avis` « Annuler » was drawn outside its
/// panel at normal text and from x −37 in the Android mode, and with a 32 px
/// root the distribution list made the page 489 px wide.

const classes = (el: Element | null) => (el?.getAttribute('class') ?? '').split(/\s+/).filter(Boolean);

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

/// The row that holds « Annuler » and « Signaler », found from the buttons, so
/// it holds whatever the form's markup becomes.
function buttonRow() {
  const cancel = screen.getByRole('button', { name: 'Annuler' });
  const row = cancel.parentElement!;
  expect(
    Array.from(row.querySelectorAll('button'), (b) => b.textContent),
    'the row found is not the form’s two buttons — nothing below would be read',
  ).toEqual(['Annuler', 'Signaler']);
  return row;
}

// --- The salon page -----------------------------------------------------------

const REVIEW = {
  id: 'r1',
  providerId: 'p1',
  userId: 'u1',
  userName: 'Awa',
  rating: 5,
  text: 'Service impeccable.',
  createdAt: '2026-06-01T10:00:00.000Z',
};

function renderSalonReviews() {
  render(<ReviewList reviews={[REVIEW]} rating={5} reviewCount={1} slug="beaute-divine" tz="UTC" />);
  const date = screen.getByText('1 juin 2026');
  return { date, row: date.parentElement! };
}

describe('the salon page’s « Signaler » (ReviewList)', () => {
  it('the date’s row wraps, so the open form can take a line of its own', () => {
    const { row } = renderSalonReviews();
    expect(row.children, 'the row is not the date and the report action').toHaveLength(2);
    expect(classes(row)).toContain('flex');
    expect(classes(row)).toContain('flex-wrap');
  });

  it('the report action keeps to the right, beside the date or alone on its line', () => {
    const { row } = renderSalonReviews();
    const action = row.children[1];
    expect(action).toContainElement(screen.getByRole('button', { name: 'Signaler' }));
    expect(classes(action)).toContain('ml-auto');

    fireEvent.click(screen.getByRole('button', { name: 'Signaler' }));
    expect(row.children[1]).toContainElement(screen.getByLabelText('Raison du signalement'));
    expect(classes(row.children[1])).toContain('ml-auto');
  });

  it('opened: « Annuler » and « Signaler » wrap, at the right', () => {
    renderSalonReviews();
    fireEvent.click(screen.getByRole('button', { name: 'Signaler' }));
    const row = buttonRow();
    expect(classes(row)).toContain('flex-wrap');
    expect(classes(row)).toContain('justify-end');
  });
});

// --- /pro/avis ----------------------------------------------------------------

function stubPro() {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const u = String(url);
      if (u === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc' },
            provider: { id: 'p1', name: 'Beauté Divine' },
            membership: { role: 'owner', capabilities: ['profile.manage'] },
          }),
          { status: 200 },
        );
      }
      if (u.startsWith('/api/pro/reviews')) {
        return new Response(JSON.stringify({ items: [REVIEW], page: 1, pageSize: 50, total: 1 }), {
          status: 200,
        });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

describe('/pro/avis’s « Signaler » (AvisClient)', () => {
  it('opened: « Annuler » and « Signaler » wrap, at the right', async () => {
    stubPro();
    render(<AvisClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Signaler' }));
    const row = buttonRow();
    expect(classes(row)).toContain('flex-wrap');
    expect(classes(row)).toContain('justify-end');
  });

  // Decision 3: `min-w-56` is 14 rem, 448 px at a 32 px root, and the page
  // scrolled sideways to 489 px. `w-56` still sends the list to its own line
  // when less than 14 rem is left beside the average, and the list may shrink
  // to the card there (a flex item's automatic minimum is the smaller of its
  // width and its content's; the mutation pass found `min-w-0` held nothing).
  // `flex-1` must go too: its 0 % basis would keep the list beside the average
  // at any width, squeezed.
  it('the distribution list goes to its own line at 14 rem, and may shrink there', async () => {
    stubPro();
    render(<AvisClient />);
    await screen.findByText('Service impeccable.');
    const list = screen.getByRole('progressbar', { name: '5 étoiles' }).closest('dl');
    expect(list, 'the distribution list did not render').not.toBeNull();
    expect(classes(list)).not.toContain('min-w-56');
    expect(classes(list)).not.toContain('flex-1');
    expect(classes(list)).toContain('w-56');
    expect(classes(list)).toContain('grow');
  });
});
