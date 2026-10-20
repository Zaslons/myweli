'use client';

import { useEffect } from 'react';
import { registerIfGranted } from '../../lib/pro/browser-push';
import { getBrowserPushDeps } from '../../lib/pro/browser-push-deps';
import { useProNotifications } from './ProNotificationsContext';

/// The shell's half of the browser notifications
/// (docs/design/web-pro-browser-push.md §2): at sign-in, a browser already
/// permitted registers again without a question (as the app does at login —
/// also how a token Firebase rotated reaches the server); and a push the
/// service worker received makes an open tab re-read the feed now, not in its
/// next 60 s.
export function BrowserPushBridge() {
  const { refresh } = useProNotifications();

  useEffect(() => {
    void registerIfGranted(getBrowserPushDeps());
  }, []);

  useEffect(() => {
    const sw = typeof navigator === 'undefined' ? undefined : navigator.serviceWorker;
    if (!sw) return;
    const onMessage = (e: MessageEvent) => {
      if ((e.data as { type?: unknown } | null)?.type === 'myweli-pro-push') void refresh();
    };
    sw.addEventListener('message', onMessage);
    return () => sw.removeEventListener('message', onMessage);
  }, [refresh]);

  return null;
}
