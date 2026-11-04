'use client';

import {
  type ReactNode,
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { type AppNotification, unreadCount } from '../../lib/account/notifications';
import { getProNotifications } from '../../lib/api/pro';
import { type LoadFailure, loadFailure } from '../../lib/api/load-failure';
import {
  PRO_NOTIFICATIONS_POLL_MS,
  arrivalAnnouncement,
  newUnreadIds,
  withUnreadPrefix,
} from '../../lib/pro/notifications';

/// The salon member's notification feed, held ONCE for the whole dashboard
/// (docs/design/web-pro-notifications.md): the sidebar entry and the phone
/// bell show its count, `/pro/notifications` shows its rows, and a row read
/// on the page lowers the count at once — one state, three readers.
///
/// **It stays current** (§3.2): read on mount, then every
/// [PRO_NOTIFICATIONS_POLL_MS] while the tab is VISIBLE, and at once when it
/// becomes visible again; a hidden tab sends nothing. A salon keeps this
/// dashboard open all day and the web has no push, so without this a new
/// booking would wait for the next page load.
///
/// **Arrivals are announced** in a polite region that is always mounted
/// (WEB-SYSTEM §7) — by id, never by the count going up: the first read
/// announces nothing, and a row a refused write puts back to unread is not
/// « new ». The tab title carries the count, re-applied when a navigation
/// rewrites the title.

type Status = 'loading' | 'ready' | 'error' | 'signedOut';

export type ProNotificationsValue = {
  items: AppNotification[];
  status: Status;
  failure: LoadFailure | false;
  unread: number;
  /// A visible read — the page's « Réessayer ».
  reload: () => Promise<void>;
  /// A background read — keeps what is on screen if it fails.
  refresh: () => Promise<void>;
  setRead: (ids: ReadonlySet<string>, read: boolean) => void;
};

const ProNotificationsContext = createContext<ProNotificationsValue | null>(null);

export function useProNotifications(): ProNotificationsValue {
  const ctx = useContext(ProNotificationsContext);
  if (!ctx) {
    throw new Error('useProNotifications requires <ProNotificationsProvider>');
  }
  return ctx;
}

/// For the sidebar, which its unit tests also mount bare — null there.
export function useOptionalProNotifications(): ProNotificationsValue | null {
  return useContext(ProNotificationsContext);
}

export function ProNotificationsProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<AppNotification[]>([]);
  const [status, setStatus] = useState<Status>('loading');
  const [failure, setFailure] = useState<LoadFailure | false>(false);
  const [announcement, setAnnouncement] = useState({ text: '', seq: 0 });
  // What the last successful read returned — the arrival baseline (null
  // until the first one, so the first one announces nothing).
  const lastRead = useRef<AppNotification[] | null>(null);
  // Only the newest read may land: a slow older answer must not overwrite a
  // newer one.
  const seq = useRef(0);
  const signedOut = useRef(false);

  const read = useCallback(async (quiet: boolean) => {
    if (signedOut.current) return;
    const mine = ++seq.current;
    if (!quiet) {
      setStatus('loading');
      setFailure(false);
    }
    const r = await getProNotifications();
    if (mine !== seq.current) return;
    if (r.status === 401) {
      // The session is gone: stop reading. The page sends the person to
      // /pro/connexion; the membership probe owns everything else.
      signedOut.current = true;
      setStatus('signedOut');
      return;
    }
    if (r.status !== 200) {
      // A background read that fails keeps the rows on screen.
      if (!quiet || lastRead.current === null) {
        setStatus('error');
        setFailure(loadFailure(r.status));
      }
      return;
    }
    const arrived = newUnreadIds(lastRead.current, r.items);
    lastRead.current = r.items;
    setItems(r.items);
    setStatus('ready');
    setFailure(false);
    if (arrived.length > 0) {
      setAnnouncement((a) => ({
        text: arrivalAnnouncement(arrived.length),
        seq: a.seq + 1,
      }));
    }
  }, []);

  const reload = useCallback(() => read(false), [read]);
  const refresh = useCallback(() => read(true), [read]);

  useEffect(() => {
    void read(false);
    const whenVisible = () => {
      if (document.visibilityState === 'visible') void read(true);
    };
    const timer = setInterval(whenVisible, PRO_NOTIFICATIONS_POLL_MS);
    document.addEventListener('visibilitychange', whenVisible);
    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', whenVisible);
    };
  }, [read]);

  const setRead = useCallback((ids: ReadonlySet<string>, isRead: boolean) => {
    // A read already in flight was asked BEFORE this gesture: its answer
    // would put the row back the way it was. Drop it; the next one is fresh.
    seq.current++;
    setItems((cur) => cur.map((n) => (ids.has(n.id) ? { ...n, read: isRead } : n)));
  }, []);

  const unread = unreadCount(items);

  // « (3) Pro — Aujourd’hui ». A navigation rewrites the title, so the
  // prefix is re-applied whenever the head changes; `withUnreadPrefix` is
  // idempotent, so the write it makes cannot trigger another.
  useEffect(() => {
    const apply = () => {
      const next = withUnreadPrefix(document.title, unread);
      if (next !== document.title) document.title = next;
    };
    apply();
    const observer = new MutationObserver(apply);
    observer.observe(document.head, {
      childList: true,
      subtree: true,
      characterData: true,
    });
    return () => {
      observer.disconnect();
      document.title = withUnreadPrefix(document.title, 0);
    };
  }, [unread]);

  const value = useMemo<ProNotificationsValue>(
    () => ({ items, status, failure, unread, reload, refresh, setRead }),
    [items, status, failure, unread, reload, refresh, setRead],
  );

  return (
    <ProNotificationsContext.Provider value={value}>
      {children}
      {/* Always mounted: a live region must exist before its text lands. */}
      <p
        role="status"
        aria-live="polite"
        className="sr-only"
        data-testid="pro-notifications-announcer"
      >
        <span key={announcement.seq}>{announcement.text}</span>
      </p>
    </ProNotificationsContext.Provider>
  );
}
