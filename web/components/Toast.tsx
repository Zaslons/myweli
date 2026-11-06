'use client';

import { useEffect, useRef } from 'react';
import type { ToastState } from '../lib/useToast';
import { spacing } from '../styles/tokens';

/// The air kept between the pill and a floating control: `s`, which is what the fixed 80px
/// lift left above « Carte » riding at 24–72 (B11.5).
const AIR = parseFloat(spacing.s);
/// The pill never moves nearer the screen's edges than the page's gutter, `m` (WEB-SYSTEM §9).
const EDGE = parseFloat(spacing.m);

type Box = { left: number; right: number; top: number; bottom: number };
/// A move: `x` to the right, `y` up.
type Move = [x: number, y: number];
const meets = (p: Box, c: Box) =>
  c.left - AIR < p.right && p.left < c.right + AIR && c.top - AIR < p.bottom && p.top < c.bottom + AIR;
const moved = (p: Box, [x, y]: Move): Box => ({ left: p.left + x, right: p.right + x, top: p.top - y, bottom: p.bottom - y });
/// How much of the pill's height stands on the controls it meets, air included.
const covered = (p: Box, cs: Box[]) =>
  cs.reduce((sum, c) => (meets(p, c) ? sum + Math.min(p.bottom, c.bottom + AIR) - Math.max(p.top, c.top - AIR) : sum), 0);
const over = (a: Box, b: Box) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;

/// Words only a screen reader reads (`sr-only`: placed absolutely and clipped to nothing) are not
/// seen, yet their Range box is as wide as the words: inside a row's link at 320, « salon, pas
/// encore d’avis » ran the label 45px past the visible text. So they are no part of a label.
function unseen(text: Node, control: Element): boolean {
  for (let el = text.parentElement; el; el = el === control ? null : el.parentElement) {
    const style = getComputedStyle(el);
    if (style.position === 'absolute' && style.clip && style.clip !== 'auto') return true;
  }
  return false;
}

/// The label of every other control on the screen, one box each: the box of its visible text,
/// which is what a person reads and aims at (a row's ♥, a link's words), not its tap area, which
/// is larger and mostly empty. Links and buttons only; the floating controls and what is inside
/// the toast (its « Annuler ») are not counted; a control with no visible text has no label here.
function labels(region: Element): Box[] {
  // jsdom has no Range boxes: there no label is seen, so no slide is refused.
  if (typeof Range === 'undefined' || typeof Range.prototype.getBoundingClientRect !== 'function') return [];
  const range = document.createRange();
  const out: Box[] = [];
  for (const el of document.querySelectorAll('a[href], button')) {
    if (region.contains(el) || el.closest('[data-floating-control]')) continue;
    let label: Box | null = null;
    const texts = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    for (let t = texts.nextNode(); t; t = texts.nextNode()) {
      if (!t.textContent?.trim() || unseen(t, el)) continue;
      range.selectNodeContents(t);
      const r = range.getBoundingClientRect();
      if (!r.width || !r.height) continue;
      label = label
        ? { left: Math.min(label.left, r.left), right: Math.max(label.right, r.right), top: Math.min(label.top, r.top), bottom: Math.max(label.bottom, r.bottom) }
        : { left: r.left, right: r.right, top: r.top, bottom: r.bottom };
    }
    if (label) out.push(label);
  }
  return out;
}

