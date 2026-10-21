'use client';

import Link from 'next/link';
import { Card } from '../Card';
import { Chip, chipLinkClasses } from '../Chip';
import { StatusChip } from '../StatusChip';
import { ErrorState } from '../ErrorState';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { SubmissionKey, writeFailureMessage } from '../../lib/api/network';
import { Toast } from '../Toast';
import { useToast } from '../../lib/useToast';
import { statusLabelFr } from '../../lib/account/appointments';
import {
  type ProProfile,
  addClientNote,
  deleteClientNote,
  getClientCard,
  getClientVisits,
  getMyProvider,
  updateClientPhone,
  updateClientTags,
} from '../../lib/api/pro';
import { loadFailure, loadFailureMessage, type LoadFailure } from '../../lib/api/load-failure';
import { useFieldErrors } from '../../lib/forms/useFieldErrors';
import {
  PHONE_INVALID,
  normalizePhone,
  phoneFieldError,
} from '../../lib/phone';
import {
  deName,
  formatDateFr,
  formatDateTimeFr,
  formatFcfa,
  formatPhoneNumber,
} from '../../lib/format';
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
import { Modal } from '../Modal';
import { PhoneField } from '../PhoneField';
import { SkeletonRows } from '../Skeleton';
import { TextField } from '../TextField';
import { ManualBookingDialog } from './ManualBookingDialog';

