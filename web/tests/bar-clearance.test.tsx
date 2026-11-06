import { act, cleanup, render } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { BarClearance } from '../components/provider/BarClearance';

/// BACKLOG 103 (web-swiss-salon.md §3.3, §3.9 U-B1–U-B5): below `lg` the salon page's booking bar
/// is fixed, and `BarClearance`, rendered inside it, gives `<html>` a bottom padding as tall as
/// the bar and a scroll padding of the bar plus `s`, keeps a visitor at the page's very end at
/// the end when that room changes, and takes both off from `lg` and when the page goes. jsdom
/// has no layout, so the boxes are given: a 390×568 screen, a page 4,000 px tall without the
/// room, whose height grows by the padding the component writes, as a browser's does.

const html = document.documentElement;
let BAR_H: number;
let CONTENT: number;
let Y: number;
let observed: Element[];
let notify: (() => void) | null;
const scrolls: number[] = [];

const box = (h: number) =>
  ({ x: 0, y: 0, left: 0, top: 0, right: 390, bottom: h, width: 390, height: h, toJSON: () => ({}) }) as DOMRect;
const room = () => parseFloat(html.style.paddingBottom) || 0;
const styles = () => [html.style.paddingBottom, html.style.scrollPaddingBottom];

/// The bar is measured in the layout effect, which `render` runs before it returns, so the box
/// is given first: the stub goes on the prototype, and only the bar has a height.
function show() {
  vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (this: HTMLElement) {
    return this.dataset.testid === 'bar' ? box(BAR_H) : box(0);
  });
  const view = render(
    <div data-testid="bar">
      <BarClearance />
    </div>,
  );
  return { ...view, bar: view.getByTestId('bar') };
}

/// A browser fires the observer when the bar's box changes; here the test says when.
const resized = () =>
  act(() => {
    notify?.();
  });
const windowResized = () =>
  act(() => {
    window.dispatchEvent(new Event('resize'));
  });

beforeEach(() => {
  BAR_H = 65;
  CONTENT = 4000;
  Y = 0;
  observed = [];
  notify = null;
  scrolls.length = 0;
  vi.stubGlobal('innerHeight', 568);
  vi.stubGlobal('innerWidth', 390);
  vi.stubGlobal(
    'ResizeObserver',
    class {
      private readonly cb: () => void;
      constructor(cb: () => void) {
        this.cb = cb;
        notify = () => {
          if (observed.length > 0) this.cb();
        };
      }
      observe(el: Element) {
        observed.push(el);
      }
      disconnect() {
        observed = [];
      }
    },
  );
  Object.defineProperty(window, 'scrollY', { configurable: true, get: () => Y });
  Object.defineProperty(html, 'scrollHeight', { configurable: true, get: () => CONTENT + room() });
  vi.spyOn(window, 'scrollTo').mockImplementation(((opts: ScrollToOptions) => {
    scrolls.push(opts.top ?? NaN);
    Y = opts.top ?? Y;
  }) as typeof window.scrollTo);
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  delete (window as unknown as Record<string, unknown>).scrollY;
  delete (html as unknown as Record<string, unknown>).scrollHeight;
  html.style.paddingBottom = '';
  html.style.scrollPaddingBottom = '';
  html.removeAttribute('style');
});

describe('BarClearance: the room the fixed booking bar is owed', () => {
  it('U-B1: a 65 px bar gives <html> 65 px of bottom padding and 73 px of scroll padding (the bar plus s)', () => {
    show();
    expect(styles()).toEqual(['65px', '73px']);
  });

  it('U-B1: the room is measured, not a token: a 137 px bar (doubled text at 320) gets 137 and 145', () => {
    BAR_H = 137;
    show();
    expect(styles()).toEqual(['137px', '145px']);
  });

  it('U-B1: it measures its own parent, the bar, and watches that box', () => {
    const { bar } = show();
    expect(observed).toEqual([bar]);
  });

  it('U-B2: a bar of height 0 (hidden from lg) takes both off, and they come back below lg', () => {
    show();
    expect(styles()).toEqual(['65px', '73px']);
    BAR_H = 0;
    windowResized();
    expect(styles()).toEqual(['', '']);
    BAR_H = 65;
    windowResized();
    expect(styles()).toEqual(['65px', '73px']);
  });

  it('U-B2: a page opened at lg or wider, the bar hidden from the start, gets neither', () => {
    BAR_H = 0;
    show();
    expect(styles()).toEqual(['', '']);
  });

  it('U-B3: when the page goes, both are taken off, and neither a resize nor the observer writes them again', () => {
    const view = show();
    expect(styles()).toEqual(['65px', '73px']);
    view.unmount();
    expect(styles()).toEqual(['', '']);
    expect(observed).toEqual([]);
    windowResized();
    resized();
    expect(styles()).toEqual(['', '']);
  });

  it('re-measures when the bar changes height (the observer: a larger font, the price wrapping)', () => {
    show();
    BAR_H = 113;
    resized();
    expect(styles()).toEqual(['113px', '121px']);
  });

  it('re-measures on a window resize (a rotation)', () => {
    show();
    BAR_H = 97;
    windowResized();
    expect(styles()).toEqual(['97px', '105px']);
  });

  it('U-B4: a visitor parked at the very end before the script is moved by exactly the room added, to the new end', () => {
    Y = CONTENT - 568; // 3,432: the end of the page without the room
    show();
    expect(scrolls).toEqual([3432 + 65]);
    expect(Y).toBe(html.scrollHeight - 568);
  });

  it('U-B4: at the very end when the bar grows, the visitor follows the new end, by the growth only', () => {
    show();
    Y = html.scrollHeight - 568; // 3,497
    BAR_H = 137;
    resized();
    expect(scrolls).toEqual([3497 + 72]);
    expect(Y).toBe(html.scrollHeight - 568);
  });

  it('U-B4: within a pixel of the end counts as the end (a fractional scroll position)', () => {
    Y = CONTENT - 568 - 0.5;
    show();
    expect(scrolls).toEqual([3432 + 65]);
  });

  it('U-B4: mid-page, the visitor is never scrolled', () => {
    Y = 1200;
    show();
    BAR_H = 137;
    resized();
    windowResized();
    expect(scrolls).toEqual([]);
    expect(Y).toBe(1200);
  });

  it('U-B4: at the top of a long page, never scrolled', () => {
    show();
    BAR_H = 137;
    resized();
    expect(scrolls).toEqual([]);
  });

  it('U-B4: a page that does not scroll (shorter than the screen) is never scrolled by the room', () => {
    CONTENT = 540;
    show();
    expect(styles()).toEqual(['65px', '73px']);
    expect(scrolls).toEqual([]);
  });

  it('U-B5: a browser without ResizeObserver: no throw, the room is set, and a resize still re-measures', () => {
    vi.stubGlobal('ResizeObserver', undefined);
    expect(() => show()).not.toThrow();
    expect(styles()).toEqual(['65px', '73px']);
    BAR_H = 113;
    windowResized();
    expect(styles()).toEqual(['113px', '121px']);
  });

  it('renders nothing a reader or the keyboard can reach: one hidden, empty span', () => {
    const { bar } = show();
    expect(bar.children).toHaveLength(1);
    const mark = bar.firstElementChild as HTMLElement;
    expect(mark.tagName).toBe('SPAN');
    expect(mark.hidden).toBe(true);
    expect(mark.textContent).toBe('');
  });
});
