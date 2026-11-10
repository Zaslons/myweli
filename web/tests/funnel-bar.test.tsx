import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('@sentry/nextjs', () => ({ captureMessage: vi.fn() }));

import { BookingFlow } from '../components/booking/BookingFlow';
import { providerFixture } from './fixtures';

/// Decision 105 (web-funnel-bar-fit.md §6): the funnel's phone bar renders the salon page's
/// `BarClearance`, so while the hub shows `<html>` gets a bottom padding as tall as the bar and
/// a scroll padding of the bar plus `s`; the confirm step has no bar, so it carries neither.
/// jsdom has no layout: the bar, the element that holds « Confirmer » and `BarClearance`'s
/// hidden mark, is given a 65px box on a 568px screen (under a quarter, so the bar stays full);
/// everything else is 0. Where the bar stands is the e2e's (funnel-bar.spec.ts).

const html = document.documentElement;
const SLOT = '2099-01-15T14:30:00.000Z';

const box = (h: number) =>
  ({ x: 0, y: 0, left: 0, top: 0, right: 390, bottom: h, width: 390, height: h, toJSON: () => ({}) }) as DOMRect;

/// The bar is the element with « Confirmer » and a hidden mark as its own children's: found
/// by what it holds, not by its classes.
const isBar = (el: HTMLElement) =>
  !!el.querySelector(':scope > span[hidden]') && /Confirmer/.test(el.textContent ?? '');

beforeEach(() => {
  vi.stubGlobal('innerHeight', 568);
  vi.stubGlobal('innerWidth', 390);
  vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (this: HTMLElement) {
    return isBar(this) ? box(65) : box(0);
  });
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const key = `${init?.method ?? 'GET'} ${String(url).split('?')[0]}`;
      const answers: Record<string, unknown> = {
        'GET /api/availability': { slots: [SLOT] },
        'GET /api/localities': { countries: [] },
      };
      return new Response(JSON.stringify(answers[key] ?? {}), { status: key in answers ? 200 : 404 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  html.style.paddingBottom = '';
  html.style.scrollPaddingBottom = '';
});

describe('the booking funnel’s phone bar and its room (decision 105)', () => {
  it('while the hub shows, <html> gets the bar’s height of room and 8px more of scroll padding', async () => {
    render(<BookingFlow provider={providerFixture} prefillServiceIds={['s1']} />);
    fireEvent.click(await screen.findByRole('button', { name: /^\d{2}:\d{2}$/ }));
    const confirm = screen.getAllByRole('button', { name: 'Confirmer' }).find((b) => !b.closest('aside'))!;
    const bar = confirm.parentElement!.parentElement!;
    expect(isBar(bar), 'the bar is not the box measured, so this proves nothing').toBe(true);
    expect([html.style.paddingBottom, html.style.scrollPaddingBottom]).toEqual(['65px', '73px']);
  });

  it('pressing « Confirmer » leaves the hub, and the confirm step carries neither', async () => {
    render(<BookingFlow provider={providerFixture} prefillServiceIds={['s1']} />);
    fireEvent.click(await screen.findByRole('button', { name: /^\d{2}:\d{2}$/ }));
    expect(html.style.paddingBottom, 'no room while the hub shows, so this proves nothing').toBe('65px');
    fireEvent.click(screen.getAllByRole('button', { name: 'Confirmer' })[0]);
    await screen.findByRole('heading', { level: 2, name: 'Confirmer' });
    expect([html.style.paddingBottom, html.style.scrollPaddingBottom]).toEqual(['', '']);
  });
});
