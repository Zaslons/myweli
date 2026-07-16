'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { statusLabelFr } from '../../lib/account/appointments';
import {
  type ProProfile,
  addClientNote,
  deleteClientNote,
  getClientCard,
  getClientVisits,
  getMyProvider,
  updateClientTags,
} from '../../lib/api/pro';
import { formatDateFr, formatDateTimeFr, formatFcfa } from '../../lib/format';
import type { ProAppointment } from '../../lib/pro/today';
import {
  MAX_NOTE_LENGTH,
  PRESET_TAGS,
  type SalonClientCard,
  telHref,
  toggleTag,
  waHref,
} from '../../lib/pro/clients';
import { Button } from '../Button';
import { TextField } from '../TextField';
import { ManualBookingDialog } from './ManualBookingDialog';

/// Module `clients` C1b — the client card at /pro/clients/[id]
/// (docs/design/clients-c1.md §6): identity + notes on the left, stats +
/// salon-scoped history on the right. « Nouveau rendez-vous » opens the
/// manual-booking dialog pre-picked with this client
/// (docs/design/web-manual-booking.md — the C1b deferral closed).
export function ClientCardClient({ clientId }: { clientId: string }) {
  const router = useRouter();
  const [providerId, setProviderId] = useState<string | null>(null);
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [booking, setBooking] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [card, setCard] = useState<SalonClientCard | null>(null);
  const [visits, setVisits] = useState<ProAppointment[]>([]);
  const [visitsTotal, setVisitsTotal] = useState(0);
  const [visitsPage, setVisitsPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [error, setError] = useState(false);
  const [noteDraft, setNoteDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [editingTags, setEditingTags] = useState(false);
  const [customTag, setCustomTag] = useState('');

  const load = useCallback(async () => {
    const me = await getMyProvider();
    if (me.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    if (me.status !== 200 || !me.profile) {
      setError(true);
      setLoading(false);
      return;
    }
    const pid = me.profile.provider.id;
    setProviderId(pid);
    setProfile(me.profile);
    const r = await getClientCard(pid, clientId);
    if (r.status === 404) {
      setNotFound(true);
      setLoading(false);
      return;
    }
    if (r.status !== 200 || !r.card) {
      setError(true);
      setLoading(false);
      return;
    }
    setCard(r.card);
    const v = await getClientVisits(pid, clientId, 1);
    setVisits(v.items);
    setVisitsTotal(v.total);
    setVisitsPage(1);
    setLoading(false);
  }, [router, clientId]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 2500);
    return () => clearTimeout(t);
  }, [toast]);

  // The ACTIVE salon's market (multi-pays MP3).
  const tz = profile?.provider.timezone ?? undefined;
  const currency = profile?.provider.currency ?? undefined;

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (notFound) {
    return (
      <div>
        <Link href="/pro/clients" className="text-bodyMedium text-textTertiary">
          ← Clients
        </Link>
        <p className="mt-m text-textSecondary">Client introuvable.</p>
      </div>
    );
  }
  if (error || !card || !providerId) {
    return <p className="text-error">Une erreur est survenue. Réessayez.</p>;
  }

  async function saveTags(next: string[]) {
    setBusy(true);
    const r = await updateClientTags(providerId!, clientId, next);
    setBusy(false);
    if (r.ok) setCard((c) => (c ? { ...c, tags: next } : c));
  }

  async function submitNote() {
    const body = noteDraft.trim();
    if (!body) return;
    setBusy(true);
    const r = await addClientNote(providerId!, clientId, body);
    setBusy(false);
    if (r.ok && r.note) {
      setCard((c) => (c ? { ...c, notes: [r.note!, ...c.notes] } : c));
      setNoteDraft('');
    }
  }

  async function removeNote(noteId: string) {
    setBusy(true);
    const r = await deleteClientNote(providerId!, clientId, noteId);
    setBusy(false);
    if (r.ok) {
      setCard((c) =>
        c ? { ...c, notes: c.notes.filter((n) => n.id !== noteId) } : c,
      );
    }
  }

  async function moreVisits() {
    const v = await getClientVisits(providerId!, clientId, visitsPage + 1);
    setVisits((prev) => [...prev, ...v.items]);
    setVisitsPage(visitsPage + 1);
  }

  const tagChoices = [
    ...PRESET_TAGS,
    ...card.tags.filter((t) => !PRESET_TAGS.includes(t)),
  ];

  return (
    <div>
      <Link href="/pro/clients" className="text-bodyMedium text-textTertiary">
        ← Clients
      </Link>

      <div className="mt-m grid gap-l lg:grid-cols-2">
        {/* Identity + notes */}
        <div>
          <div className="rounded-xl border border-border bg-secondary p-l">
            <div className="flex items-center gap-m">
              <span className="flex h-12 w-12 items-center justify-center rounded-pill bg-surface text-titleLarge font-medium text-textPrimary">
                {card.displayName.slice(0, 1).toUpperCase()}
              </span>
              <div className="min-w-0">
                <h1 className="flex items-center gap-xs text-titleLarge font-semibold text-textPrimary">
                  <span className="truncate">{card.displayName}</span>
                  {card.linked ? (
                    <span
                      className="rounded-pill bg-surface px-xs text-labelSmall uppercase text-textTertiary"
                    >
                      MyWeli
                    </span>
                  ) : null}
                </h1>
                {card.phone ? (
                  <p className="mt-xs flex items-center gap-s text-bodyMedium text-textSecondary">
                    {card.phone}
                    <a
                      href={telHref(card.phone)}
                      className="-my-sm inline-flex min-h-12 items-center underline"
                      aria-label="Appeler"
                    >
                      Appeler
                    </a>
                    <a
                      href={waHref(card.phone)}
                      target="_blank"
                      rel="noreferrer"
                      className="-my-sm inline-flex min-h-12 items-center underline"
                      aria-label="WhatsApp"
                    >
                      WhatsApp
                    </a>
                  </p>
                ) : null}
              </div>
            </div>

            <div className="mt-m">
              <Button onClick={() => setBooking(true)}>
                Nouveau rendez-vous
              </Button>
            </div>

            <div className="mt-m flex flex-wrap items-center gap-s">
              {(editingTags ? tagChoices : card.tags).map((t) => {
                const active = card.tags.includes(t);
                return editingTags ? (
                  <button
                    key={t}
                    type="button"
                    disabled={busy}
                    onClick={() => {
                      const next = toggleTag(card.tags, t);
                      if (next) saveTags(next);
                    }}
                    className={`inline-flex min-h-12 items-center rounded-pill border px-s text-bodySmall ${
                      active
                        ? 'border-primary bg-primary text-secondary'
                        : 'border-border bg-surface text-textSecondary'
                    }`}
                  >
                    {t}
                  </button>
                ) : (
                  <span
                    key={t}
                    className="rounded-pill border border-border px-s py-xs text-bodySmall text-textSecondary"
                  >
                    {t}
                  </span>
                );
              })}
              <button
                type="button"
                onClick={() => setEditingTags((v) => !v)}
                className="inline-flex min-h-12 items-center text-bodySmall text-textTertiary underline"
              >
                {editingTags ? 'Terminé' : 'Modifier les tags'}
              </button>
            </div>
            {/* Audit 4.1: mint a custom tag (the app's free-text field). */}
            {editingTags ? (
              <form
                className="mt-s flex gap-s"
                onSubmit={(e) => {
                  e.preventDefault();
                  const t = customTag.trim();
                  if (!t || card.tags.includes(t)) return;
                  saveTags([...card.tags, t]);
                  setCustomTag('');
                }}
              >
                <TextField
                  label="Nouveau tag"
                  hideLabel
                  value={customTag}
                  onChange={(e) => setCustomTag(e.target.value)}
                  maxLength={30}
                  placeholder="Nouveau tag…"
                />
                <Button variant="secondary" disabled={busy || !customTag.trim()}>
                  Ajouter le tag
                </Button>
              </form>
            ) : null}
          </div>

          <section className="mt-l rounded-xl border border-border bg-secondary p-l">
            <h2 className="font-semibold text-textPrimary">Notes</h2>
            <p className="mt-xs text-bodySmall text-textTertiary">
              Visible uniquement par votre équipe.
            </p>
            <div className="mt-m flex gap-s">
              <TextField
                className="flex-1"
                label="Ajouter une note"
                hideLabel
                multiline
                value={noteDraft}
                onChange={(e) => setNoteDraft(e.target.value)}
                maxLength={MAX_NOTE_LENGTH}
                rows={2}
                placeholder="Ajouter une note…"
              />
              <Button
                onClick={submitNote}
                disabled={busy || !noteDraft.trim()}
              >
                Ajouter
              </Button>
            </div>
            {card.notes.length === 0 ? (
              <p className="mt-m text-bodyMedium text-textSecondary">
                Aucune note pour l’instant.
              </p>
            ) : (
              <ul className="mt-m space-y-s">
                {card.notes.map((n) => (
                  <li
                    key={n.id}
                    className="rounded-lg bg-surface p-s text-bodyMedium text-textPrimary"
                  >
                    <p>{n.body}</p>
                    <p className="mt-xs flex items-center justify-between text-bodySmall text-textTertiary">
                      <span>
                        {n.authorName} · {formatDateFr(n.createdAt, tz)}
                      </span>
                      <button
                        type="button"
                        onClick={() => removeNote(n.id)}
                        disabled={busy}
                        className="-my-m inline-flex min-h-12 items-center underline"
                      >
                        Supprimer
                      </button>
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>

        {/* Stats + history */}
        <div>
          <div className="grid grid-cols-2 gap-s">
            <Stat label="Visites" value={String(card.stats.visits)} />
            <Stat
              label="Dépensé"
              value={formatFcfa(card.stats.spentFcfa, currency)}
            />
            <Stat
              label="Absences"
              value={String(card.stats.noShows)}
              alert={card.stats.noShows >= 2}
            />
            <Stat
              label="Dernière visite"
              value={
                card.lastVisitAt ? formatDateFr(card.lastVisitAt, tz) : '—'
              }
            />
          </div>

          {card.upcoming ? (
            <Link
              href={`/pro/rendez-vous/${card.upcoming.id}`}
              className="mt-l block rounded-xl border border-border bg-secondary p-l hover:bg-surface"
            >
              <p className="text-bodySmall uppercase text-textTertiary">
                Prochain rendez-vous
              </p>
              <p className="mt-xs text-labelLarge font-medium text-textPrimary">
                {formatDateTimeFr(card.upcoming.appointmentDate, tz)} ·{' '}
                {statusLabelFr(card.upcoming.status)}
              </p>
            </Link>
          ) : null}

          <section className="mt-l rounded-xl border border-border bg-secondary p-l">
            <h2 className="font-semibold text-textPrimary">
              Historique des visites
            </h2>
            {visits.length === 0 ? (
              <p className="mt-m text-bodyMedium text-textSecondary">
                Aucune visite enregistrée.
              </p>
            ) : (
              <ul className="mt-m divide-y divide-border">
                {visits.map((v) => (
                  <li
                    key={v.id}
                    className="flex items-center justify-between py-s text-bodyMedium"
                  >
                    <span className="text-textPrimary">
                      {formatDateTimeFr(v.appointmentDate, tz)}
                    </span>
                    <span className="flex items-center gap-s">
                      {typeof v.totalPrice === 'number' ? (
                        <span className="text-textSecondary">
                          {formatFcfa(v.totalPrice, currency)}
                        </span>
                      ) : null}
                      <span className="rounded-pill bg-surface px-s py-xs text-bodySmall text-textSecondary">
                        {statusLabelFr(v.status)}
                      </span>
                    </span>
                  </li>
                ))}
              </ul>
            )}
            {visits.length < visitsTotal ? (
              <div className="mt-m text-center">
                <Button variant="secondary" onClick={moreVisits}>
                  Charger plus
                </Button>
              </div>
            ) : null}
          </section>
        </div>
      </div>

      {booking && profile && providerId ? (
        <ManualBookingDialog
          providerId={providerId}
          profile={profile}
          initialClient={{
            name: card.displayName,
            phone: card.phone ?? undefined,
          }}
          onClose={() => setBooking(false)}
          onCreated={() => {
            setBooking(false);
            setToast('Rendez-vous créé');
            load();
          }}
          onToast={setToast}
        />
      ) : null}
      {toast ? (
        <div className="fixed bottom-l left-1/2 z-toast -translate-x-1/2 rounded-lg bg-primary px-l py-s text-bodyMedium text-secondary shadow-lg">
          {toast}
        </div>
      ) : null}
    </div>
  );
}

function Stat({
  label,
  value,
  alert = false,
}: {
  label: string;
  value: string;
  alert?: boolean;
}) {
  return (
    <div className="rounded-xl border border-border bg-secondary p-m">
      <p className="text-bodySmall uppercase text-textTertiary">{label}</p>
      <p
        className={`mt-xs text-titleLarge font-semibold ${
          alert ? 'text-error' : 'text-textPrimary'
        }`}
      >
        {value}
      </p>
    </div>
  );
}
