'use client';

// Design: docs/design/web-pro-upload-resize.md §2.4 and §2.7 (the review of
// 2026-11-09, F3 and the focus finding).
import { type RefObject, useCallback, useEffect, useRef } from 'react';

/// The signal of the page that asked for an upload: aborted when that page
/// is left (its component unmounts), so a photo still being prepared or
/// signed is never sent, and one already sent is never added to the gallery.
/// Before this, leaving Médias 41 ms after picking a photo still put it in the
/// public gallery about 3 s later (measured by the review).
export function useLeaveSignal(): () => AbortSignal {
  const controller = useRef<AbortController | null>(null);
  useEffect(() => {
    const current = new AbortController();
    controller.current = current;
    return () => current.abort();
  }, []);
  return useCallback(() => {
    controller.current ??= new AbortController();
    return controller.current.signal;
  }, []);
}

/// Puts the focus back on `target` when `busy` ends, if the busy state took
/// it away: a control disabled while it holds the focus leaves the focus on
/// the page itself, and a keyboard user starts again from the top. Nothing
/// moves when the person has put the focus somewhere else in the meantime.
export function useFocusBackAfter(busy: boolean, target: RefObject<HTMLElement>): void {
  const wasBusy = useRef(false);
  useEffect(() => {
    if (busy) {
      wasBusy.current = true;
      return;
    }
    if (!wasBusy.current) return;
    wasBusy.current = false;
    const active = document.activeElement;
    if (!active || active === document.body) target.current?.focus();
  }, [busy, target]);
}
