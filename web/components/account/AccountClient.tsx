'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import {
  type Appointment,
  type Tab,
  TABS,
  filterByTab,
} from '../../lib/account/appointments';
import {
  type Me,
  getFavorites,
  getMe,
  listAppointments,
  logout,
  removeFavorite,
} from '../../lib/api/account';
import type { Provider } from '../../lib/api/providers';
import { Button } from '../Button';
import { OpenInAppButton } from '../OpenInAppButton';
import { ProviderCard } from '../provider/ProviderCard';
import { AppointmentCard } from './AppointmentCard';

export function AccountClient() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [items, setItems] = useState<Appointment[]>([]);
  const [favorites, setFavorites] = useState<Provider[]>([]);
  const [tab, setTab] = useState<Tab>('upcoming');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    let active = true;
    (async () => {
      const m = await getMe();
      if (m.status === 401) {
        router.replace('/connexion?returnTo=/mon-compte');
        return;
      }
      const a = await listAppointments();
      const f = await getFavorites();
      if (!active) return;
      if (m.status !== 200 || a.status !== 200) {
        setError(true);
        setLoading(false);
        return;
      }
      setMe(m.user ?? null);
      setItems(a.items);
      setFavorites(f.favorites);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router]);

  async function removeFav(id: string) {
    setFavorites((f) => f.filter((x) => x.id !== id));
    await removeFavorite(id);
  }

  async function onLogout() {
    await logout();
    router.replace('/');
  }

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (error) {
    return (
      <p className="text-error">Une erreur est survenue. Réessayez plus tard.</p>
    );
  }

  const shown = filterByTab(items, tab);

  return (
    <div>
      <section className="flex items-center justify-between rounded-xl border border-border bg-secondary p-m">
        <div>
          <p className="font-medium text-textPrimary">
            {me?.name ?? 'Mon compte'}
          </p>
          <p className="text-sm text-textTertiary">{me?.phoneNumber}</p>
        </div>
        <Button variant="secondary" onClick={onLogout}>
          Se déconnecter
        </Button>
      </section>

      <div className="mt-l flex gap-s border-b border-divider">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => setTab(t.key)}
            className={`px-m py-s text-sm ${
              tab === t.key
                ? 'border-b-2 border-primary text-textPrimary'
                : 'text-textTertiary'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="mt-m space-y-s">
        {shown.length === 0 ? (
          <div className="rounded-xl border border-border bg-secondary p-l text-center">
            <p className="text-textSecondary">Aucun rendez-vous.</p>
            <Link
              href="/"
              className="mt-s inline-block text-sm text-textPrimary underline"
            >
              Découvrir des salons
            </Link>
          </div>
        ) : (
          shown.map((a) => <AppointmentCard key={a.id} appt={a} />)
        )}
      </div>

      <section className="mt-l">
        <h2 className="text-lg font-semibold text-textPrimary">Favoris</h2>
        {favorites.length === 0 ? (
          <p className="mt-s text-sm text-textTertiary">
            Aucun favori — explorez les salons.
          </p>
        ) : (
          <div className="mt-m grid grid-cols-1 gap-m sm:grid-cols-2 lg:grid-cols-3">
            {favorites.map((f) => (
              <div key={f.id}>
                <ProviderCard provider={f} />
                <button
                  type="button"
                  onClick={() => removeFav(f.id)}
                  className="mt-xs text-sm text-textTertiary underline"
                >
                  Retirer des favoris
                </button>
              </div>
            ))}
          </div>
        )}
      </section>

      <div className="mt-l">
        <OpenInAppButton />
      </div>
    </div>
  );
}
