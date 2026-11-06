import { act, cleanup, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Toast } from '../components/Toast';

/// B11.5 (prototype guard): the toast is measured against a `[data-floating-control]` and moved
/// clear of it when the two come within 8 of each other, and only then: aside first, within the
/// gutters, else up or down, whichever is the shorter move (the nearer side), never nearer an
/// edge than 16. jsdom has no layout, so the boxes are given: a 390×844 screen, the pill at its
/// class position 97–293 × 708–764 (80 above the foot).

type R = { left: number; right: number; top: number; bottom: number };
let PILL: R;
let pillReads = 0;
const box = (r: R) =>
  ({ ...r, x: r.left, y: r.top, width: r.right - r.left, height: r.bottom - r.top, toJSON: () => r }) as DOMRect;

function control(r: R | null, parent: HTMLElement = document.body) {
  const el = document.createElement('button');
  el.setAttribute('data-floating-control', '');
  // Not displayed: a 0×0 box at the screen's corner, as a browser gives it.
  el.getBoundingClientRect = () => box(r ?? { left: 0, right: 0, top: 0, bottom: 0 });
  parent.appendChild(el);
  return el;
}

beforeEach(() => {
  PILL = { left: 97, right: 293, top: 708, bottom: 764 };
  pillReads = 0;
  vi.stubGlobal('innerHeight', 844);
  vi.stubGlobal('innerWidth', 390);
  vi.stubGlobal('ResizeObserver', class { observe() {} disconnect() {} });
  vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
    cb(0);
    return 1;
  });
  // The pill moves by the move its region wears, as it does in a browser.
  vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (this: HTMLElement) {
    const region = this.parentElement;
    if (region?.getAttribute('role') !== 'status') return box({ left: 0, right: 0, top: 0, bottom: 0 });
    pillReads++;
    const y = parseFloat(region.style.marginBottom) || 0;
    const x = parseFloat(region.style.translate) || 0;
    return box({ left: PILL.left + x, right: PILL.right + x, top: PILL.top - y, bottom: PILL.bottom - y });
  });
});
afterEach(() => {
  cleanup();
  document.body.innerHTML = '';
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

const lift = () => screen.getByRole('status').style.marginBottom;
const aside = () => screen.getByRole('status').style.translate;
const show = () => render(<Toast toast={{ message: 'Ajouté aux favoris', kind: 'success' }} aboveFloatingControl />);
const scroll = () =>
  act(() => {
    window.dispatchEvent(new Event('scroll'));
  });

describe('Toast clears a floating control', () => {
  it('riding at the foot (772–820): 8 below the pill, no move', () => {
    control({ left: 16, right: 100, top: 772, bottom: 820 });
    show();
    expect([lift(), aside()]).toEqual(['', '']);
  });

  it('level with the pill, room beside it: slides aside, just clear, and does not rise', () => {
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    // 101 + 8 − 97 = 12; the pill then ends at 305, within the 374 gutter.
    expect([lift(), aside()]).toEqual(['', '12px']);
  });

  it('level, no room beside it (a wide control): lifted to end 8 above it', () => {
    control({ left: 16, right: 200, top: 740, bottom: 788 });
    show();
    // Aside would need 111, the gutter leaves 81. Up: 764 − (740 − 8) = 32.
    expect([lift(), aside()]).toEqual(['32px', '']);
  });

  it('a full-width bar (the salon page) level with the pill: lifted', () => {
    control({ left: 0, right: 390, top: 740, bottom: 804 });
    show();
    expect([lift(), aside()]).toEqual(['32px', '']);
  });

  it('level but beside it, with more than 8 between: no move', () => {
    control({ left: 16, right: 80, top: 740, bottom: 788 });
    show();
    expect([lift(), aside()]).toEqual(['', '']);
  });

  // These two hold the outcome, not the off-screen filter: with the pill kept 16 from every
  // edge, `meets` alone already keeps such a box from moving it (the filter is a safeguard).
  it('not displayed (the map view at lg): no move', () => {
    control(null);
    show();
    expect([lift(), aside()]).toEqual(['', '']);
  });

  it('off the screen: no move', () => {
    control({ left: 16, right: 200, top: 900, bottom: 948 });
    show();
    expect([lift(), aside()]).toEqual(['', '']);
  });

  it('a short screen with no room above: goes below the control, 16 above the foot at most', () => {
    // 320×256 at a large text size: the pill 34–287 × 40–176, the control high at 30–78.
    vi.stubGlobal('innerHeight', 256);
    vi.stubGlobal('innerWidth', 320);
    PILL = { left: 34, right: 287, top: 40, bottom: 176 };
    control({ left: 16, right: 160, top: 30, bottom: 78 });
    show();
    // Up would need 154 (24 of room). Down: 78 + 8 − 40 = 46, which leaves the pill at 86–222.
    expect([lift(), aside()]).toEqual(['-46px', '']);
  });

  it('a short screen with no room anywhere: stays whole on the screen where it covers least', () => {
    vi.stubGlobal('innerHeight', 256);
    vi.stubGlobal('innerWidth', 320);
    PILL = { left: 34, right: 287, top: 40, bottom: 176 };
    control({ left: 16, right: 160, top: 150, bottom: 198 });
    show();
    // Up 34 > 24 of room; down 166 > 64. At home it covers 34, up 24 (top at 16) covers 10, down
    // 64 covers 64: up 24, and its top stays 16 from the screen's.
    expect([lift(), aside()]).toEqual(['24px', '']);
  });

  it('a scroll after the move keeps it: the move worn is taken off before measuring', () => {
    control({ left: 16, right: 200, top: 740, bottom: 788 });
    show();
    expect(lift()).toBe('32px');
    scroll();
    expect(lift()).toBe('32px');
  });

  it('the control rides on (back to 772–820): the next scroll drops the move', () => {
    const el = control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    expect(aside()).toBe('12px');
    el.getBoundingClientRect = () => box({ left: 16, right: 101, top: 772, bottom: 820 });
    scroll();
    expect([lift(), aside()]).toEqual(['', '']);
  });

  it('a control that appears while the message shows, with no scroll: the pill is moved', async () => {
    // Deep in the page, as « Liste » mounts inside `main`: the observer must watch the subtree.
    const deep = document.createElement('div');
    deep.appendChild(document.createElement('div'));
    document.body.appendChild(deep);
    show();
    expect([lift(), aside()]).toEqual(['', '']);
    control({ left: 16, right: 200, top: 740, bottom: 788 }, deep.firstElementChild as HTMLElement);
    // MutationObserver callbacks run as a microtask.
    await act(async () => {
      await Promise.resolve();
    });
    expect(lift()).toBe('32px');
  });

  it('a browser without ResizeObserver: no throw, and the pill is still moved', () => {
    vi.stubGlobal('ResizeObserver', undefined);
    control({ left: 16, right: 200, top: 740, bottom: 788 });
    show();
    expect(lift()).toBe('32px');
  });

  it('a slide survives the next scroll: the slide worn is taken off before measuring', () => {
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    expect(aside()).toBe('12px');
    scroll();
    expect([lift(), aside()]).toEqual(['', '12px']);
  });

  it('a control on the right: slides left, just clear', () => {
    control({ left: 290, right: 374, top: 700, bottom: 748 });
    show();
    // Right would need 285 (81 of gutter). Left: 293 − (290 − 8) = 11; the pill then starts at 86.
    expect([lift(), aside()]).toEqual(['', '-11px']);
  });

  it('a full-width bar where rising and dropping both clear: the shorter, down (the salon page)', () => {
    control({ left: 0, right: 390, top: 650, bottom: 715 });
    show();
    // Up: 764 − (650 − 8) = 122. Down: 715 + 8 − 708 = 15, within the 64 of room below: down.
    expect([lift(), aside()]).toEqual(['-15px', '']);
  });

  it('rising and dropping the same length, both clear: it rises', () => {
    control({ left: 0, right: 390, top: 722, bottom: 750 });
    show();
    // Up: 764 − (722 − 8) = 50. Down: 750 + 8 − 708 = 50, within the 64 of room below.
    expect([lift(), aside()]).toEqual(['50px', '']);
  });

  it('the order is fixed, not the smallest move: a 1 px rise would clear, it slides 12', () => {
    control({ left: 16, right: 101, top: 771, bottom: 819 });
    show();
    expect([lift(), aside()]).toEqual(['', '12px']);
  });

  it('a browser without the CSS translate property: no slide, the shorter of up and down', () => {
    vi.stubGlobal('CSS', { supports: (property: string) => property !== 'translate' });
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    // Up: 764 − (700 − 8) = 72. Down: 748 + 8 − 708 = 48, within the 64 of room below: down.
    expect([lift(), aside()]).toEqual(['-48px', '']);
  });

  it('once the toast is unmounted, a scroll or a resize measures nothing', () => {
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    expect(pillReads).toBeGreaterThan(0);
    cleanup();
    pillReads = 0;
    window.dispatchEvent(new Event('scroll'));
    window.dispatchEvent(new Event('resize'));
    expect(pillReads).toBe(0);
  });

  it('a toast that goes takes its move with it', () => {
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    const { rerender } = show();
    expect(aside()).toBe('12px');
    act(() => rerender(<Toast toast={null} aboveFloatingControl />));
    expect([lift(), aside()]).toEqual(['', '']);
  });
  // Review of the port (B11.5): the 16 above the screen's foot decides the drop's length.
  it('a 320×256 screen, the control high on it: the drop stops 16 above the foot', () => {
    // The salon page at the browser's 200 % font, 320×256: the pill 34–287 × 40–176, the control
    // 16–160 × 30–170. Up needs 154 (24 of room), down 138 (256 − 16 − 176 = 64 of room). At home it
    // covers 136, up 24 covers 130, down 64 covers 74: down 64, its foot 16 above the screen's.
    vi.stubGlobal('innerHeight', 256);
    vi.stubGlobal('innerWidth', 320);
    PILL = { left: 34, right: 287, top: 40, bottom: 176 };
    control({ left: 16, right: 160, top: 30, bottom: 170 });
    show();
    expect([lift(), aside()]).toEqual(['-64px', '']);
  });

  it('a control taller than the screen, where no move covers it less: the pill stays home', () => {
    // 320×256, the control 16–160 × −10–300: up 24 (the room) and down 64 (the room) each leave the
    // pill's whole height on it, as home does, so staying home wins the tie.
    vi.stubGlobal('innerHeight', 256);
    vi.stubGlobal('innerWidth', 320);
    PILL = { left: 34, right: 287, top: 40, bottom: 176 };
    control({ left: 16, right: 160, top: -10, bottom: 300 });
    show();
    expect([lift(), aside()]).toEqual(['', '']);
  });

  // Boxes are fractional in a browser; a move is worn in whole px, so it is tried in whole px.
  it('a rise capped by the top, in whole px within the room: its top stays 16 from the screen’s', () => {
    // The pill 40.5–176.5 on a 256-high screen, a full-width bar 150–200. Up needs 34.5 (35); the
    // room is 24.5, so 24, not 25 (which would end 15.5 from the top). Down needs 167.5, the room
    // 63.5: 63. Up 24 covers the bar least.
    vi.stubGlobal('innerHeight', 256);
    PILL = { left: 97, right: 293, top: 40.5, bottom: 176.5 };
    control({ left: 0, right: 390, top: 150, bottom: 200 });
    show();
    expect([lift(), aside()]).toEqual(['24px', '']);
  });

  it('a rise or a drop is rounded up to whole px, so the 8 of air stay whole', () => {
    // A wide control at 740.4: up needs 764 − 732.4 = 31.6, worn as 32 (31.6 would leave 7.6).
    const el = control({ left: 16, right: 200, top: 740.4, bottom: 788 });
    show();
    expect([lift(), aside()]).toEqual(['32px', '']);
    cleanup();
    el.remove();
    // 320×256, the control high at 30–77.6: up needs 154 (24 of room); down needs 77.6 + 8 − 40 =
    // 45.6, worn as 46, within the 64 of room below.
    vi.stubGlobal('innerHeight', 256);
    vi.stubGlobal('innerWidth', 320);
    PILL = { left: 34, right: 287, top: 40, bottom: 176 };
    control({ left: 16, right: 160, top: 30, bottom: 77.6 });
    show();
    expect([lift(), aside()]).toEqual(['-46px', '']);
    cleanup();
    document.body.innerHTML = '';
    // A control on the right ending its air at 282.4: aside left needs 293 − 282.4 = 10.6, worn as 11.
    vi.stubGlobal('innerHeight', 844);
    vi.stubGlobal('innerWidth', 390);
    PILL = { left: 97, right: 293, top: 708, bottom: 764 };
    control({ left: 290.4, right: 374, top: 700, bottom: 748 });
    show();
    expect([lift(), aside()]).toEqual(['', '-11px']);
  });

  it('a drop capped by the foot, in whole px within the room: its foot stays 16 from the screen’s', () => {
    // The pill 40.5–176.5 on 320×256, the control 16–160 × 30–170. Up needs 154.5, the room 24.5:
    // 24. Down needs 137.5, the room 256 − 16 − 176.5 = 63.5: 63, not 64 (15.5 above the foot).
    // Up 24 covers 130.5, down 63 covers 74.5: down.
    vi.stubGlobal('innerHeight', 256);
    vi.stubGlobal('innerWidth', 320);
    PILL = { left: 34, right: 287, top: 40.5, bottom: 176.5 };
    control({ left: 16, right: 160, top: 30, bottom: 170 });
    show();
    expect([lift(), aside()]).toEqual(['-63px', '']);
  });

  // Review of the build (B11.4): the 8 of air above the control, held on its own.
  it('a control 7 below the pill, within the 8 of air: it moves, 1 up', () => {
    // Too wide to slide past (aside needs 111, the gutter leaves 81); up 764 − (771 − 8) = 1.
    control({ left: 16, right: 200, top: 771, bottom: 819 });
    show();
    expect([lift(), aside()]).toEqual(['1px', '']);
  });

  // Review of the build (B11.4): each of the three ways a placement is asked for with no scroll.
  it('without ResizeObserver, a resize alone places the pill again (a shorter window, no scroll)', () => {
    // 390×920: the pill 784–840, « Carte » riding at 848–896, 8 below it: no move. The window
    // made 844 tall: the pill 708–764, and the list's end on the screen stops « Carte » at
    // 700–748, level with it. Only `resize` fires: there is no observer and no scroll.
    vi.stubGlobal('ResizeObserver', undefined);
    vi.stubGlobal('innerHeight', 920);
    PILL = { left: 97, right: 293, top: 784, bottom: 840 };
    const el = control({ left: 16, right: 101, top: 848, bottom: 896 });
    show();
    expect([lift(), aside()]).toEqual(['', '']);
    vi.stubGlobal('innerHeight', 844);
    PILL = { left: 97, right: 293, top: 708, bottom: 764 };
    el.getBoundingClientRect = () => box({ left: 16, right: 101, top: 700, bottom: 748 });
    act(() => {
      window.dispatchEvent(new Event('resize'));
    });
    expect([lift(), aside()]).toEqual(['', '12px']);
  });

  it('a control that grows with no scroll or resize: its own ResizeObserver places the pill again', () => {
    // A ResizeObserver that calls back only for what it observes, as a browser's does.
    const observers: { call: () => void; seen: Set<Element> }[] = [];
    vi.stubGlobal(
      'ResizeObserver',
      class {
        seen = new Set<Element>();
        call: () => void;
        constructor(cb: () => void) {
          this.call = cb;
          observers.push(this);
        }
        observe(el: Element) {
          this.seen.add(el);
        }
        disconnect() {
          this.seen.clear();
        }
      },
    );
    const el = control({ left: 16, right: 101, top: 772, bottom: 820 });
    show();
    expect([lift(), aside()]).toEqual(['', '']);
    // Its text grows: 12 taller, its top 760, within 8 of the pill's foot at 764.
    el.getBoundingClientRect = () => box({ left: 16, right: 101, top: 760, bottom: 820 });
    act(() => {
      for (const o of observers) if (o.seen.has(el)) o.call();
    });
    expect([lift(), aside()]).toEqual(['', '12px']);
  });

  it('a slide that fits only before rounding is not taken: the pill stays 16 from the side', () => {
    // The pill 97.4–293.4: the gutter leaves 390 − 16 − 293.4 = 80.6 on the right. The control ends
    // at 169.6, so aside needs 80.2, worn as 81, which would end the pill 15.6 from the side.
    // Not taken: up 764 − (700 − 8) = 72 or down 748 + 8 − 708 = 48, the shorter: down.
    PILL = { left: 97.4, right: 293.4, top: 708, bottom: 764 };
    control({ left: 16, right: 169.6, top: 700, bottom: 748 });
    show();
    expect([lift(), aside()]).toEqual(['-48px', '']);
  });

});

/// The salon page (B11.4's cover, then B11.5): the toast's home is `aboveBookingBar`'s, in rem,
/// and the booking bar is a `data-floating-control`, so the same measure runs from that home.
/// jsdom has no rem: the pill is given at the same 708–764, 80 above the foot at normal text.
describe('Toast clears the salon page’s booking bar from its own home', () => {
  const salon = () => render(<Toast toast={{ message: 'Ajouté aux favoris', kind: 'success' }} aboveBookingBar />);

  it('the bar at the screen’s foot (779–844), 15 below the pill: no move', () => {
    control({ left: 0, right: 390, top: 779, bottom: 844 });
    salon();
    expect([lift(), aside()]).toEqual(['', '']);
  });

  it('the bar stopped above the footer, level with the pill: lifted to end 8 above it', () => {
    control({ left: 0, right: 390, top: 740, bottom: 805 });
    salon();
    // 764 − (740 − 8) = 32; aside cannot clear a bar that spans the width.
    expect([lift(), aside()]).toEqual(['32px', '']);
  });

  it('the home stays the rem one, not « Carte »’s px one', () => {
    salon();
    const classes = screen.getByRole('status').className.split(' ');
    expect(classes).toEqual(expect.arrayContaining(['bottom-20', 'lg:bottom-l']));
    expect(classes).not.toContain('bottom-xxxl');
  });

  it('a toast with neither prop (every other page’s) is never measured or moved', () => {
    control({ left: 0, right: 390, top: 740, bottom: 805 });
    render(<Toast toast={{ message: 'Enregistré', kind: 'success' }} />);
    expect([lift(), aside()]).toEqual(['', '']);
    expect(pillReads).toBe(0);
  });
});

/// Variant « noheart »: a slide is refused where it would bring the pill over another control's
/// label, the box of its text, that the pill does not cover at home; the pill then rises or
/// drops as it would without room aside. jsdom has no Range boxes, so each text's box is given.
/// The control is level with the pill at 16–101 × 700–748, so the slide is 12 right, to 109–305.
describe('a slide that would newly cover another control’s label', () => {
  const at: Record<string, R> = {};
  beforeEach(() => {
    Range.prototype.getBoundingClientRect = function (this: Range) {
      return box(at[this.startContainer.textContent ?? ''] ?? { left: 0, right: 0, top: 0, bottom: 0 });
    };
  });
  afterEach(() => {
    for (const k of Object.keys(at)) delete at[k];
    delete (Range.prototype as Partial<Range>).getBoundingClientRect;
  });
  const add = (tag: 'a' | 'button', text: string, r: R) => {
    const el = document.createElement(tag);
    if (tag === 'a') el.setAttribute('href', '/salon-b');
    el.textContent = text;
    document.body.appendChild(el);
    at[text] = r;
  };

  it('a row’s ♥ the slide would newly cover (the browser’s 200 % font at 320): it drops instead', () => {
    add('button', '♥', { left: 300, right: 318, top: 724, bottom: 744 });
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    // Slid, the pill would end at 305, over the ♥ from 300; at home it ends at 293. Up 72, down
    // 748 + 8 − 708 = 48 within the 64 of room below: the shorter, down.
    expect([lift(), aside()]).toEqual(['-48px', '']);
  });

  it('a link’s words the slide would newly cover count too', () => {
    add('a', 'Salon B', { left: 298, right: 360, top: 712, bottom: 730 });
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    expect([lift(), aside()]).toEqual(['-48px', '']);
  });

  it('a slide left that would newly cover a label: refused as well', () => {
    add('button', '♥', { left: 80, right: 95, top: 724, bottom: 744 });
    control({ left: 290, right: 374, top: 700, bottom: 748 });
    show();
    // Slid 11 left, the pill would start at 86, over the ♥ to 95; at home it starts at 97. Up 72, down 48: the shorter, down.
    expect([lift(), aside()]).toEqual(['-48px', '']);
  });

  it('where the browser gives text no box (jsdom), no label is seen and the slide is taken', () => {
    delete (Range.prototype as Partial<Range>).getBoundingClientRect;
    add('button', '♥', { left: 300, right: 318, top: 724, bottom: 744 });
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    expect([lift(), aside()]).toEqual(['', '12px']);
  });

  it('a ♥ the pill already covers at home: the slide does not hide it, and is taken', () => {
    add('button', '♥', { left: 285, right: 303, top: 724, bottom: 744 });
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    expect([lift(), aside()]).toEqual(['', '12px']);
  });

  it('labels the slid pill does not reach, beside it or above its band: the slide is taken', () => {
    add('button', '♥', { left: 306, right: 324, top: 724, bottom: 744 });
    add('a', 'Salon C', { left: 120, right: 340, top: 680, bottom: 700 });
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    expect([lift(), aside()]).toEqual(['', '12px']);
  });

  it('the floating control’s own words and the toast’s « Annuler » are not other controls', () => {
    at.Carte = { left: 300, right: 318, top: 724, bottom: 744 };
    at.Annuler = { left: 300, right: 318, top: 724, bottom: 744 };
    control({ left: 16, right: 101, top: 700, bottom: 748 }).textContent = 'Carte';
    render(
      <Toast
        toast={{ message: 'Ajouté aux favoris', kind: 'success', action: { label: 'Annuler', onAction: () => {} } }}
        aboveFloatingControl
      />,
    );
    expect([lift(), aside()]).toEqual(['', '12px']);
  });

  // Review of the port (B11.5): what the label check must and must not count.
  it('a label the slide reaches only once worn in whole px: refused as well', () => {
    // The control ends at 101.4: aside needs 12.4, worn as 13, so the pill would end at 306, over
    // the ♥ from 305.6 (before rounding it would end at 305.4, short of it).
    // Up 72, down 48: the shorter, down.
    add('button', '♥', { left: 305.6, right: 323, top: 724, bottom: 744 });
    control({ left: 16, right: 101.4, top: 700, bottom: 748 });
    show();
    expect([lift(), aside()]).toEqual(['-48px', '']);
  });

  it('a label in the slid pill’s columns but above its band: the slide is taken', () => {
    // 296–304 is inside the slid pill's 109–305 and outside its home 97–293, but 680–700 is above
    // its 708–764: nothing is covered.
    add('a', 'Salon D', { left: 296, right: 304, top: 680, bottom: 700 });
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    expect([lift(), aside()]).toEqual(['', '12px']);
  });

  // Review of the build (B11.4): a row's link carries words for screen readers only (`sr-only`,
  // absolutely placed and clipped), whose Range box is as wide as the words though nothing shows.
  const linkWithHidden = (hiddenStyle: Partial<CSSStyleDeclaration>) => {
    const link = document.createElement('a');
    link.setAttribute('href', '/salon-g');
    link.textContent = 'Salon G';
    const hidden = document.createElement('span');
    hidden.textContent = 'pas encore d’avis';
    Object.assign(hidden.style, hiddenStyle);
    link.appendChild(hidden);
    document.body.appendChild(link);
    // The words shown stand beside the slid pill (109–305); the hidden ones run under it.
    at['Salon G'] = { left: 310, right: 360, top: 712, bottom: 730 };
    at['pas encore d’avis'] = { left: 296, right: 420, top: 712, bottom: 730 };
  };

  it('words only a screen reader reads (`sr-only`) are no part of a label: the slide is taken', () => {
    linkWithHidden({ position: 'absolute', clip: 'rect(0px, 0px, 0px, 0px)' });
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    expect([lift(), aside()]).toEqual(['', '12px']);
  });

  it('words placed absolutely but not clipped (a badge) are seen, and count', () => {
    linkWithHidden({ position: 'absolute' });
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    // Up 72, down 48: the shorter, down.
    expect([lift(), aside()]).toEqual(['-48px', '']);
  });

  it('a control with no text (a row’s photo link) has no label, whatever its tap area', () => {
    const link = document.createElement('a');
    link.setAttribute('href', '/salon-e');
    link.getBoundingClientRect = () => box({ left: 296, right: 380, top: 700, bottom: 770 });
    document.body.appendChild(link);
    control({ left: 16, right: 101, top: 700, bottom: 748 });
    show();
    expect([lift(), aside()]).toEqual(['', '12px']);
  });
});
