import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import type { ReactElement } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { LoginOptions } from '../components/auth/LoginOptions';
import { ProLoginOptions } from '../components/pro/ProLoginOptions';

/// The sign-ins' code step names the address the code went to
/// (docs/design/web-code-sent-to.md). Driven through both real components,
/// because the sentence lives in each of them.
///
/// jsdom draws nothing, so this file holds the STRUCTURE: what a screen reader
/// hears, what is drawn, and where the address may break. Where the lines
/// actually fall is measured by `type-overflow.spec.ts` in a real browser.

const LEAD = 'Entrez le code reçu par e-mail à';

const SURFACES: [name: string, request: string, render: () => ReactElement][] = [
  ['the sign-in', '/api/auth/email/request', () => <LoginOptions onSuccess={() => {}} />],
  ['the Pro sign-in', '/api/pro/auth/email/request', () => <ProLoginOptions onSuccess={() => {}} />],
];

/// [typed, what the code went to, the pieces a <wbr> separates].
const ADDRESSES: [typed: string, address: string, pieces: string[]][] = [
  ['awa@exemple.ci', 'awa@exemple.ci', ['awa', '@exemple.ci']],
  ['aminata.kone@exemple.ci', 'aminata.kone@exemple.ci', ['aminata', '.kone', '@exemple.ci']],
  // The domain's dots are no seam: a line would end on « gmail » and leave
  // « .com » alone on the next (SYSTEM.md §13.3).
  ['koffi.yao@gmail.com', 'koffi.yao@gmail.com', ['koffi', '.yao', '@gmail.com']],
  // As typed, then trimmed, as it was sent.
  ['  awa.kone.nouvelle@exemple.ci ', 'awa.kone.nouvelle@exemple.ci', ['awa', '.kone', '.nouvelle', '@exemple.ci']],
];

function mockFetch(request: string) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) =>
      url === request
        ? new Response(JSON.stringify({ expiresInSeconds: 300 }), { status: 202 })
        : new Response('{}', { status: 404 }),
    ),
  );
}

async function reachTheCodeStep(view: () => ReactElement, request: string, typed: string) {
  mockFetch(request);
  render(view());
  fireEvent.change(screen.getByLabelText('Votre e-mail'), { target: { value: typed } });
  fireEvent.click(screen.getByRole('button', { name: 'Continuer avec e-mail' }));
  await screen.findByLabelText('Code à 6 chiffres');
}

const hidden = (el: Element) => el.closest('[aria-hidden="true"]') !== null;

/// The element that draws the address: its text is the address and nothing
/// else (a <wbr> has none), and it is not part of what a screen reader reads.
function drawnAddress(address: string): HTMLElement | undefined {
  return [...document.querySelectorAll<HTMLElement>('body *')].find(
    (el) => el.textContent === address && hidden(el),
  );
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

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe.each(SURFACES)('%s — the code step names the address', (_, request, view) => {
  describe.each(ADDRESSES)('« %s »', (typed, address, pieces) => {
    it('a screen reader hears the sentence it always heard, period included, once', async () => {
      await reachTheCodeStep(view, request, typed);
      const sentence = `${LEAD} ${address}.`;
      const read = [...document.querySelectorAll<HTMLElement>('body *')].filter(
        (el) => !hidden(el) && el.textContent?.includes(address),
      );
      // The innermost element that holds the address in the read tree is the
      // sentence itself: nothing reads the address a second time, in pieces.
      const innermost = read.filter((el) => !read.some((other) => other !== el && el.contains(other)));
      expect(innermost.map((el) => el.textContent)).toEqual([sentence]);
    });

    it('the address is drawn on a line of its own, in ink, with no period after it', async () => {
      await reachTheCodeStep(view, request, typed);
      const drawn = drawnAddress(address);
      expect(drawn, 'no element draws the address alone (still inline in the sentence?)').toBeDefined();
      expect(drawn!.className.split(/\s+/)).toEqual(expect.arrayContaining(['block', 'text-textPrimary']));

      // The drawing is the sentence without its period: the lead, then the
      // address — nothing drawn after it.
      const drawing = drawn!.closest('[aria-hidden="true"]') as HTMLElement;
      expect(drawing.textContent).toBe(`${LEAD}${address}`);
      const lead = [...drawing.querySelectorAll<HTMLElement>('*')].find((el) => el.textContent === LEAD);
      expect(lead, 'the lead is not drawn as its own run').toBeDefined();
      expect(lead!.className.split(/\s+/)).toContain('text-textSecondary');
    });

    it('it may break only before its « @ » or a « . » of its name — and inside a piece only as a last resort', async () => {
      await reachTheCodeStep(view, request, typed);
      const drawn = drawnAddress(address);
      expect(drawn).toBeDefined();
      expect(piecesOf(drawn!)).toEqual(pieces);
      // The fallback for a piece wider than a line by itself.
      expect(drawn!.className.split(/\s+/)).toContain('break-words');
    });
  });
});
