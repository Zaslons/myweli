'use client';

import Link from 'next/link';
import { Icon } from './Icon';
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
      className="-my-sm -ml-sm flex min-h-12 min-w-12 items-center justify-center text-textPrimary hover:text-textSecondary"
    >
      <span className="relative">
        <Icon name="bell" size="iconS" />
        {state.unread > 0 ? (
          <span className="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-pill border-2 border-secondary bg-error" />
        ) : null}
      </span>
    </Link>
  );
}