/// Where the pill goes when it would meet a floating control: aside, within the gutters, where
/// it covers the same band it always does, unless that would cover another control's label it
/// does not cover at home; else just above the control or just below it, whichever is the
/// shorter move (the nearer side). Never nearer an edge than `EDGE`. Where none of these clears it
/// (a very short screen at a large text size), the pill stays whole on the screen where it
/// covers the control least.
///
/// Why a label, any part of it, and only a new one: the slide's measured cost was the ♥ of the
/// salon beside « Carte », hidden at the browser's 200 % font on 320-wide phones; at normal text
/// the slide met only the hearts' tap areas, so a tap area would refuse slides that hide
/// nothing. A glyph partly covered is already misread, and any threshold would be arbitrary.
/// What the pill already covers at home is not the slide's doing, so it does not count.
///
/// Every move is tried as the pill will wear it, in whole px: what a move needs is rounded up
/// (a whole slide fits its gutter only if it fits it rounded down), and a rise or drop the room
/// caps is that room rounded down. So a move that fits only before rounding is not taken, and
/// every check sees the pill where it will stand (else the rounding could end a move 15.6 from a
/// side or 15.1 from the top, or carry it past what a check saw).
function bestMove(home: Box, cs: Box[], width: number, height: number, slide: boolean, others: () => Box[]): Move {
  const hit = cs.filter((c) => meets(home, c));
  if (hit.length === 0) return [0, 0];
  const clears = (m: Move) => !cs.some((c) => meets(moved(home, m), c));
  const hides = (m: Move) => others().some((l) => over(moved(home, m), l) && !over(home, l));
  if (slide) {
    const right = Math.ceil(Math.max(...hit.map((c) => c.right + AIR - home.left)));
    const left = Math.ceil(Math.max(...hit.map((c) => home.right - (c.left - AIR))));
    if (right <= width - EDGE - home.right && clears([right, 0]) && !hides([right, 0])) return [right, 0];
    if (left <= home.left - EDGE && clears([-left, 0]) && !hides([-left, 0])) return [-left, 0];
  }
  const up = Math.min(Math.ceil(Math.max(...hit.map((c) => home.bottom - (c.top - AIR)))), Math.floor(home.top - EDGE));
  const down = Math.min(Math.ceil(Math.max(...hit.map((c) => c.bottom + AIR - home.top))), Math.floor(height - EDGE - home.bottom));
  const rise: Move = [0, Math.max(0, up)];
  const drop: Move = [0, -Math.max(0, down)];
  // The nearer side: the shorter of the two is tried first, so where both clear, or both cover
  // the control as much, it wins. The same length goes up.
  const vertical: Move[] = -drop[1] < rise[1] ? [[0, 0], drop, rise] : [[0, 0], rise, drop];
  return vertical.reduce((best, m) => (covered(moved(home, m), cs) < covered(moved(home, best), cs) ? m : best));
}