/// Module `clients` C1b — the client card at /pro/clients/[id]
/// (docs/design/clients-c1.md §6): identity + notes on the left, stats +
/// salon-scoped history on the right. « Nouveau rendez-vous » opens the
/// manual-booking dialog pre-picked with this client
/// (docs/design/web-manual-booking.md — the C1b deferral closed). A GUEST
/// card's number is edited under it, « Modifier », when the server says so
/// (`phoneEditable`); a card linked to an account keeps the account's number,
/// read-only (docs/design/phone-leftovers.md §8, §11).
export function ClientCardClient({ clientId }: { clientId: string }) {
  const router = useRouter();
  const [providerId, setProviderId] = useState<string | null>(null);
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [booking, setBooking] = useState(false);
  // §8 of docs/design/phone-leftovers.md: a guest card's number, in a Modal.
  const [editingPhone, setEditingPhone] = useState(false);
  const { toast, show } = useToast();
  const [card, setCard] = useState<SalonClientCard | null>(null);
  const [visits, setVisits] = useState<ProAppointment[]>([]);
  const [visitsTotal, setVisitsTotal] = useState(0);
  const [visitsPage, setVisitsPage] = useState(1);
  // The history read failed: it says so — never « Aucune visite » beside a
  // visit count (docs/design/web-pro-truthful-failure.md §2.1).
  const [visitsFailed, setVisitsFailed] = useState<LoadFailure | false>(false);
  // A « Charger plus » that failed: its line, and the SAME page asked again.
  const [moreFailed, setMoreFailed] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [error, setError] = useState<LoadFailure | false>(false);
  const [noteDraft, setNoteDraft] = useState('');
  // One Idempotency-Key per note sent (docs/design/write-idempotency.md §4).
  const noteKey = useRef(new SubmissionKey());
  const [busy, setBusy] = useState(false);
  const [editingTags, setEditingTags] = useState(false);
  const [customTag, setCustomTag] = useState('');
  // Where focus goes when the element that held it is gone (a client_linked:
  // the dialog hands focus back to « Modifier », which the reloaded card no
  // longer has) — the card's own heading, not <body>.
  const headingRef = useRef<HTMLHeadingElement>(null);

  const load = useCallback(async () => {
    const me = await getMyProvider();
    if (me.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    if (me.status !== 200 || !me.profile) {
      setError(loadFailure(me.status));
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
      setError(loadFailure(r.status));
      setLoading(false);
      return;
    }
    setCard(r.card);
    const v = await getClientVisits(pid, clientId, 1);
    setVisits(v.items);
    setVisitsTotal(v.total);
    setVisitsPage(1);
    setVisitsFailed(v.status === 200 ? false : loadFailure(v.status));
    setMoreFailed(null);
    setLoading(false);
  }, [router, clientId]);

  useEffect(() => {
    load();
  }, [load]);


  // The ACTIVE salon's market (multi-pays MP3).
  const tz = profile?.provider.timezone ?? undefined;
  const currency = profile?.provider.currency ?? undefined;

  if (loading) return <SkeletonRows count={4} className="mt-l" />;
  if (notFound) {
    return (
      <div>
        <Link href="/pro/clients" className="text-bodyMedium text-textTertiary">
          ← Clients
        </Link>
        <p className="mt-m text-bodyLarge text-textSecondary">Client introuvable.</p>
      </div>
    );
  }
  if (error || !card || !providerId) {
    return <ErrorState title="Fiche client" message={loadFailureMessage(error)} onRetry={() => { setError(false); setLoading(true); void load(); }} />;
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
    const r = await addClientNote(
      providerId!,
      clientId,
      body,
      noteKey.current.for({ clientId, body }),
    );
    setBusy(false);
    if (r.ok && r.note) {
      // Only once the note shows: a 2xx that came back without it, even
      // asked again, keeps the key — tapping « Ajouter » replays it, never a
      // second note.
      noteKey.current.settle();
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

  /// The history alone, again — « Réessayer » under a failed read.
  async function retryVisits() {
    const v = await getClientVisits(providerId!, clientId, 1);
    setVisits(v.items);
    setVisitsTotal(v.total);
    setVisitsPage(1);
    setVisitsFailed(v.status === 200 ? false : loadFailure(v.status));
  }

  async function moreVisits() {
    setMoreFailed(null);
    const v = await getClientVisits(providerId!, clientId, visitsPage + 1);
    // Only a page that came moves the counter: a failed one was skipped
    // before, and its visits were never shown.
    if (v.status !== 200) {
      setMoreFailed(writeFailureMessage(v.status, 'Le chargement a échoué. Réessayez.'));
      return;
    }
    setVisits((prev) => [...prev, ...v.items]);
    setVisitsPage(visitsPage + 1);
  }

  const tagChoices = [
    ...PRESET_TAGS,
    ...card.tags.filter((t) => !PRESET_TAGS.includes(t)),
  ];

  // « Modifier » only on the server's word (docs/design/phone-leftovers.md
  // §11): `phoneEditable` is exactly the cards whose number its PATCH takes —
  // a guest card with a number. ABSENT means no: the web ships on merge, the
  // backend by a manual dispatch, and the older server refuses `{ phone }`
  // (`invalid_tags`) — a « Modifier » there would fail on every try.
  const editablePhone = card.phoneEditable === true ? card.phone : null;

  return (
    <div>
      <Link href="/pro/clients" className="text-bodyMedium text-textTertiary">
        ← Clients
      </Link>

      <div className="mt-m grid gap-l lg:grid-cols-2">
        {/* Identity + notes */}
        <div>
          <Card>
            <div className="flex items-center gap-m">
              {/* `shrink-0`: the phone row beside it may wrap, which makes
                  that column shrinkable — and without this the avatar gave up
                  width with it (32.7 × 48 at 320px, an oval). */}
              <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-pill bg-surface text-titleLarge font-medium text-textPrimary">
                {card.displayName.slice(0, 1).toUpperCase()}
              </span>
              <div className="min-w-0">
                <h1
                  ref={headingRef}
                  tabIndex={-1}
                  className="flex items-center gap-xs text-titleLarge font-semibold text-textPrimary"
                >
                  {/* clip-ok: this is the page's own `<h1>`, so the bar is
                      higher — and it clears it because the record identifies
                      itself again immediately below, by phone number and visit
                      history, and the name is the document title. Recorded as
                      the weakest of the six: if this page ever loses the phone
                      row, the declaration stops being true. */}
                  <span className="truncate">{card.displayName}</span>
                  {card.linked ? (
                    <Chip dense className="uppercase text-textTertiary">
                      MyWeli
                    </Chip>
                  ) : null}
                </h1>
                {card.phone ? (
                  // The number is READ grouped (« +225 07 00 00 01 01 », the
                  // app's rule — `formatPhoneNumber`) and DIALLED as stored:
                  // both links take `card.phone`, never the grouped text.
                  //
                  // Grouped, it has five places a line could break, and a
                  // phone number may not break (SYSTEM.md §13.3). So the
                  // number is `whitespace-nowrap` and it is the ROW that wraps
                  // (WEB-SYSTEM §9 rule 1): on a narrow card the two actions
                  // drop below the number — together, which is why they share
                  // a wrapper; as three loose items « WhatsApp » dropped alone
                  // at 375px. `gap-y-sm` is the 12px each 48px link reaches
                  // above its own line (`-my-sm`), so a dropped action starts
                  // where the number's line ends instead of lying over it.
                  <p className="mt-xs flex flex-wrap items-center gap-x-s gap-y-sm text-bodyMedium text-textSecondary">
                    <span className="whitespace-nowrap">
                      {formatPhoneNumber(card.phone)}
                    </span>
                    <span className="flex gap-s">
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
                    </span>
                  </p>
                ) : null}
                {/* §8: what the number below the row says — editable on a
                    guest card, the account's own on a linked one. Its own
                    line, never a third item in the row: at 320px the column
                    is ~174px, and « Modifier » dropped alone under « Appeler ·
                    WhatsApp » with the two 48px boxes overlapping across the
                    row's 12px gap. `mt-xl` − the 12px each box reaches
                    (`-my-sm`, theirs and its own) leaves 8px between them
                    (SYSTEM.md §13.2); the caption is no target, so `mt-sm`
                    only has to clear theirs. Shown on `phoneEditable` alone
                    (above): a guest card with a number, on a server whose
                    PATCH takes one. */}
                {editablePhone ? (
                  // `flex`, as the row is: the box's 24px of negative margin
                  // then sizes the line, not an inline baseline.
                  <div className="mt-xl flex text-bodyMedium text-textSecondary">
                    <button
                      type="button"
                      onClick={() => setEditingPhone(true)}
                      // Label in name (WCAG 2.5.3) — and not « Modifier les
                      // tags » further down.
                      aria-label="Modifier le numéro"
                      className="-my-sm inline-flex min-h-12 items-center underline"
                    >
                      Modifier
                    </button>
                  </div>
                ) : null}
                {card.phone && card.linked ? (
                  <p className="mt-sm text-bodySmall text-textTertiary">
                    Numéro du compte client
                  </p>
                ) : null}
              </div>
            </div>

            {/* `mt-l`, not `mt-m`: the target directly above this button —
                « Modifier » under a guest's number, else « Appeler » and
                « WhatsApp » when the phone row wraps — is a 48px box reaching
                12px below its own line (`-my-sm`). 24 − 12 leaves 12px
                between the hit areas; `mt-m` left 4, under the 8px that
                adjacent targets need (SYSTEM.md §13.2). */}
            <div className="mt-l">
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
                    className={chipLinkClasses(active)}
                  >
                    {t}
                  </button>
                ) : (
                  <Chip variant="outlined" key={t}>
                    {t}
                  </Chip>
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
          </Card>

          <Card as="section" className="mt-l">
            <h2 className="text-titleLarge font-semibold text-textPrimary">Notes</h2>
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
          </Card>
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

          <Card as="section" className="mt-l">
            <h2 className="text-titleLarge font-semibold text-textPrimary">
              Historique des visites
            </h2>
            {visitsFailed ? (
              <ErrorState
                className="mt-m"
                message={loadFailureMessage(visitsFailed, 'Historique indisponible.')}
                onRetry={() => void retryVisits()}
              />
            ) : visits.length === 0 ? (
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
                      <StatusChip status={v.status} />
                    </span>
                  </li>
                ))}
              </ul>
            )}
            {!visitsFailed && visits.length < visitsTotal ? (
              <div className="mt-m text-center">
                <Button variant="secondary" onClick={moreVisits}>
                  Charger plus
                </Button>
                {moreFailed ? (
                  <p role="alert" className="mt-s text-bodyMedium text-error">
                    {moreFailed}
                  </p>
                ) : null}
              </div>
            ) : null}
          </Card>
        </div>
      </div>

      {booking && profile && providerId ? (
        <ManualBookingDialog
          providerId={providerId}
          profile={profile}
          initialClient={{
            id: clientId,
            name: card.displayName,
            phone: card.phone ?? undefined,
            // A refused number on a linked card is the account's: the dialog
            // offers no way back to a card that cannot change it.
            linked: card.linked,
          }}
          onClose={() => setBooking(false)}
          onCreated={() => {
            setBooking(false);
            show('Rendez-vous créé', 'success');
            load();
          }}
        />
      ) : null}
      {editingPhone && editablePhone ? (
        <EditPhoneModal
          providerId={providerId}
          clientId={clientId}
          phone={editablePhone}
          onClose={() => setEditingPhone(false)}
          // The salon's manual appointments followed the number server-side:
          // the whole card is read again — stats and visits included.
          onSaved={() => {
            setEditingPhone(false);
            show('Numéro mis à jour', 'success');
            load();
          }}
          // Linked since the card was read: reloaded, it shows the read-only
          // state (no « Modifier », « Numéro du compte client »). « Modifier »
          // — where the dialog hands focus back — goes with that reload, so
          // focus is put on the card's heading once the card is read.
          onLinked={() => {
            setEditingPhone(false);
            show('Ce client a un compte MyWeli : son numéro est celui du compte.', 'error');
            void load().then(() => headingRef.current?.focus());
          }}
        />
      ) : null}
      <Toast toast={toast} />
    </div>
  );
}

