'use client';

import { useEffect, useRef, useState } from 'react';
import { chipLinkClasses } from '../Chip';
import { Loading } from '../Loading';
import { SkeletonRows } from '../Skeleton';
import { isPossiblePhoneNumber } from 'react-phone-number-input';
import { type Me, getMe } from '../../lib/api/account';
import type { Provider } from '../../lib/api/providers';
import { updateContactPhone } from '../../lib/auth/client';
import {
  type CreatedBooking,
  createBooking,
  fetchSlots,
} from '../../lib/booking/client';
import {
  type HubState,
  type Section,
  advance,
  artistCanDoServices,
  availableLengthVariants,
  bookingHasVariants,
  canConfirm,
  chooseArtist,
  clearSlot,
  estimatedDeposit,
  goPhase,
  initialHubState,
  lengthVariantLabel,
  openSection,
  pickSlot,
  autoPickSlot,
  priceTotal,
  sanitizeRebookSelection,
  selectedServices,
  setDate,
  setVariant,
  shouldAutoPickEarliest,
  slotFetchDuration,
  todayYmd,
  toggleService,
  totalDuration,
} from '../../lib/booking/state';
import {
  formatDateFr,
  formatDuration,
  formatFcfa,
  priceRange,
} from '../../lib/format';
import { salonDayKey, salonFormatter } from '../../lib/time';
import { Button } from '../Button';
import { SalonTimeHint } from '../SalonTimeHint';
import { LoginOptions } from '../auth/LoginOptions';
import { OpenInAppButton } from '../OpenInAppButton';
import { PhoneField } from '../PhoneField';
import { TextField } from '../TextField';
import { DepositProof } from './DepositProof';

const slotTime = (iso: string, tz?: string) =>
  salonFormatter({ hour: '2-digit', minute: '2-digit' }, tz).format(
    new Date(iso),
  );

function totalLabel(p: Provider, ids: string[]): string {
  const t = priceTotal(p, ids);
  const cur = p.currency ?? undefined;
  return t.max > t.min
    ? `${formatFcfa(t.min, cur)} – ${formatFcfa(t.max, cur)}`
    : formatFcfa(t.min, cur);
}

