'use client';

import { useEffect, useLayoutEffect, useRef } from 'react';
import { spacing } from '../../styles/tokens';

/// `useLayoutEffect` writes the room in the commit's layout phase, before the browser paints
/// (bar-clearance.test.tsx holds that a layout effect after it already sees the room); that a
/// page reached by a client-side navigation therefore never shows a frame without it follows
/// from that and is not filmed. The server has no layout, and React warns about the hook there
/// (as in BookingFlow).
const useIsoLayoutEffect = typeof window === 'undefined' ? useEffect : useLayoutEffect;

/// The room the salon page's fixed booking bar is owed (BACKLOG 103), measured. While the bar
/// shows, `<html>` gets a bottom padding as tall as the bar, so the page ends below the footer
/// and the bar stops short of the footer's last link at the page's very end; and a scroll
/// padding of the bar plus `s`, so whatever the keyboard focuses stops 8px above it (WCAG
/// 2.4.11). Measured, so it holds at every text size, where a px token falls short of the rem
/// bar. Whoever is at the page's very end when the room changes is kept at the end: the page's
/// script can arrive after a visitor has reached the footer, and the room would otherwise open
/// below the screen with the bar still on the last link. Only a change of the bar's height
/// writes or scrolls anything: a resize that leaves it alone (iOS Safari's toolbar showing or
/// hiding fires one) changes no room, so it moves no one. Rendered inside the bar, it measures
/// its parent; from `lg` the bar is hidden, its height 0, and both are taken off; taken off too
/// when the page goes. Before the script runs, neither is set.
export function BarClearance() {
  const mark = useRef<HTMLSpanElement>(null);
  useIsoLayoutEffect(() => {
    const bar = mark.current?.parentElement;
    if (!bar) return;
    const html = document.documentElement;
    const air = parseFloat(spacing.s);
    let last = -1;
    const place = () => {
      const h = bar.getBoundingClientRect().height;
      if (h === last) return;
      last = h;
      const end = html.scrollHeight - window.innerHeight;
      const atEnd = window.scrollY > 0 && window.scrollY >= end - 1;
      html.style.paddingBottom = h > 0 ? `${h}px` : '';
      html.style.scrollPaddingBottom = h > 0 ? `${h + air}px` : '';
      if (atEnd) {
        window.scrollTo({ top: html.scrollHeight - window.innerHeight, behavior: 'instant' });
      }
    };
    place();
    const seen = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(place);
    seen?.observe(bar);
    window.addEventListener('resize', place);
    return () => {
      seen?.disconnect();
      window.removeEventListener('resize', place);
      html.style.paddingBottom = '';
      html.style.scrollPaddingBottom = '';
    };
  }, []);
  return <span ref={mark} hidden />;
}
