'use client';

import Link from 'next/link';
import { EmptyState } from '../EmptyState';
import { ErrorState } from '../ErrorState';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { ICON_PATHS, Icon, type IconName } from '../Icon';
import {
  type AppNotification,
  type NotificationPrefs,
  unreadCount,
  webRouteFor,
} from '../../lib/account/notifications';
import {
  getNotificationPrefs,
  getNotifications,
  markAllNotificationsRead,
  markNotificationRead,
  updateNotificationPrefs,
} from '../../lib/api/account';
import { writeFailureMessage } from '../../lib/api/network';
import { formatDateTimeFr } from '../../lib/format';
import { Button } from '../Button';
import { SkeletonRows } from '../Skeleton';

/// Notification glyphs (Material outline paths), one per contract type.

const PREF_ROWS: {
  key: keyof NotificationPrefs;
  title: string;
  subtitle: string;
}[] = [
  {
    key: 'reminders',
    title: 'Rappels de rendez-vous',
    subtitle: 'Rappels 24 h et 2 h avant vos rendez-vous.',
  },
  {
    key: 'marketing',
    title: 'Offres & promotions',
    subtitle: 'Offres, nouveautés et relances.',
  },
  {
    key: 'push',
    title: 'Notifications push',
    subtitle: 'Notifications push sur vos appareils mobiles.',
  },
];

/// Per-type glyph — the registry names match the API types; the generic
/// fallback is the bell (the pre-B6 private TYPE_PATHS, now in <Icon>).
function typeIcon(type: string): IconName {
  return type in ICON_PATHS && type !== 'bell'
    ? (type as IconName)
    : 'bell';
}

