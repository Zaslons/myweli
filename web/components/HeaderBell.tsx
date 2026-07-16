'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { unreadCount } from '../lib/account/notifications';
import { getNotifications } from '../lib/api/account';

/// Header bell (parity 5.1): one fetch on mount, no polling. Anonymous
/// sessions get a BFF 401 without a backend call → render nothing.
export function HeaderBell() {
  const [state, setState] = useState<{ authed: boolean; unread: number }>({
    authed: false,
    unread: 0,
  });

  useEffect(() => {
    let active = true;
    getNotifications().then((r) => {
      if (!active || r.status !== 200) return;
      setState({ authed: true, unread: unreadCount(r.items) });
    });
    return () => {
      active = false;
    };
  }, []);

  if (!state.authed) return null;

  return (
    <Link
      href="/mon-compte/notifications"
      aria-label={
        state.unread > 0
          ? `Notifications (${state.unread} non lues)`
          : 'Notifications'
      }
      className="relative text-textPrimary hover:text-textSecondary"
    >
      <svg viewBox="0 0 24 24" className="h-5 w-5" fill="currentColor" aria-hidden>
        <path d="M12 22a2 2 0 0 0 2-2h-4a2 2 0 0 0 2 2zm6-6v-5a6 6 0 0 0-4.5-5.8V4.5a1.5 1.5 0 0 0-3 0v.7A6 6 0 0 0 6 11v5l-2 2v1h16v-1l-2-2z" />
      </svg>
      {state.unread > 0 ? (
        <span className="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-pill border-2 border-secondary bg-error" />
      ) : null}
    </Link>
  );
}
