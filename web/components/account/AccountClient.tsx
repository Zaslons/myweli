'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { isPossiblePhoneNumber } from 'react-phone-number-input';
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
  deleteAccount,
  logout,
  updateName,
  removeFavorite,
} from '../../lib/api/account';
import type { Provider } from '../../lib/api/providers';
import { updateContactPhone } from '../../lib/auth/client';
import { supportWhatsAppUrl } from '../../lib/support';
import { Button } from '../Button';
import { OpenInAppButton } from '../OpenInAppButton';
import { PhoneField } from '../PhoneField';
import { ProviderCard } from '../provider/ProviderCard';
import { AppointmentCard } from './AppointmentCard';

const PROVIDER_LABELS: Record<string, string> = {
  google: 'Connecté via Google',
  apple: 'Connecté via Apple',
  email: 'Connecté via e-mail',
  phone: 'Connecté via téléphone',
};

export function AccountClient() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [items, setItems] = useState<Appointment[]>([]);
  const [favorites, setFavorites] = useState<Provider[]>([]);
  const [tab, setTab] = useState<Tab>('upcoming');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  // Contact-phone edit (auth overhaul: phone is contact data, not the login).
  const [editingPhone, setEditingPhone] = useState(false);
  const [editingName, setEditingName] = useState(false);
  const [nameDraft, setNameDraft] = useState('');
  const [nameBusy, setNameBusy] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteText, setDeleteText] = useState('');
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [deleteError, setDeleteError] = useState(false);
  const [phoneDraft, setPhoneDraft] = useState('');
  const [phoneBusy, setPhoneBusy] = useState(false);
  const [phoneError, setPhoneError] = useState(false);

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

  async function savePhone() {
    setPhoneBusy(true);
    setPhoneError(false);
    const r = await updateContactPhone(phoneDraft);
    setPhoneBusy(false);
    if (!r.ok) {
      setPhoneError(true);
      return;
    }
    setMe((m) =>
      m ? { ...m, phoneNumber: phoneDraft, phoneVerified: false } : m,
    );
    setEditingPhone(false);
  }

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (error) {
    return (
      <p className="text-error">Une erreur est survenue. Réessayez plus tard.</p>
    );
  }

  async function saveName() {
    setNameBusy(true);
    const r = await updateName(nameDraft.trim());
    setNameBusy(false);
    if (!r.ok) return;
    setMe((m) => (m ? { ...m, name: nameDraft.trim() } : m));
    setEditingName(false);
  }

  /// Parity 11.1 — the app's flow: type SUPPRIMER, definitive delete; the
  /// session ends and the CRM identity is anonymized server-side (T48).
  async function onDelete() {
    setDeleteBusy(true);
    setDeleteError(false);
    const r = await deleteAccount();
    setDeleteBusy(false);
    if (!r.ok) {
      setDeleteError(true);
      return;
    }
    router.replace('/');
  }

  const shown = filterByTab(items, tab);

  return (
    <div>
      <section className="rounded-xl border border-border bg-secondary p-m">
        <div className="flex items-center justify-between">
          <div>
            {editingName ? (
              <div className="flex flex-wrap items-center gap-s">
                <input
                  value={nameDraft}
                  onChange={(e) => setNameDraft(e.target.value)}
                  aria-label="Nom"
                  className="rounded-lg border border-border bg-surface px-s py-xs text-bodyMedium text-textPrimary"
                />
                <Button
                  disabled={nameBusy || !nameDraft.trim()}
                  onClick={saveName}
                >
                  OK
                </Button>
                <button
                  type="button"
                  className="text-bodyMedium text-textTertiary underline"
                  onClick={() => setEditingName(false)}
                >
                  Annuler
                </button>
              </div>
            ) : (
              <p className="flex items-center gap-s font-medium text-textPrimary">
                {me?.name ?? 'Mon compte'}
                <button
                  type="button"
                  aria-label="Modifier le nom"
                  className="text-bodyMedium font-normal text-textTertiary underline"
                  onClick={() => {
                    setNameDraft(me?.name ?? '');
                    setEditingName(true);
                  }}
                >
                  Modifier
                </button>
              </p>
            )}
            {me?.email ? (
              <p className="text-bodyMedium text-textTertiary">{me.email}</p>
            ) : null}
            {me?.authProvider && PROVIDER_LABELS[me.authProvider] ? (
              <p className="text-bodySmall text-textTertiary">
                {PROVIDER_LABELS[me.authProvider]}
              </p>
            ) : null}
          </div>
          <Button variant="secondary" onClick={onLogout}>
            Se déconnecter
          </Button>
        </div>
        <div className="mt-m border-t border-divider pt-m">
          {editingPhone ? (
            <div className="flex flex-col gap-s">
              <p className="text-bodyMedium text-textSecondary">
                Numéro pour que le salon vous contacte :
              </p>
              <PhoneField
                onChange={setPhoneDraft}
                initialValue={me?.phoneNumber ?? undefined}
              />
              <div className="flex gap-s">
                <Button
                  disabled={
                    phoneBusy ||
                    !phoneDraft ||
                    !isPossiblePhoneNumber(phoneDraft)
                  }
                  onClick={savePhone}
                >
                  Enregistrer
                </Button>
                <Button
                  variant="secondary"
                  onClick={() => setEditingPhone(false)}
                >
                  Annuler
                </Button>
              </div>
              {phoneError ? (
                <p className="text-bodyMedium text-error">
                  Numéro invalide. Réessayez.
                </p>
              ) : null}
            </div>
          ) : (
            <div className="flex items-center justify-between">
              <div>
                <p className="text-bodyMedium text-textPrimary">
                  {me?.phoneNumber ?? 'Aucun numéro de contact'}
                </p>
                {me?.phoneNumber && !me.phoneVerified ? (
                  <p className="text-bodySmall text-textTertiary">Non vérifié</p>
                ) : null}
              </div>
              <button
                type="button"
                onClick={() => {
                  setPhoneDraft(me?.phoneNumber ?? '');
                  setEditingPhone(true);
                }}
                className="text-bodyMedium text-textPrimary underline"
              >
                Modifier
              </button>
            </div>
          )}
        </div>
      </section>

      <div className="mt-l flex gap-s border-b border-divider">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => setTab(t.key)}
            className={`px-m py-s text-bodyMedium ${
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
              className="mt-s inline-block text-bodyMedium text-textPrimary underline"
            >
              Découvrir des salons
            </Link>
          </div>
        ) : (
          shown.map((a) => <AppointmentCard key={a.id} appt={a} />)
        )}
      </div>

      <section className="mt-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">Favoris</h2>
        {favorites.length === 0 ? (
          <p className="mt-s text-bodyMedium text-textTertiary">
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
                  className="mt-xs text-bodyMedium text-textTertiary underline"
                >
                  Retirer des favoris
                </button>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Notifications (parity 5.1/5.2) */}
      <Link
        href="/mon-compte/notifications"
        className="mt-l flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-bodyMedium text-textPrimary hover:bg-surfaceVariant"
      >
        <span>Notifications</span>
        <span className="text-textTertiary">›</span>
      </Link>

      {/* Aide & Support (parity 15.2) — manual intake via WhatsApp. */}
      <a
        href={supportWhatsAppUrl()}
        target="_blank"
        rel="noopener noreferrer"
        className="mt-s flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-bodyMedium text-textPrimary hover:bg-surfaceVariant"
      >
        <span>Aide & Support</span>
        <span className="text-textTertiary">›</span>
      </a>

      {/* Confidentialité (parity 11.1/11.2 — AUTH-004/005 on web) */}
      <section className="mt-l rounded-xl border border-border bg-secondary p-m">
        <h2 className="text-titleLarge font-semibold text-textPrimary">
          Confidentialité
        </h2>
        <div className="mt-s flex items-center justify-between gap-m">
          <p className="text-bodyMedium text-textSecondary">
            Recevoir une copie de vos données (profil, rendez-vous, favoris).
          </p>
          <Link
            href="/mon-compte/donnees"
            className="shrink-0 text-bodyMedium text-textPrimary underline"
          >
            Exporter mes données
          </Link>
        </div>
        <div className="mt-m border-t border-divider pt-m">
          {!confirmDelete ? (
            <button
              type="button"
              onClick={() => {
                setConfirmDelete(true);
                setDeleteText('');
              }}
              className="text-bodyMedium text-error underline"
            >
              Supprimer mon compte
            </button>
          ) : (
            <div className="rounded-lg bg-surface p-m">
              <p className="text-bodyMedium text-textPrimary">
                Cette action est définitive. Vos rendez-vous, favoris et avis
                seront supprimés. Pensez à exporter vos données avant.
              </p>
              <p className="mt-s text-bodySmall text-textTertiary">
                Tapez SUPPRIMER pour confirmer
              </p>
              <div className="mt-xs flex flex-wrap items-center gap-s">
                <input
                  value={deleteText}
                  onChange={(e) => setDeleteText(e.target.value)}
                  placeholder="SUPPRIMER"
                  aria-label="Confirmation de suppression"
                  className="rounded-lg border border-border bg-secondary px-s py-xs text-bodyMedium text-textPrimary"
                />
                <Button
                  disabled={
                    deleteBusy ||
                    deleteText.trim().toUpperCase() !== 'SUPPRIMER'
                  }
                  onClick={onDelete}
                >
                  Supprimer définitivement
                </Button>
                <button
                  type="button"
                  className="text-bodyMedium text-textTertiary underline"
                  onClick={() => setConfirmDelete(false)}
                >
                  Annuler
                </button>
              </div>
              {deleteError ? (
                <p className="mt-s text-bodyMedium text-error">
                  La suppression a échoué. Réessayez.
                </p>
              ) : null}
            </div>
          )}
        </div>
      </section>

      <div className="mt-l">
        <OpenInAppButton />
      </div>
    </div>
  );
}