export function NotificationsClient() {
  const router = useRouter();
  const [items, setItems] = useState<AppNotification[]>([]);
  const [prefs, setPrefs] = useState<NotificationPrefs | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [prefError, setPrefError] = useState(false);
  // A « marquer comme lu » the server refused: under that notification, or
  // under the header for « Tout lire » (docs/design/web-consumer-optimistic-revert.md §3.2 ②③).
  // `at` is the notification's id, or 'all' for « Tout lire ».
  const [readError, setReadError] = useState<{
    at: string;
    message: string;
  } | null>(null);
  const readAllRef = useRef<HTMLButtonElement>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(false);
    const [feed, p] = await Promise.all([
      getNotifications(),
      getNotificationPrefs(),
    ]);
    if (feed.status === 401) {
      router.replace('/connexion?returnTo=/mon-compte/notifications');
      return;
    }
    if (feed.status !== 200) {
      setError(true);
      setLoading(false);
      return;
    }
    setItems(feed.items);
    if (p.status === 200 && p.prefs) setPrefs(p.prefs);
    setLoading(false);
  }, [router]);

  useEffect(() => {
    load();
  }, [load]);

  // « Tout lire » unmounts itself while it is out, and focus goes with it:
  // back on the button with the failure — never stolen from elsewhere.
  useEffect(() => {
    if (readError?.at !== 'all') return;
    const active = document.activeElement;
    if (!active || active === document.body) readAllRef.current?.focus();
  }, [readError]);

  function setRead(ids: ReadonlySet<string>, read: boolean) {
    setItems((cur) => cur.map((x) => (ids.has(x.id) ? { ...x, read } : x)));
  }

  /// Read at once; the navigation never waits for the write. If the page is
  /// still here when the server refuses, this one notification is unread
  /// again and says why; if it has gone, the feed shows it unread on return —
  /// which is true.
  function open(n: AppNotification) {
    if (!n.read) {
      const one = new Set([n.id]);
      setReadError(null);
      setRead(one, true);
      void markNotificationRead(n.id).then((r) => {
        if (r.ok) return;
        setRead(one, false);
        setReadError({ at: n.id, message: writeFailureMessage(r.status) });
      });
    }
    const href = webRouteFor(n.route);
    if (href) router.push(href);
  }

  /// On a failure, only what THIS gesture marked goes back to unread — one
  /// read before it, or on its own meanwhile, stays read (SYSTEM §15: undo
  /// is never a snapshot).
  async function readAll() {
    const marked = new Set(items.filter((x) => !x.read).map((x) => x.id));
    setReadError(null);
    setRead(marked, true);
    const r = await markAllNotificationsRead();
    if (r.ok) return;
    setRead(marked, false);
    setReadError({ at: 'all', message: writeFailureMessage(r.status) });
  }

  async function toggle(key: keyof NotificationPrefs) {
    if (!prefs) return;
    const next = { ...prefs, [key]: !prefs[key] };
    setPrefs(next);
    setPrefError(false);
    const r = await updateNotificationPrefs({ [key]: next[key] });
    if (!r.ok) {
      setPrefs(prefs); // revert
      setPrefError(true);
    } else if (r.prefs) {
      setPrefs(r.prefs);
    }
  }

  if (loading) return <SkeletonRows count={5} className="mt-l" />;
  if (error) {
    return (
      <div>
        <ErrorState title="Notifications" message="Chargement impossible." onRetry={load} />
      </div>
    );
  }

  const unread = unreadCount(items);

  return (
    <div className="max-w-2xl">
      <Link href="/mon-compte" className="text-bodyMedium text-textTertiary">
        ← Mon compte
      </Link>
      {/* B11: a heading beside a French button label, with nothing
          allowed to wrap. Six sibling toolbars in this product already
          wrap; these four did not. Latent at 320 with the seeded copy —
          fixed anyway, because B9 shipped five identical tab strips of
          which only one was live and the other four were one string
          away. */}
      <div className="mt-s flex flex-wrap items-center justify-between gap-m">
        <h1 className="text-headlineSmall font-semibold text-textPrimary">
          Notifications
        </h1>
        {unread > 0 ? (
          <Button ref={readAllRef} variant="secondary" onClick={readAll}>
            Tout lire
          </Button>
        ) : null}
      </div>
      {readError?.at === 'all' ? (
        <p role="alert" className="mt-s text-bodyMedium text-error">
          {readError.message}
        </p>
      ) : null}

      {items.length === 0 ? (
        <EmptyState
          className="mt-l"
          icon="bell"
          title="Aucune notification"
          description="Vos confirmations de rendez-vous et nouveautés apparaîtront ici."
        />
      ) : (
        <ul className="mt-l space-y-s">
          {items.map((n) => (
            <li key={n.id}>
              <button
                type="button"
                onClick={() => open(n)}
                className="flex w-full items-start gap-m rounded-xl border border-border bg-secondary p-m text-left hover:bg-surfaceVariant"
              >
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-surface text-textPrimary">
                  <Icon name={typeIcon(n.type)} size="iconS" />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="flex items-center gap-s">
                    <span
                      className={`text-bodyMedium text-textPrimary ${
                        n.read ? '' : 'font-semibold'
                      }`}
                    >
                      {n.title}
                    </span>
                    {!n.read ? (
                      <span
                        className="h-2 w-2 shrink-0 rounded-pill bg-primary"
                        aria-label="Non lu"
                      />
                    ) : null}
                  </span>
                  <span className="mt-xs block text-bodyMedium text-textSecondary">
                    {n.body}
                  </span>
                  <span className="mt-xs block text-bodySmall text-textTertiary">
                    {formatDateTimeFr(n.createdAt)}
                  </span>
                </span>
              </button>
              {readError?.at === n.id ? (
                <p role="alert" className="mt-xs text-bodyMedium text-error">
                  {readError.message}
                </p>
              ) : null}
            </li>
          ))}
        </ul>
      )}

      {/* Préférences (parity 5.2) — the app's three opt-out toggles. */}
      <h2 className="mt-xl text-titleLarge font-semibold text-textPrimary">
        Préférences
      </h2>
      {prefs ? (
        <div className="mt-m rounded-xl border border-border bg-secondary">
          {PREF_ROWS.map((row, i) => (
            <div
              key={row.key}
              className={`flex items-center justify-between gap-m p-m ${
                i > 0 ? 'border-t border-divider' : ''
              }`}
            >
              <div>
                <p
                  id={`pref-${row.key}-title`}
                  className="text-bodyLarge text-textPrimary"
                >
                  {row.title}
                </p>
                <p className="mt-xs text-bodySmall text-textTertiary">
                  {row.subtitle}
                </p>
              </div>
              {/* §13.2: the BUTTON is the ≥48px target; the 44×24 track is the
                  visible inner span, unmoved. Named by the row title (a real
                  element, not a duplicated string). */}
              <button
                type="button"
                role="switch"
                aria-checked={prefs[row.key]}
                aria-labelledby={`pref-${row.key}-title`}
                onClick={() => toggle(row.key)}
                className="flex min-h-12 min-w-12 shrink-0 items-center justify-center"
              >
                <span
                  className={`relative block h-6 w-11 rounded-pill transition-colors ${
                    prefs[row.key] ? 'bg-primary' : 'bg-border'
                  }`}
                >
                  <span
                    // ds-ignore: the knob's travel is exact geometry, not spacing — and B11 had to
                    // fix the ARITHMETIC, not just the unit. It read "track w-11 (44) − knob w-5 (20)
                    // − left-0.5 (2) = 22" and wrote `left-[22px]`, but all three of those operands
                    // are REM (`tailwind.config.ts` sources the sizing keys from Tailwind's default
                    // scale). The sum is only 22px at a 16px root; at Chrome's "Very large" (24px)
                    // the correct travel is 33 and the knob stopped a third of the way across a
                    // track that had grown around it. In rem the identity holds at every root:
                    // 2.75 − 1.25 − 0.125 = 1.375rem. (The switch stays hand-rolled — §10 specs no
                    // Switch primitive; B4 fixed its target + label in place.)
                    // eslint-disable-next-line tailwindcss/no-arbitrary-value
                    className={`absolute top-0.5 h-5 w-5 rounded-pill bg-secondary shadow transition-all ${
                      prefs[row.key] ? 'left-[1.375rem]' : 'left-0.5'
                    }`}
                  />
                </span>
              </button>
            </div>
          ))}
        </div>
      ) : (
        <ErrorState
          message="Préférences indisponibles."
          onRetry={load}
        />
      )}
      {prefError ? (
        <p role="alert" className="mt-s text-bodyMedium text-error">
          Impossible d’enregistrer. Réessayez.
        </p>
      ) : null}
      <p className="mt-s text-bodySmall text-textTertiary">
        Les confirmations et changements de rendez-vous sont toujours envoyés.
      </p>
    </div>
  );
}