/// The shared toast (§7, §10) — pairs with `useToast`.
///
/// The live region is ALWAYS rendered and the pill swaps INSIDE it: §7's own
/// rule is that the region must exist in the DOM **before** the text lands, or
/// nothing is read. Every pre-B5 toast mounted the region together with its
/// text ({toast ? <div role="status">…} — including the one that had
/// `role="status"`), which is exactly the unreliable shape. Keep this component
/// mounted unconditionally and let `toast` be null.
///
/// Kinds wear §15's colors: success/info = the brand pill (`bg-primary`),
/// error = `bg-error` (#8B0000 — ~10.6:1 under `secondary` white text).
/// Position: fixed bottom-center on `z-toast` — feedback is always on top (§9);
/// the pre-B5 EquipeClient toast had no z token and painted on DOM-order luck.
export function Toast({
  toast,
  aboveFloatingControl = false,
  aboveBookingBar = false,
}: {
  toast: ToastState;
  /// The page has a floating control at the bottom under `lg`, marked `data-floating-control`:
  /// the search's « Carte »/« Liste » (this prop) or the salon page's booking bar
  /// (`aboveBookingBar`). Each prop gives the toast its home, centred above the band its control
  /// rides in. From that home the pill is measured against every marked control: where one
  /// stands anywhere else — stopped above the footer, resting under a short list, or taller
  /// because the text is larger — and comes within `s` of the pill, the pill is moved clear of
  /// it (`bestMove`): aside first, if that fits within the `m` gutters and covers no other
  /// control's label it does not cover at home, even where a shorter move up or down would
  /// clear; else up or down, whichever is the shorter move (the nearer side); where none clears,
  /// kept whole on the screen where it covers the control least. So the two never meet where
  /// the screen has room
  /// (docs/design/web-swiss-salon.md §2.3, B11.5). This replaces decision 86's « the toast
  /// stays where it is ».
  ///
  /// « Carte »'s home is 80px (`bottom-xxxl` + `pb-m`), px like the 24–72px band the button
  /// rides at normal text.
  aboveFloatingControl?: boolean;
  /// The salon page's booking bar under `lg` (docs/design/web-swiss-salon.md §1.4): 65px at
  /// normal text, but its « Réserver » is `min-h-12`, which is rem, so with the browser's text
  /// at double size (a 32px root) the bar is 113px. The home is `bottom-20`, 5rem, rem like
  /// the bar: 80px at normal text, the same place as « Carte »'s, 15px clear of the bar; 160px
  /// at a 32px root, 47px clear. The px home left the pill over the bar there, and at 320 and
  /// 360 « Annuler » took a corner of « Réserver », so a press there undid the favourite. From
  /// this home the pill is measured and moved as above, where the bar still comes near it: at
  /// the page's end, where the bar stops above the footer, or with text enlarged otherwise.
  aboveBookingBar?: boolean;
}) {
  const region = useRef<HTMLDivElement>(null);
  // Both homes are measured from; a toast with neither (every other page's) never moves.
  const measured = aboveFloatingControl || aboveBookingBar;

  // The move is runtime geometry, not a token. It is written straight on the region's style,
  // not through state, so every frame reads the move the pill really wears: `margin-bottom` up
  // or down, and `translate` aside, which leaves the region's width, and so the pill's wrapping,
  // as it is.
  useEffect(() => {
    const box = region.current;
    if (!box) return;
    if (!measured || !toast) {
      box.style.marginBottom = '';
      box.style.translate = '';
      return;
    }
    // An old browser without the `translate` property would not show the slide while this
    // code believed it: there the pill only goes up or down.
    const slide = typeof CSS === 'undefined' || typeof CSS.supports !== 'function' || CSS.supports('translate', '1px');
    let frame = 0;
    const place = () => {
      frame = 0;
      const pill = box.firstElementChild;
      if (!pill) return;
      const r = pill.getBoundingClientRect();
      // Where the classes put the pill, without the move it wears now.
      const wornX = parseFloat(box.style.translate) || 0;
      const wornY = parseFloat(box.style.marginBottom) || 0;
      const home = { left: r.left - wornX, right: r.right - wornX, top: r.top + wornY, bottom: r.bottom + wornY };
      const height = window.innerHeight;
      // A control that is not displayed (`lg:hidden`, `md:landscape:hidden`) has a 0×0 box at the
      // screen's corner, and one off the screen has nothing to clear: neither counts. A safeguard:
      // with the pill kept `m` from every edge, such a box cannot come within `s` of it today.
      const cs = [...document.querySelectorAll('[data-floating-control]')]
        .map((el) => el.getBoundingClientRect())
        .filter((c) => c.bottom > 0 && c.top < height);
      // The other controls' labels, read only if a slide is weighed, and once.
      let seen: Box[] | null = null;
      const others = () => (seen ??= labels(box));
      const [x, y] = bestMove(home, cs, document.documentElement.clientWidth || window.innerWidth, height, slide, others);
      if (y !== wornY) box.style.marginBottom = y ? `${y}px` : '';
      if (x !== wornX) box.style.translate = x ? `${x}px` : '';
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(place);
    };
    place();
    window.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('resize', schedule);
    // jsdom has no ResizeObserver, nor has an old WebView. An effect that throws takes the
    // page down with it, so without one the scroll and resize listeners place the pill alone.
    const seen = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(schedule);
    const watch = () => document.querySelectorAll('[data-floating-control]').forEach((el) => seen?.observe(el));
    if (seen && box.firstElementChild) seen.observe(box.firstElementChild);
    watch();
    // A control that appears while the message shows (« Liste » after « Carte », at the top
    // already, so no scroll follows) is placed against too.
    const added =
      typeof MutationObserver === 'undefined'
        ? null
        : new MutationObserver(() => {
            watch();
            schedule();
          });
    added?.observe(document.body, { childList: true, subtree: true });
    return () => {
      if (frame) cancelAnimationFrame(frame);
      window.removeEventListener('scroll', schedule);
      window.removeEventListener('resize', schedule);
      seen?.disconnect();
      added?.disconnect();
    };
  }, [measured, toast]);

  return (
    <div
      ref={region}
      role="status"
      aria-live="polite"
      className={`pointer-events-none fixed left-1/2 z-toast -translate-x-1/2 ${
        aboveBookingBar
          ? 'bottom-20 lg:bottom-l'
          : aboveFloatingControl
            ? 'bottom-xxxl pb-m lg:bottom-l lg:pb-0'
            : 'bottom-l'
      }`}
    >
      {toast ? (
        <div
          className={`flex items-center gap-m rounded-lg px-l py-s text-bodyMedium text-secondary shadow-lg ${
            toast.kind === 'error' ? 'bg-error' : 'bg-primary'
          }`}
        >
          {toast.message}
          {toast.action ? (
            // The container lets clicks through; its one control takes them.
            <button
              type="button"
              onClick={toast.action.onAction}
              className="pointer-events-auto -my-s min-h-12 font-semibold text-secondary underline"
            >
              {toast.action.label}
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
