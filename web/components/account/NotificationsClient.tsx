'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
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
import { formatDateTimeFr } from '../../lib/format';
import { Button } from '../Button';

/// Notification glyphs (Material outline paths), one per contract type.
const TYPE_PATHS: Record<string, string> = {
  bookingConfirmed:
    'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm-1.2 14.4L6.4 12l1.4-1.4 3 3 5.4-5.4 1.4 1.4-6.8 6.8z',
  depositReceived:
    'M21 7H5a1 1 0 0 1 0-2h14V3H5a3 3 0 0 0-3 3v12a3 3 0 0 0 3 3h16a1 1 0 0 0 1-1V8a1 1 0 0 0-1-1zm-4 7a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3z',
  reminder:
    'M12 22a9 9 0 1 1 0-18 9 9 0 0 1 0 18zm.5-13.5h-1.5V14l4 2.4.75-1.23-3.25-1.92V8.5zM5 2 1.5 5l1.3 1.3L6.3 3.3 5 2zm14 0-1.3 1.3 3.5 3L22.5 5 19 2z',
  reschedule:
    'M12 6V3L8 7l4 4V8a4 4 0 0 1 3.9 4.9l1.5 1.1A6 6 0 0 0 12 6zm0 10a4 4 0 0 1-3.9-4.9L6.6 10A6 6 0 0 0 12 18v3l4-4-4-4v3z',
  cancellation:
    'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm4.3 12.9-1.4 1.4L12 13.4l-2.9 2.9-1.4-1.4 2.9-2.9-2.9-2.9 1.4-1.4 2.9 2.9 2.9-2.9 1.4 1.4-2.9 2.9 2.9 2.9z',
  reviewRequest:
    'M12 17.3 6.2 21l1.5-6.6L2.5 9.9l6.7-.6L12 3l2.8 6.3 6.7.6-5.2 4.5L17.8 21z',
  general:
    'M12 22a2 2 0 0 0 2-2h-4a2 2 0 0 0 2 2zm6-6v-5a6 6 0 0 0-4.5-5.8V4.5a1.5 1.5 0 0 0-3 0v.7A6 6 0 0 0 6 11v5l-2 2v1h16v-1l-2-2z',
};

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

export function NotificationsClient() {
  const router = useRouter();
  const [items, setItems] = useState<AppNotification[]>([]);
  const [prefs, setPrefs] = useState<NotificationPrefs | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [prefError, setPrefError] = useState(false);

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

  async function open(n: AppNotification) {
    if (!n.read) {
      setItems((cur) =>
        cur.map((x) => (x.id === n.id ? { ...x, read: true } : x)),
      );
      markNotificationRead(n.id);
    }
    const href = webRouteFor(n.route);
    if (href) router.push(href);
  }

  async function readAll() {
    setItems((cur) => cur.map((x) => ({ ...x, read: true })));
    await markAllNotificationsRead();
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

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (error) {
    return (
      <div>
        <p className="text-error">Chargement impossible.</p>
        <div className="mt-s">
          <Button variant="secondary" onClick={load}>
            Réessayer
          </Button>
        </div>
      </div>
    );
  }

  const unread = unreadCount(items);

  return (
    <div className="max-w-2xl">
      <Link href="/mon-compte" className="text-bodyMedium text-textTertiary">
        ← Mon compte
      </Link>
      <div className="mt-s flex items-center justify-between gap-m">
        <h1 className="text-headlineSmall font-semibold text-textPrimary">
          Notifications
        </h1>
        {unread > 0 ? (
          <Button variant="secondary" onClick={readAll}>
            Tout lire
          </Button>
        ) : null}
      </div>

      {items.length === 0 ? (
        <div className="mt-l rounded-xl border border-border bg-secondary p-l text-center">
          <p className="font-medium text-textPrimary">Aucune notification</p>
          <p className="mt-xs text-bodyMedium text-textSecondary">
            Vos confirmations de rendez-vous et nouveautés apparaîtront ici.
          </p>
        </div>
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
                  <svg
                    viewBox="0 0 24 24"
                    className="h-5 w-5"
                    fill="currentColor"
                    aria-hidden
                  >
                    <path d={TYPE_PATHS[n.type] ?? TYPE_PATHS.general} />
                  </svg>
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
                  className="text-bodyMedium text-textPrimary"
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
                    // ds-ignore: the knob's travel is exact geometry, not spacing: track w-11 (44) − knob
                    // w-5 (20) − left-0.5 (2) = 22. Any token snap misplaces it. (The switch stays
                    // hand-rolled — §10 specs no Switch primitive; B4 fixed its target + label in place.)
                    // eslint-disable-next-line tailwindcss/no-arbitrary-value
                    className={`absolute top-0.5 h-5 w-5 rounded-pill bg-secondary shadow transition-all ${
                      prefs[row.key] ? 'left-[22px]' : 'left-0.5'
                    }`}
                  />
                </span>
              </button>
            </div>
          ))}
        </div>
      ) : (
        <p className="mt-m text-bodyMedium text-textSecondary">
          Préférences indisponibles. Rechargez la page.
        </p>
      )}
      {prefError ? (
        <p className="mt-s text-bodyMedium text-error">
          Impossible d’enregistrer. Réessayez.
        </p>
      ) : null}
      <p className="mt-s text-bodySmall text-textTertiary">
        Les confirmations et changements de rendez-vous sont toujours envoyés.
      </p>
    </div>
  );
}
