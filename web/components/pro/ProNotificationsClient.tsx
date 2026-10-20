'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { type ReactNode, useEffect, useRef, useState } from 'react';
import type { AppNotification } from '../../lib/account/notifications';
import {
  markAllProNotificationsRead,
  markProNotificationRead,
} from '../../lib/api/pro';
import { writeFailureMessage } from '../../lib/api/network';
import { formatDateTimeFr } from '../../lib/format';
import { loadFailureMessage } from '../../lib/pro/load-failure';
import { proWebRouteFor, salonOf } from '../../lib/pro/notifications';
import { Button } from '../Button';
import { EmptyState } from '../EmptyState';
import { ErrorState } from '../ErrorState';
import { Icon, notificationIcon } from '../Icon';
import { SkeletonRows } from '../Skeleton';
import { BrowserPushPreference, useBrowserPushRow } from './BrowserPushPreference';
import { EmailAlertsPreference } from './EmailAlertsPreference';
import { useProMembership } from './ProMembershipContext';
import { useProNotifications } from './ProNotificationsContext';

const TITLE = 'Notifications';

/// The salon's notification center — `/pro/notifications`
/// (docs/design/web-pro-notifications.md §3.3). The app's
/// `ProNotificationsScreen` flow, web-adapted: the rows the server writes for
/// this member (a new booking, a client's reschedule or cancellation, a
/// deposit proof), newest first; a row is a LINK to its booking — read on
/// click, its salon carried along so the detail switches to it first;
/// « Tout marquer comme lu » while anything is unread.
///
/// The rows live in `ProNotificationsProvider` (the shell's), so reading one
/// here lowers the count on the sidebar entry and the phone bell at once.
export function ProNotificationsClient() {
  const router = useRouter();
  const feed = useProNotifications();
  const { salons, email } = useProMembership();
  const pushRow = useBrowserPushRow();
  // A « marquer comme lu » the server refused: under its row, or under the
  // header for « Tout marquer comme lu » (`at: 'all'`) — the client center's
  // rule (web-consumer-optimistic-revert.md §3.2).
  const [readError, setReadError] = useState<{ at: string; message: string } | null>(null);
  const readAllRef = useRef<HTMLButtonElement>(null);

  // Arriving here: a fresh read — the count may be up to a minute old. Not
  // on the very first dashboard load, which is already reading.
  const { refresh, status } = feed;
  const statusOnArrival = useRef(status);
  useEffect(() => {
    if (statusOnArrival.current === 'ready') void refresh();
  }, [refresh]);

  useEffect(() => {
    if (status === 'signedOut') router.replace('/pro/connexion');
  }, [status, router]);

  // « Tout marquer comme lu » leaves while it is out, and focus with it:
  // back on the button with the failure — never stolen from elsewhere.
  useEffect(() => {
    if (readError?.at !== 'all') return;
    const active = document.activeElement;
    if (!active || active === document.body) readAllRef.current?.focus();
  }, [readError]);

  /// Read at once; the navigation never waits for the write. If the server
  /// refuses, this one row is unread again (everywhere — it is one state) and,
  /// while this page is still here, says why under it.
  function markOne(n: AppNotification) {
    if (n.read) return;
    const one = new Set([n.id]);
    setReadError(null);
    feed.setRead(one, true);
    void markProNotificationRead(n.id).then((r) => {
      if (r.ok) return;
      feed.setRead(one, false);
      setReadError({ at: n.id, message: writeFailureMessage(r.status) });
    });
  }

  /// On a failure only what THIS gesture marked goes back to unread
  /// (SYSTEM §15: undo is never a snapshot).
  async function readAll() {
    const marked = new Set(feed.items.filter((x) => !x.read).map((x) => x.id));
    setReadError(null);
    feed.setRead(marked, true);
    const r = await markAllProNotificationsRead();
    if (r.ok) return;
    feed.setRead(marked, false);
    setReadError({ at: 'all', message: writeFailureMessage(r.status) });
  }

  if (status === 'loading' || status === 'signedOut') {
    return (
      <Page>
        <h1 className="text-headlineSmall font-semibold text-textPrimary">{TITLE}</h1>
        <SkeletonRows count={5} className="mt-l" />
      </Page>
    );
  }
  if (status === 'error') {
    return (
      <Page>
        <ErrorState
          title={TITLE}
          message={loadFailureMessage(feed.failure)}
          onRetry={() => void feed.reload()}
        />
      </Page>
    );
  }

  // The salon a row is about matters only to an account with more than one.
  const salonNames =
    salons.length > 1 ? new Map(salons.map((s) => [s.salonId, s.salonName])) : null;

  return (
    <Page>
      <div className="flex flex-wrap items-center justify-between gap-m">
        <h1 className="text-headlineSmall font-semibold text-textPrimary">{TITLE}</h1>
        {feed.unread > 0 ? (
          <Button ref={readAllRef} variant="secondary" onClick={readAll}>
            Tout marquer comme lu
          </Button>
        ) : null}
      </div>
      {readError?.at === 'all' ? (
        <p role="alert" className="mt-s text-bodyMedium text-error">
          {readError.message}
        </p>
      ) : null}

      {feed.items.length === 0 ? (
        <EmptyState
          className="mt-l"
          icon="bell"
          title="Aucune notification"
          description="Les réservations, reports, annulations et acomptes de vos clients apparaîtront ici."
        />
      ) : (
        <ul className="mt-l space-y-s">
          {feed.items.map((n) => {
            const href = proWebRouteFor(n.route);
            const salonId = salonOf(n.route);
            const salonName = salonId ? salonNames?.get(salonId) : undefined;
            const content = <RowContent n={n} salonName={salonName} />;
            const rowClass =
              'flex w-full items-start gap-m rounded-xl border border-border bg-secondary p-m text-left hover:bg-surfaceVariant';
            return (
              <li key={n.id}>
                {href ? (
                  <Link href={href} onClick={() => markOne(n)} className={rowClass}>
                    {content}
                  </Link>
                ) : (
                  // A row with nowhere to go still reads on a click.
                  <button type="button" onClick={() => markOne(n)} className={rowClass}>
                    {content}
                  </button>
                )}
                {readError?.at === n.id ? (
                  <p role="alert" className="mt-xs text-bodyMedium text-error">
                    {readError.message}
                  </p>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
      <EmailAlertsPreference
        email={email}
        leading={pushRow ? <BrowserPushPreference /> : null}
      />
    </Page>
  );
}

/// The reading width (B7: reading pages `max-w-3xl`) — every state shares it.
function Page({ children }: { children: ReactNode }) {
  return <div className="max-w-3xl">{children}</div>;
}

function RowContent({ n, salonName }: { n: AppNotification; salonName?: string }) {
  return (
    <>
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-surface text-textPrimary">
        <Icon name={notificationIcon(n.type)} size="iconS" />
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-s">
          <span className={`text-bodyMedium text-textPrimary ${n.read ? '' : 'font-semibold'}`}>
            {n.title}
          </span>
          {/* Unread is said in words, not only in weight and colour. */}
          {!n.read ? (
            <span role="img" aria-label="Non lu" className="h-2 w-2 shrink-0 rounded-pill bg-primary" />
          ) : null}
        </span>
        {salonName ? (
          <span className="mt-xs block text-bodySmall font-medium text-textSecondary">
            {salonName}
          </span>
        ) : null}
        <span className="mt-xs block text-bodyMedium text-textSecondary">{n.body}</span>
        <span className="mt-xs block text-bodySmall text-textTertiary">
          {formatDateTimeFr(n.createdAt)}
        </span>
      </span>
    </>
  );
}
