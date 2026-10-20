'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

/// §7 + SYSTEM §15 — the single transient-feedback entry point (the web twin of
/// the `AppSnackBar` SPEC; mobile's own implementation is still A6, so §15's
/// table is the source and nothing here is invented).
///
/// Durations are §15's, by kind: success/info 3 s · error **6 s** (an error
/// needs time to read) · **with an action, 10 s** — the row that waited for
/// its first caller, which is Médias' « Annuler » after a delete, where the
/// toast is the only route back (docs/design/web-pro-medias-like-app.md).
export type ToastKind = 'success' | 'info' | 'error';
export type ToastAction = { label: string; onAction: () => void };
export type ToastState = { message: string; kind: ToastKind; action?: ToastAction } | null;

const ACTION_MS = 10000;

const DURATION_MS: Record<ToastKind, number> = {
  success: 3000,
  info: 3000,
  error: 6000,
};

export function useToast() {
  const [toast, setToast] = useState<ToastState>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const show = useCallback(
    (message: string, kind: ToastKind = 'info', action?: ToastAction) => {
      if (timer.current) clearTimeout(timer.current);
      setToast({ message, kind, action });
      timer.current = setTimeout(
        () => setToast(null),
        action ? ACTION_MS : DURATION_MS[kind],
      );
    },
    [],
  );

  /// Closes it now — an action taken has done its job.
  const dismiss = useCallback(() => {
    if (timer.current) clearTimeout(timer.current);
    setToast(null);
  }, []);

  // Unmount must not leave a dangling setState.
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );

  return { toast, show, dismiss };
}