/// The booking HUB (K2 — docs/design/booking-capacity-web-hub.md §4): the
/// app's order-free flow on web. Three sections always visible; the first
/// interaction fixes the entry point and the auto-advance + constraint graph
/// adapt (services⇄artists capability, artist→slots, time-first default +
/// silent re-validation, artist-first earliest-slot auto-pick, length
/// variants). Confirm/done steps kept from the wizard; done becomes the
/// deposit-proof sheet when the booking carries an acompte.
export function BookingFlow({
  provider,
  prefillServiceIds,
  prefillArtistId,
  countryLabel,
}: {
  provider: Provider;
  prefillServiceIds?: string[];
  prefillArtistId?: string | null;
  /// The salon country's display name (tree lookup by the reserver page) —
  /// feeds the salon-time hint (multi-pays MP3).
  countryLabel?: string | null;
}) {
  // The viewed SALON's market (multi-pays): its clock shapes every day/time
  // rendered here; its currency labels every price.
  const tz = provider.timezone ?? undefined;
  const currency = provider.currency ?? undefined;
  const [s, setS] = useState<HubState>(() => {
    const clean = sanitizeRebookSelection(
      provider,
      prefillServiceIds ?? [],
      prefillArtistId ?? null,
    );
    return initialHubState(clean, tz);
  });
  const [slots, setSlots] = useState<string[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);
  // The app's slotsRequestId pattern — stale slot responses are dropped.
  const slotsReq = useRef(0);

  // Auth overhaul P2: confirming requires a signed-in account + a REQUIRED
  // contact phone. undefined = probing the session; null = signed out.
  const [me, setMe] = useState<Me | null | undefined>(undefined);
  const [phone, setPhone] = useState('');
  // Parity 2.10 — the app's « Notes (optionnel) » on the confirm step.
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [created, setCreated] = useState<CreatedBooking | null>(null);

  const services = (provider.services ?? []).filter((x) => x.active !== false);
  const artists = provider.artists ?? [];
  const hasArtists = artists.length > 0;
  const selection = selectedServices(provider, s.serviceIds);
  const duration = totalDuration(provider, s.serviceIds, s.lengthVariant);

  // Probe the session when the confirm phase opens (re-run after inline login).
  useEffect(() => {
    if (s.phase !== 'confirm' || me !== undefined) return;
    let active = true;
    (async () => {
      const r = await getMe();
      if (!active) return;
      setMe(r.status === 200 ? (r.user ?? null) : null);
      setPhone(r.user?.phoneNumber ?? '');
    })();
    return () => {
      active = false;
    };
  }, [s.phase, me]);

  function fetchSlotsFor(state: HubState, date: string) {
    return fetchSlots({
      providerId: provider.id,
      date,
      serviceIds: state.serviceIds,
      durationMinutes: slotFetchDuration(provider, state),
      artistId: state.artistId,
    });
  }

  async function loadSlots(state: HubState) {
    const req = ++slotsReq.current;
    setSlotsLoading(true);
    const r = await fetchSlotsFor(state, state.date);
    if (req !== slotsReq.current) return;
    setSlots(r);
    setSlotsLoading(false);
  }

  /// Time-first rule: keep the chosen time if it still fits the (new)
  /// selection/variant/stylist; otherwise clear it silently.
  async function revalidateSlot(state: HubState): Promise<HubState> {
    if (!state.slot) return state;
    const r = await fetchSlotsFor(state, state.slot.slice(0, 10));
    return r.includes(state.slot) ? state : clearSlot(state);
  }

  /// Artist-first rule: auto-pick the earliest slot within 14 days.
  async function findEarliestSlot(state: HubState): Promise<string | null> {
    const start = Date.parse(`${todayYmd(tz)}T00:00:00Z`);
    for (let i = 0; i <= 14; i++) {
      const day = salonDayKey(new Date(start + i * 86_400_000), tz);
      const r = await fetchSlotsFor(state, day);
      if (r.length > 0) return r[0];
    }
    return null;
  }

  /// The shared post-mutation pipeline (mirrors the app's handler sequence):
  /// re-validate the chosen time → maybe auto-pick the earliest → advance to
  /// the next section for this entry point → refresh slots if landing on time.
  async function settle(state: HubState) {
    let next = await revalidateSlot(state);
    if (shouldAutoPickEarliest(next)) {
      const earliest = await findEarliestSlot(next);
      if (earliest) next = autoPickSlot(next, earliest);
    }
    next = advance(next, hasArtists);
    setS(next);
    if (next.activeSection === 'time') await loadSlots(next);
  }

  // Rebook prefill lands on the time section → load its slots on mount.
  useEffect(() => {
    if (s.activeSection === 'time') loadSlots(s);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function onToggleService(id: string) {
    const next = toggleService(s, provider, id);
    setS(next);
    await settle(next);
  }

  async function onVariant(variant: string) {
    let next = setVariant(s, variant);
    setS(next);
    next = await revalidateSlot(next);
    setS(next);
    if (next.activeSection === 'time') await loadSlots(next);
  }

  async function onChooseArtist(id: string | null) {
    const next = chooseArtist(s, provider, id);
    if (next === s) return; // incompatible stylist — row is disabled anyway
    setS(next);
    await settle(next);
  }

  async function onOpenSection(section: Section) {
    const next = openSection(s, section);
    setS(next);
    if (section === 'time') await loadSlots(next);
  }

  async function onDate(date: string) {
    if (!date) return;
    const next = setDate(s, date);
    setS(next);
    await loadSlots(next);
  }

  function onPickSlot(iso: string) {
    setS(advance(pickSlot(s, iso), hasArtists));
  }

  async function confirm() {
    setBusy(true);
    setError(null);
    // Contact phone is REQUIRED (decision 2026-07-02); persist it when changed.
    if (phone !== (me?.phoneNumber ?? '')) {
      const saved = await updateContactPhone(phone);
      if (!saved.ok) {
        setBusy(false);
        return setError('Numéro invalide. Vérifiez et réessayez.');
      }
    }
    const b = await createBooking({
      providerId: provider.id,
      serviceIds: s.serviceIds,
      appointmentDateTime: s.slot!,
      artistId: s.artistId,
      notes: notes.trim() || undefined,
    });
    setBusy(false);
    if (!b.ok) {
      return setError(
        b.error === 'slot_unavailable'
          ? 'Ce créneau vient d’être pris. Choisissez-en un autre.'
          : 'La réservation a échoué. Réessayez.',
      );
    }
    setCreated(b.appointment ?? null);
    setS(goPhase(s, 'done'));
  }

  // ---- DONE (deposit-aware) --------------------------------------------------
  if (s.phase === 'done') {
    const deposit = created?.depositAmount ?? 0;
    return (
      <section className="rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">
          Réservation envoyée ✓
        </h2>
        <p className="mt-s text-textSecondary">
          {provider.name} va confirmer votre rendez-vous. Vous recevrez une
          notification.
        </p>
        {deposit > 0 && created?.id ? (
          <div className="mt-m">
            <DepositProof
              appointmentId={created.id}
              amount={deposit}
              operator={provider.depositMobileMoneyOperator}
              number={provider.depositMobileMoneyNumber}
              currency={currency}
            />
          </div>
        ) : null}
        <div className="mt-l flex flex-wrap gap-s">
          <OpenInAppButton />
        </div>
      </section>
    );
  }

  // ---- CONFIRM ---------------------------------------------------------------
  if (s.phase === 'confirm') {
    return (
      <section className="rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">Confirmation</h2>
        <dl className="mt-m space-y-xs text-bodyMedium">
          <Recap label="Salon" value={provider.name} />
          <Recap
            label="Prestations"
            value={selection.map((x) => x.name).join(', ')}
          />
          {s.lengthVariant ? (
            <Recap label="Longueur" value={lengthVariantLabel(s.lengthVariant)} />
          ) : null}
          <Recap
            label="Spécialiste"
            value={
              s.artistId
                ? (artists.find((a) => a.id === s.artistId)?.name ?? '—')
                : 'Pas de préférence'
            }
          />
          {s.slot ? (
            <Recap
              label="Date"
              value={`${formatDateFr(s.slot, tz)} à ${slotTime(s.slot, tz)}`}
            />
          ) : null}
          {s.slot ? (
            <SalonTimeHint
              date={s.slot}
              tz={provider.timezone}
              countryLabel={countryLabel}
              className="text-bodySmall text-textTertiary"
            />
          ) : null}
          <Recap label="Total" value={totalLabel(provider, s.serviceIds)} />
          {provider.depositRequired ? (
            <Recap
              label="Acompte estimé"
              value={formatFcfa(
                estimatedDeposit(provider, s.serviceIds),
                currency,
              )}
            />
          ) : null}
        </dl>

        {me === undefined ? (
          <Loading className="mt-m" />
        ) : me === null ? (
          <div className="mt-m">
            <p className="text-bodyMedium text-textSecondary">
              Connectez-vous pour confirmer votre réservation.
            </p>
            <div className="mt-s">
              {/* After login (incl. its mandatory phone step) re-probe the
                  session — the flow continues in place, no redirect. */}
              <LoginOptions onSuccess={() => setMe(undefined)} />
            </div>
          </div>
        ) : (
          <div className="mt-m flex flex-col gap-s">
            <p className="text-bodyMedium text-textSecondary">
              Numéro pour que le salon vous contacte :
            </p>
            <PhoneField
              onChange={setPhone}
              initialValue={me.phoneNumber ?? undefined}
            />
            <TextField
              className="mt-s"
              label="Notes (optionnelles)"
              multiline
              rows={3}
              maxLength={500}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              hint="Précisions pour le salon (allergies, préférences…)"
            />
            <Button
              disabled={busy || !phone || !isPossiblePhoneNumber(phone)}
              onClick={confirm}
            >
              Confirmer la réservation
            </Button>
          </div>
        )}
        {error ? <p role="alert" className="mt-s text-bodyMedium text-error">{error}</p> : null}
        <div className="mt-l">
          <Button
            variant="secondary"
            onClick={() => setS(goPhase(s, 'hub'))}
          >
            Retour
          </Button>
        </div>
      </section>
    );
  }

  // ---- HUB ---------------------------------------------------------------
  return (
    <div
      // ds-ignore: clears the pinned bottom bar. 6rem, NOT 96px — `pb-24` was
      // 6rem, and the bar it clears is TEXT-driven, so a px clearance stops
      // tracking the root font size: raise it and the bar grows while the gap
      // does not, and the bar covers the content (SYSTEM.md §13.3 — A5's lesson,
      // on the web). 96 is off the rhythm scale, hence the exception. The grid
      // template is a layout ratio + a fixed side panel — not a token either.
      // eslint-disable-next-line tailwindcss/no-arbitrary-value
      className="pb-[6rem] lg:grid lg:grid-cols-[minmax(0,1fr)_320px] lg:items-start lg:gap-l lg:pb-0"
    >
      <div className="space-y-s">
        {/* PRESTATIONS */}
        <SectionCard
          title="Prestations"
          value={
            s.serviceIds.length === 0
              ? 'Choisir'
              : s.serviceIds.length === 1
                ? (selection[0]?.name ?? 'Choisir')
                : `${s.serviceIds.length} prestations`
          }
          expanded={s.activeSection === 'services'}
          onHeaderTap={() => onOpenSection('services')}
        >
          {services.length === 0 ? (
            <p className="text-bodyMedium text-textSecondary">
              Aucun service disponible
            </p>
          ) : (
            <ul className="divide-y divide-divider">
              {services.map((svc) => {
                const on = s.serviceIds.includes(svc.id);
                const hasVariants =
                  svc.durationVariants &&
                  (svc.durationVariants.court != null ||
                    svc.durationVariants.moyen != null ||
                    svc.durationVariants.long != null);
                return (
                  <li key={svc.id}>
                    <label className="flex cursor-pointer items-center justify-between gap-m py-s">
                      <span>
                        <span className="text-textPrimary">{svc.name}</span>
                        <span className="block text-bodyMedium text-textTertiary">
                          {hasVariants
                            ? `${priceRange(svc.price, svc.priceMax, currency)} · durée selon la longueur`
                            : `${formatDuration(svc.durationMinutes)} · ${priceRange(svc.price, svc.priceMax, currency)}`}
                        </span>
                      </span>
                      <input
                        type="checkbox"
                        className="h-5 w-5 shrink-0 accent-primary"
                        checked={on}
                        onChange={() => onToggleService(svc.id)}
                      />
                    </label>
                  </li>
                );
              })}
            </ul>
          )}
          {bookingHasVariants(selection) ? (
            <div className="mt-m">
              <p className="text-bodyMedium text-textSecondary">Longueur de cheveux :</p>
              <div
                role="group"
                aria-label="Longueur de cheveux"
                className="mt-xs flex flex-wrap gap-s"
              >
                {availableLengthVariants(selection).map((k) => (
                  <button
                    key={k}
                    type="button"
                    onClick={() => onVariant(k)}
                    aria-pressed={s.lengthVariant === k}
                    className={chipLinkClasses(s.lengthVariant === k)}
                  >
                    {lengthVariantLabel(k)} ·{' '}
                    {formatDuration(totalDuration(provider, s.serviceIds, k))}
                  </button>
                ))}
              </div>
            </div>
          ) : null}
        </SectionCard>

        {/* SPÉCIALISTE */}
        <SectionCard
          title="Spécialiste"
          value={
            s.artistId
              ? (artists.find((a) => a.id === s.artistId)?.name ??
                'Pas de préférence')
              : 'Pas de préférence'
          }
          expanded={s.activeSection === 'artist'}
          onHeaderTap={() => onOpenSection('artist')}
        >
          {!hasArtists ? (
            <p className="text-bodyMedium text-textSecondary">
              Aucun spécialiste à sélectionner
            </p>
          ) : (
            <div className="space-y-s">
              <label className="flex min-h-12 cursor-pointer items-center gap-s">
                <input
                  type="radio"
                  name="artist"
                  className="h-5 w-5 shrink-0 accent-primary"
                  checked={s.artistChosen && s.artistId === null}
                  onChange={() => onChooseArtist(null)}
                />
                <span>
                  <span className="text-textPrimary">Pas de préférence</span>
                  <span className="block text-bodyMedium text-textTertiary">
                    Le salon choisit pour vous
                  </span>
                </span>
              </label>
              {artists.map((a) => {
                const canDo =
                  s.serviceIds.length === 0 ||
                  artistCanDoServices(provider, a.id, s.serviceIds);
                return (
                  <label
                    key={a.id}
                    className={`flex min-h-12 items-center gap-s ${
                      canDo ? 'cursor-pointer' : 'cursor-not-allowed opacity-45'
                    }`}
                  >
                    <input
                      type="radio"
                      name="artist"
                      className="h-5 w-5 shrink-0 accent-primary"
                      disabled={!canDo}
                      checked={s.artistChosen && s.artistId === a.id}
                      onChange={() => onChooseArtist(a.id)}
                    />
                    <span>
                      <span className="text-textPrimary">{a.name}</span>
                      <span className="block text-bodyMedium text-textTertiary">
                        {a.specialization ?? 'Spécialiste'}
                      </span>
                    </span>
                  </label>
                );
              })}
            </div>
          )}
        </SectionCard>

        {/* DATE ET HEURE */}
        <SectionCard
          title="Date et heure"
          value={
            s.slot
              ? `${formatDateFr(s.slot, tz)} · ${slotTime(s.slot, tz)}`
              : 'Choisir'
          }
          expanded={s.activeSection === 'time'}
          onHeaderTap={() => onOpenSection('time')}
        >
          <TextField
            label="Date"
            hideLabel
            type="date"
            min={todayYmd(tz)}
            value={s.date}
            onChange={(e) => onDate(e.target.value)}
          />
          {slotsLoading ? (
            <Loading label="Chargement des créneaux…" className="mt-m" />
          ) : slots.length === 0 ? (
            <p className="mt-m text-textSecondary">Aucun créneau disponible</p>
          ) : (
            <div className="mt-m flex flex-wrap gap-s">
              {slots.map((iso) => (
                <button
                  key={iso}
                  type="button"
                  onClick={() => onPickSlot(iso)}
                  className={chipLinkClasses(s.slot === iso)}
                >
                  {slotTime(iso, tz)}
                </button>
              ))}
            </div>
          )}
          {s.entryPoint === 'artist' &&
          s.artistChosen &&
          s.serviceIds.length > 0 &&
          s.slot ? (
            <p className="mt-s text-bodyMedium text-textSecondary">
              Prochain créneau : {formatDateFr(s.slot, tz)} ·{' '}
              {slotTime(s.slot, tz)}
            </p>
          ) : null}
          <SalonTimeHint
            date={s.slot ?? undefined}
            tz={provider.timezone}
            countryLabel={countryLabel}
          />
        </SectionCard>
      </div>

      {/* SUMMARY (sticky aside on desktop; the app's pinned bar on mobile —
          parity 2.11). */}
      <aside className="hidden rounded-xl border border-border bg-secondary p-m lg:sticky lg:top-24 lg:block">
        <div className="flex items-center justify-between gap-m">
          <span className="font-semibold text-textPrimary">Total</span>
          <span className="text-titleLarge font-semibold text-primary">
            {totalLabel(provider, s.serviceIds)}
          </span>
        </div>
        {duration > 0 ? (
          <p className="mt-xs text-bodyMedium text-textSecondary">
            Durée : {formatDuration(duration)}
          </p>
        ) : null}
        {!s.artistChosen && hasArtists ? (
          <p className="mt-xs text-bodyMedium text-textSecondary">
            Spécialiste optionnel (vous pouvez laisser « Pas de préférence »)
          </p>
        ) : null}
        <div className="mt-m">
          <Button
            disabled={!canConfirm(s)}
            onClick={() => setS(goPhase(s, 'confirm'))}
          >
            Confirmer
          </Button>
        </div>
      </aside>

      {/* Mobile-web pinned bottom bar (parity 2.11 — the app's fixed
          Total + « Confirmer »). */}
      <div className="fixed inset-x-0 bottom-0 z-sticky border-t border-divider bg-secondary px-m py-s lg:hidden">
        <div className="mx-auto flex max-w-2xl items-center justify-between gap-m">
          <div>
            <p className="font-semibold text-textPrimary">
              {totalLabel(provider, s.serviceIds)}
            </p>
            {duration > 0 ? (
              <p className="text-bodySmall text-textSecondary">
                Durée : {formatDuration(duration)}
              </p>
            ) : null}
          </div>
          <Button
            disabled={!canConfirm(s)}
            onClick={() => setS(goPhase(s, 'confirm'))}
          >
            Confirmer
          </Button>
        </div>
      </div>
    </div>
  );
}

function SectionCard({
  title,
  value,
  expanded,
  onHeaderTap,
  children,
}: {
  title: string;
  value: string;
  expanded: boolean;
  onHeaderTap: () => void;
  children: React.ReactNode;
}) {
  return (
    <section
      className={`rounded-xl border bg-secondary p-m ${
        expanded ? 'border-primary' : 'border-border'
      }`}
    >
      <button
        type="button"
        onClick={onHeaderTap}
        aria-expanded={expanded}
        className="flex w-full items-center justify-between gap-m text-left"
      >
        <span className="font-semibold text-textPrimary">{title}</span>
        <span className="text-bodyMedium text-textSecondary">{value}</span>
      </button>
      {expanded ? <div className="mt-m">{children}</div> : null}
    </section>
  );
}

function Recap({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-m">
      <dt className="text-textTertiary">{label}</dt>
      <dd className="text-right text-textPrimary">{value}</dd>
    </div>
  );
}
