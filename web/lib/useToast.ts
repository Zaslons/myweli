'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

/// §7 + SYSTEM §15 — the single transient-feedback entry point (the web twin of
/// the `AppSnackBar` SPEC; mobile's own implementation is still A6, so §15's
/// table is the source and nothing here is invented).
///
/// Durations are §15's, by kind: success/info 3 s · error **6 s** (an error
/// needs time to read). The « with action → 10 s » row is deliberately absent —
/// zero callers exist product-wide (mobile has exactly one in 118 calls);
/// A6/B6 adds it when a caller does (web-b5-feedback.md).
export type ToastKind = 'success' | 'info' | 'error';
export type ToastState = { message: string; kind: ToastKind } | null;

const DURATION_MS: Record<ToastKind, number> = {
  success: 3000,
  info: 3000,
  error: 6000,
};

export function useToast() {
  const [toast, setToast] = useState<ToastState>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const show = useCallback((message: string, kind: ToastKind = 'info') => {
    if (timer.current) clearTimeout(timer.current);
    setToast({ message, kind });
    timer.current = setTimeout(() => setToast(null), DURATION_MS[kind]);
  }, []);

  // Unmount must not leave a dangling setState.
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );

  return { toast, show };
}
