'use client';

import Link from 'next/link';
import { EmptyState } from '../EmptyState';
import { ErrorState } from '../ErrorState';
import { useRouter } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import {
  type Appointment,
  type Tab,
  TABS,
  filterByTab,
  salonStoppedMessageFor,
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
import { loadFailure, loadFailureMessage, type LoadFailure } from '../../lib/api/load-failure';
import { NO_CONNECTION_MESSAGE, writeFailureMessage } from '../../lib/api/network';
import type { Provider } from '../../lib/api/providers';
import { updateContactPhone } from '../../lib/auth/client';
import { useFieldErrors } from '../../lib/forms/useFieldErrors';
import { PHONE_INVALID, normalizePhone, phoneFieldError } from '../../lib/phone';
import { SUPPORT } from '../../lib/support';
import { Button } from '../Button';
import { SkeletonRows } from '../Skeleton';
import { TextField } from '../TextField';
import { OpenInAppButton } from '../OpenInAppButton';
import { PhoneField } from '../PhoneField';
import { ProviderCard } from '../provider/ProviderCard';
import { AppointmentCard } from './AppointmentCard';
import { Tabs } from '../Tabs';

const PROVIDER_LABELS: Record<string, string> = {
  google: 'Connecté via Google',
  apple: 'Connecté via Apple',
  email: 'Connecté via e-mail',
  phone: 'Connecté via téléphone',
};

/// The contact phone's check — the shared rule, required (an empty number is
/// not a contact). A module constant: useFieldErrors keys its callbacks on
/// this object's identity.
const CONTACT_PHONE_CHECK = {
  phone: (v: string) => phoneFieldError(v, { required: true }),
};

export function AccountClient() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [items, setItems] = useState<Appointment[]>([]);
  const [favorites, setFavorites] = useState<Provider[]>([]);
  // The favorites read failed: the section says so — never « Aucun favori »
  // to someone who has some (docs/design/web-consumer-network-failure.md §3.2).
  const [favoritesFailed, setFavoritesFailed] = useState<LoadFailure | false>(false);
  // « Retirer des favoris » in flight: those cards are HIDDEN, not dropped —
  // `favorites` loses one only on a success, so a failure brings back that
  // card at its place (docs/design/web-consumer-optimistic-revert.md §3.2 ①).
  const [removing, setRemoving] = useState<ReadonlySet<string>>(new Set());
  // A failed removal's sentence, under its card.
  const [favErrors, setFavErrors] = useState<Record<string, string | undefined>>({});
  const [favRefocus, setFavRefocus] = useState<{ id: string } | null>(null);
  const removeButtons = useRef(new Map<string, HTMLButtonElement>());
  const [tab, setTab] = useState<Tab>('upcoming');
  const [loading, setLoading] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);
  const [error, setError] = useState(false);
  const [logoutBusy, setLogoutBusy] = useState(false);
  const [logoutError, setLogoutError] = useState<string | null>(null);
  const logoutRef = useRef<HTMLButtonElement>(null);
  // Contact-phone edit (auth overhaul: phone is contact data, not the login).
  const [editingPhone, setEditingPhone] = useState(false);
  const [editingName, setEditingName] = useState(false);
  const [nameDraft, setNameDraft] = useState('');
  const [nameBusy, setNameBusy] = useState(false);
  const [nameError, setNameError] = useState<string | null>(null);
  const nameOkRef = useRef<HTMLButtonElement>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteText, setDeleteText] = useState('');
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [phoneDraft, setPhoneDraft] = useState('');
  const [phoneBusy, setPhoneBusy] = useState(false);
  // The number's failure line: « Pas de connexion » when nothing answered,
  // like the name beside it (docs/design/app-failure-messages.md §2.2).
  const [phoneError, setPhoneError] = useState<string | null>(null);
  // The draft's fault answers UNDER the field, on submit (§14 rules 1/2/5 —
  // docs/design/phone-leftovers.md §4); « Enregistrer » used to grey out on
  // bare `isPossiblePhoneNumber`, with no word.
  const phoneFields = useFieldErrors(CONTACT_PHONE_CHECK);

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
      // Why, when it failed: no answer is « Pas de connexion »
      // (docs/design/app-failure-messages.md §2.2).
      setFavoritesFailed(f.status === 200 ? false : loadFailure(f.status));
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router, reloadKey]);

  /// Optimistic, and undone on a failure (§3.2 ①): the card hides at once and
  /// leaves `favorites` only once the server agreed. Undo is this ONE card at
  /// its own place — never a snapshot laid over another removal that worked
  /// (SYSTEM §15).
  async function removeFav(id: string) {
    setRemoving((cur) => new Set(cur).add(id));
    const r = await removeFavorite(id);
    setRemoving((cur) => {
      const next = new Set(cur);
      next.delete(id);
      return next;
    });
    if (r.ok) {
      setFavorites((f) => f.filter((x) => x.id !== id));
      return;
    }
    setFavErrors((e) => ({ ...e, [id]: writeFailureMessage(r.status) }));
    setFavRefocus({ id });
  }

  // The card was unmounted while its removal was out, and focus went with
  // it: back on that card's « Retirer des favoris » — never stolen from
  // elsewhere.
  useEffect(() => {
    if (!favRefocus) return;
    const active = document.activeElement;
    if (!active || active === document.body) {
      removeButtons.current.get(favRefocus.id)?.focus();
    }
  }, [favRefocus]);

  // « OK » was disabled while the name was out, which can drop focus to
  // <body>: back on it with the failure, never stolen from elsewhere.
  useEffect(() => {
    if (!nameError) return;
    const active = document.activeElement;
    if (!active || active === document.body) nameOkRef.current?.focus();
  }, [nameError]);

  // The button was disabled while the call was out, which can drop focus to
  // <body>: put it back on the retry, never steal it from elsewhere.
  useEffect(() => {
    if (!logoutError) return;
    const active = document.activeElement;
    if (!active || active === document.body) logoutRef.current?.focus();
  }, [logoutError]);

  /// The session is httpOnly cookies only the logout RESPONSE can clear: the
  /// page goes only once it came back OK (`ProLogoutButton`'s rule). A failed
  /// call stays, says so and gives the button back — a signed-out-looking
  /// home over a live session is the next person's way into this account.
  async function onLogout() {
    setLogoutBusy(true);
    setLogoutError(null);
    const outcome = await logout();
    if (outcome === 'ok') {
      // Busy until the page goes: home replaces this one.
      router.replace('/');
      return;
    }
    setLogoutError(
      outcome === 'offline'
        ? NO_CONNECTION_MESSAGE
        : 'Une erreur est survenue. Réessayez.',
    );
    setLogoutBusy(false);
  }

  async function savePhone() {
    // The last save's failure line goes first: a save stopped at the field
    // below must not keep it under the new fault.
    setPhoneError(null);
    if (!phoneFields.validate({ phone: phoneDraft })) return;
    // What is checked is what crosses.
    const phone = normalizePhone(phoneDraft);
    setPhoneBusy(true);
    const r = await updateContactPhone(phone);
    setPhoneBusy(false);
    if (!r.ok) {
      // The server's own verdict on the number belongs to the field too.
      if (r.error === 'invalid_phone') phoneFields.set('phone', PHONE_INVALID);
      else setPhoneError(writeFailureMessage(r.status, 'L’enregistrement a échoué. Réessayez.'));
      return;
    }
    setMe((m) => (m ? { ...m, phoneNumber: phone, phoneVerified: false } : m));
    setEditingPhone(false);
  }

  if (loading) return <SkeletonRows count={4} className="mt-l" />;
  if (error) {
    return (
      <ErrorState
        onRetry={() => { setError(false); setLoading(true); setReloadKey((k) => k + 1); }}
      />
    );
  }

  async function saveName() {
    setNameError(null);
    setNameBusy(true);
    const r = await updateName(nameDraft.trim());
    setNameBusy(false);
    if (!r.ok) {
      // The phone row's sentence, in the same card (§3.1).
      setNameError(
        writeFailureMessage(r.status, 'L’enregistrement a échoué. Réessayez.'),
      );
      return;
    }
    setMe((m) => (m ? { ...m, name: nameDraft.trim() } : m));
    setEditingName(false);
  }

  /// Parity 11.1 — the app's flow: type SUPPRIMER, definitive delete; the
  /// session ends and the CRM identity is anonymized server-side (T48).
  async function onDelete() {
    setDeleteBusy(true);
    setDeleteError(null);
    const r = await deleteAccount();
    setDeleteBusy(false);
    if (!r.ok) {
      setDeleteError(
        r.error === 'future_bookings'
          ? 'Annulez vos rendez-vous à venir avant de supprimer votre compte.'
          : 'La suppression a échoué. Réessayez.',
      );
      return;
    }
    router.replace('/');
  }

  const shown = filterByTab(items, tab);
  const shownFavorites = favorites.filter((f) => !removing.has(f.id));

  return (
    <div>
      <section className="rounded-xl border border-border bg-secondary p-m">
        {/* B11: both identity rows in this section are `justify-between` with a
            value on the left and « Modifier » on the right, and neither could
            wrap or had ANY gap — so at 320 the phone row measured 262 of 254
            and the two items could touch at any width. `gap-s` is also
            SYSTEM.md §13.2's ≥8px adjacency floor, which a bare
            `justify-between` never guaranteed. This row is the latent twin: it
            did not fire, because the seeded name is shorter than the phone. */}
        <div className="flex flex-wrap items-center justify-between gap-s">
          <div>
            {editingName ? (
              <>
                <div className="flex flex-wrap items-center gap-s">
                  <TextField
                    label="Nom"
                    hideLabel
                    value={nameDraft}
                    onChange={(e) => setNameDraft(e.target.value)}
                  />
                  <Button
                    ref={nameOkRef}
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
                {nameError ? (
                  <p role="alert" className="mt-xs text-bodyMedium text-error">
                    {nameError}
                  </p>
                ) : null}
              </>
            ) : (
              <p className="flex items-center gap-s font-medium text-textPrimary">
                {me?.name ?? 'Mon compte'}
                <button
                  type="button"
                  aria-label="Modifier le nom"
                  className="text-bodyMedium font-normal text-textTertiary underline"
                  onClick={() => {
                    setNameDraft(me?.name ?? '');
                    setNameError(null);
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
          <div>
            <Button
              ref={logoutRef}
              variant="secondary"
              isLoading={logoutBusy}
              onClick={onLogout}
            >
              Se déconnecter
            </Button>
            {logoutError ? (
              <p role="alert" className="mt-xs text-bodySmall text-error">
                {logoutError}
              </p>
            ) : null}
          </div>
        </div>
        <div className="mt-m border-t border-divider pt-m">
          {editingPhone ? (
            <div className="flex flex-col gap-s">
              <p className="text-bodyMedium text-textSecondary">
                Numéro pour que le salon vous contacte :
              </p>
              <PhoneField
                onChange={(v) => {
                  setPhoneDraft(v);
                  phoneFields.revalidate('phone', v);
                }}
                initialValue={me?.phoneNumber ?? undefined}
                error={phoneFields.errors.phone}
              />
              <div className="flex gap-s">
                <Button disabled={phoneBusy} onClick={savePhone}>
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
                <p role="alert" className="text-bodyMedium text-error">
                  {phoneError}
                </p>
              ) : null}
            </div>
          ) : (
            <div className="flex flex-wrap items-center justify-between gap-s">
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
                  // A fault from an abandoned edit is about a draft that is gone.
                  phoneFields.clear();
                  setPhoneError(null);
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

      <Tabs
        label="Filtrer mes rendez-vous"
        className="mt-l"
        value={tab}
        onChange={setTab}
        items={TABS}
      />

      <div className="mt-m space-y-s">
        {shown.length === 0 ? (
          <EmptyState
            icon="event"
            title="Aucun rendez-vous"
            description="Vos réservations apparaîtront ici."
            action={
              <Link href="/" className="text-bodyMedium text-textPrimary underline">
                Découvrir des salons
              </Link>
            }
          />
        ) : (
          shown.map((a) => <AppointmentCard key={a.id} appt={a} />)
        )}
      </div>

      <section className="mt-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">Favoris</h2>
        {favoritesFailed ? (
          <ErrorState
            className="mt-s"
            message={loadFailureMessage(favoritesFailed, 'Favoris indisponibles.')}
            onRetry={() => { setLoading(true); setReloadKey((k) => k + 1); }}
          />
        ) : shownFavorites.length === 0 ? (
          <EmptyState
            className="mt-s"
            icon="search"
            title="Aucun favori"
            description="Ajoutez vos salons préférés avec le ♥ pour les retrouver ici."
            action={
              <Link href="/" className="text-bodyMedium text-textPrimary underline">
                Découvrir des salons
              </Link>
            }
          />
        ) : (
          <div className="mt-m grid grid-cols-1 gap-m sm:grid-cols-2 lg:grid-cols-3">
            {shownFavorites.map((f) => {
              // A salon that stopped is MARKED, not dropped. This list used to
              // be hydrated by fetching each favorite from the PUBLIC route
              // and filtering the failures away, so a stopped salon silently
              // left the list — and if it was the only one, the page said
              // « Aucun favori » to someone who had one. « Retirer des
              // favoris » stays: it is the one action that still helps.
              const stopped = salonStoppedMessageFor(f.status);
              return (
                <div key={f.id}>
                  <ProviderCard provider={f} />
                  {stopped ? (
                    <p className="mt-xs text-bodySmall text-textSecondary">
                      {stopped}
                    </p>
                  ) : null}
                  <button
                    ref={(el) => {
                      if (el) removeButtons.current.set(f.id, el);
                      else removeButtons.current.delete(f.id);
                    }}
                    type="button"
                    onClick={() => removeFav(f.id)}
                    className="mt-xs text-bodyMedium text-textTertiary underline"
                  >
                    Retirer des favoris
                  </button>
                  {favErrors[f.id] ? (
                    <p role="alert" className="mt-xs text-bodyMedium text-error">
                      {favErrors[f.id]}
                    </p>
                  ) : null}
                </div>
              );
            })}
          </div>
        )}
      </section>

      {/* Notifications (parity 5.1/5.2) */}
      <Link
        href="/mon-compte/notifications"
        className="mt-l flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-bodyLarge text-textPrimary hover:bg-surfaceVariant"
      >
        <span>Notifications</span>
        <span className="text-textTertiary">›</span>
      </Link>

      {/* Aide & Support (parity 15.2).
          It used to render ONLY when a WhatsApp number existed — and the number
          is unset in every build, so this row has never once appeared, while
          three legal documents name it as the contact of record. It now points
          at /support, which always carries an address. */}
      <Link
        href={SUPPORT.path}
        className="mt-s flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-bodyLarge text-textPrimary hover:bg-surfaceVariant"
      >
        <span>Aide &amp; Support</span>
        <span className="text-textTertiary">›</span>
      </Link>

      {/* Confidentialité (parity 11.1/11.2 — AUTH-004/005 on web) */}
      <section className="mt-l rounded-xl border border-border bg-secondary p-m">
        <h2 className="text-titleLarge font-semibold text-textPrimary">
          Confidentialité
        </h2>
        <div className="mt-s flex items-center justify-between gap-m">
          <p className="text-bodyLarge text-textSecondary">
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
              <p className="text-bodyLarge text-textPrimary">
                Cette action est définitive. Votre profil, vos favoris et vos
                notifications sont supprimés ; vos rendez-vous et vos avis
                restent chez le salon, sans votre nom. Pensez à exporter vos
                données avant.
              </p>
              <p className="mt-s text-bodySmall text-textTertiary">
                Tapez SUPPRIMER pour confirmer
              </p>
              <div className="mt-xs flex flex-wrap items-center gap-s">
                <TextField
                  label="Confirmation de suppression"
                  hideLabel
                  value={deleteText}
                  onChange={(e) => setDeleteText(e.target.value)}
                  placeholder="SUPPRIMER"
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
                <p role="alert" className="mt-s text-bodyMedium text-error">
                  {deleteError}
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