// A module constant: useFieldErrors keys its callbacks on this object. A guest
// card exists only by its number, so the field is required.
const PHONE_CHECK = {
  phone: (v: string) => phoneFieldError(v, { required: true }),
};

/// The dialog's dismissal while a save is in flight: nothing.
const ignoreClose = () => {};

/// « Modifier le numéro » of a GUEST card (docs/design/phone-leftovers.md §8).
/// The fault of the number sits UNDER the field (SYSTEM.md §14) — the shared
/// rule on submit, a server `invalid_phone` alike; a refused save's outcome
/// stays INSIDE the dialog (§15). The button is disabled only while saving.
function EditPhoneModal({
  providerId,
  clientId,
  phone: current,
  onClose,
  onSaved,
  onLinked,
}: {
  providerId: string;
  clientId: string;
  /** The card's stored number — prefilled, and what « nothing changed » means. */
  phone: string;
  onClose: () => void;
  onSaved: () => void;
  onLinked: () => void;
}) {
  const [phone, setPhone] = useState(current);
  const [busy, setBusy] = useState(false);
  // `cardId`: the card that already holds the number — the way out rides with
  // its sentence, so neither can outlive the other.
  const [outcome, setOutcome] = useState<{ text: string; cardId?: string } | null>(
    null,
  );
  const fields = useFieldErrors(PHONE_CHECK);
  // Gone mid-save (the page left): the other card's name has nowhere to show,
  // and reading it is an AUDITED view of that card — so it is not read.
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  async function save() {
    if (!fields.validate({ phone })) return;
    // What is checked is what crosses: separators stripped.
    const next = normalizePhone(phone);
    // The number the card already has: nothing to do, nothing to say.
    if (next === current) {
      onClose();
      return;
    }
    setBusy(true);
    setOutcome(null);
    const r = await updateClientPhone(providerId, clientId, next);
    if (r.ok) {
      onSaved();
      return;
    }
    if (r.error === 'client_linked') {
      onLinked();
      return;
    }
    if (r.error === 'invalid_phone') {
      setBusy(false);
      fields.set('phone', PHONE_INVALID);
      return;
    }
    if (r.error === 'client_exists' && r.clientId) {
      // The 409 names the other card by id only (the shape of POST
      // …/clients). Its name costs ONE read of that card, by id — audited
      // server-side as a view of it, which is true: its name is shown here.
      // Not the list searched by the number: that matches loosely and would
      // write the number into the audit trail's query.
      if (!mounted.current) return;
      const other = await getClientCard(providerId, r.clientId);
      setBusy(false);
      setOutcome({
        text: other.card
          ? `Ce numéro est déjà sur la fiche ${deName(other.card.displayName)}.`
          : 'Ce numéro est déjà sur une autre fiche.',
        cardId: r.clientId,
      });
      return;
    }
    setBusy(false);
    setOutcome({ text: writeFailureMessage(r.status, 'L’enregistrement a échoué. Réessayez.') });
  }

  return (
    // Not closable while saving — Escape and the scrim, as « Annuler » is
    // disabled: the answer (a refusal especially) must land in this dialog.
    <Modal title="Modifier le numéro" onClose={busy ? ignoreClose : onClose}>
      <div className="mt-m">
        <PhoneField
          initialValue={current}
          onChange={(v) => {
            setPhone(v);
            fields.revalidate('phone', v);
            // A sentence about another number would be stale.
            setOutcome(null);
          }}
          error={fields.errors.phone}
        />
      </div>
      {outcome ? (
        <p role="alert" className="mt-s text-bodyMedium text-error">
          {outcome.text}
        </p>
      ) : null}
      {/* Closing first: the other card replaces this one under the dialog. */}
      {outcome?.cardId ? (
        <Link
          href={`/pro/clients/${outcome.cardId}`}
          onClick={onClose}
          className="mt-xs inline-flex min-h-12 items-center text-bodyMedium text-textPrimary underline"
        >
          Ouvrir la fiche
        </Link>
      ) : null}
      <div className="mt-l flex justify-end gap-s">
        <Button variant="secondary" onClick={onClose} disabled={busy}>
          Annuler
        </Button>
        {/* No number gate: a wrong one answers under its field (§14 rule 5). */}
        <Button onClick={save} disabled={busy}>
          Enregistrer
        </Button>
      </div>
    </Modal>
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
