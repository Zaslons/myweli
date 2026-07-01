'use client';

import { useReducer, useState } from 'react';
import { isPossiblePhoneNumber } from 'react-phone-number-input';
import type { Provider } from '../../lib/api/providers';
import {
  type CreatedBooking,
  createBooking,
  fetchSlots,
  requestOtp,
  verifyOtp,
} from '../../lib/booking/client';
import {
  estimatedDeposit,
  initialState,
  priceTotal,
  reducer,
  selectedServices,
  totalDuration,
} from '../../lib/booking/state';
import { formatDateFr, formatDuration, formatFcfa, priceRange } from '../../lib/format';
import { Button } from '../Button';
import { OpenInAppButton } from '../OpenInAppButton';
import { PhoneField } from '../PhoneField';

const today = () => new Date().toISOString().slice(0, 10);
const slotTime = (iso: string) =>
  new Intl.DateTimeFormat('fr-FR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'UTC',
  }).format(new Date(iso));

function totalLabel(p: Provider, ids: string[]): string {
  const t = priceTotal(p, ids);
  return t.max > t.min
    ? `${formatFcfa(t.min)} – ${formatFcfa(t.max)}`
    : formatFcfa(t.min);
}

export function BookingFlow({ provider }: { provider: Provider }) {
  const [s, dispatch] = useReducer(reducer, initialState);
  const [slots, setSlots] = useState<string[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [otpSent, setOtpSent] = useState(false);
  const [devCode, setDevCode] = useState<string | undefined>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [created, setCreated] = useState<CreatedBooking | null>(null);

  const services = (provider.services ?? []).filter((x) => x.active !== false);
  const duration = totalDuration(provider, s.serviceIds);

  async function loadSlots(date: string) {
    setSlotsLoading(true);
    setError(null);
    const r = await fetchSlots({
      providerId: provider.id,
      date,
      serviceIds: s.serviceIds,
      durationMinutes: duration,
    });
    setSlots(r);
    setSlotsLoading(false);
  }

  async function sendCode() {
    setBusy(true);
    setError(null);
    const r = await requestOtp(phone);
    setBusy(false);
    if (!r.ok) return setError('Numéro invalide ou envoi impossible.');
    setOtpSent(true);
    setDevCode(r.devCode);
  }

  async function confirm() {
    setBusy(true);
    setError(null);
    const v = await verifyOtp(phone, code);
    if (!v.ok) {
      setBusy(false);
      return setError('Code incorrect ou expiré.');
    }
    const b = await createBooking({
      providerId: provider.id,
      serviceIds: s.serviceIds,
      appointmentDateTime: s.slot!,
      artistId: s.artistId,
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
    dispatch({ type: 'go', step: 'done' });
  }

  // ---- DONE -----------------------------------------------------------------
  if (s.step === 'done') {
    const deposit = created?.depositAmount ?? 0;
    return (
      <section className="rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-xl font-semibold text-textPrimary">
          Réservation envoyée ✓
        </h2>
        <p className="mt-s text-textSecondary">
          {provider.name} va confirmer votre rendez-vous. Vous recevrez une
          notification.
        </p>
        {deposit > 0 ? (
          <div className="mt-m rounded-lg bg-surface p-m">
            <p className="font-medium text-textPrimary">
              Acompte à régler : {formatFcfa(deposit)}
            </p>
            <p className="mt-xs text-sm text-textSecondary">
              Payez directement au salon
              {provider.depositMobileMoneyNumber
                ? ` (${provider.depositMobileMoneyOperator ?? 'Mobile Money'} : ${provider.depositMobileMoneyNumber})`
                : ''}
              , puis joignez la capture dans l’app. MyWeli ne prélève rien.
            </p>
          </div>
        ) : null}
        <div className="mt-l flex flex-wrap gap-s">
          <OpenInAppButton />
        </div>
      </section>
    );
  }

  return (
    <section className="rounded-xl border border-border bg-secondary p-l">
      {/* Step: services */}
      {s.step === 'services' ? (
        <div>
          <h2 className="text-xl font-semibold text-textPrimary">
            Choisissez vos prestations
          </h2>
          <ul className="mt-m divide-y divide-divider">
            {services.map((svc) => {
              const on = s.serviceIds.includes(svc.id);
              return (
                <li key={svc.id}>
                  <label className="flex cursor-pointer items-center justify-between gap-m py-s">
                    <span>
                      <span className="text-textPrimary">{svc.name}</span>
                      <span className="block text-sm text-textTertiary">
                        {formatDuration(svc.durationMinutes)} ·{' '}
                        {priceRange(svc.price, svc.priceMax)}
                      </span>
                    </span>
                    <input
                      type="checkbox"
                      checked={on}
                      onChange={() => dispatch({ type: 'toggleService', id: svc.id })}
                    />
                  </label>
                </li>
              );
            })}
          </ul>
          {s.serviceIds.length > 0 ? (
            <p className="mt-m text-sm text-textSecondary">
              Total : {totalLabel(provider, s.serviceIds)} · {formatDuration(duration)}
            </p>
          ) : null}
          <div className="mt-l">
            <Button
              disabled={s.serviceIds.length === 0}
              onClick={() => dispatch({ type: 'go', step: 'staff' })}
            >
              Continuer
            </Button>
          </div>
        </div>
      ) : null}

      {/* Step: staff */}
      {s.step === 'staff' ? (
        <div>
          <h2 className="text-xl font-semibold text-textPrimary">
            Avec qui ?
          </h2>
          <div className="mt-m space-y-s">
            <label className="flex items-center gap-s">
              <input
                type="radio"
                name="artist"
                checked={s.artistId === null}
                onChange={() => dispatch({ type: 'setArtist', id: null })}
              />
              <span className="text-textPrimary">Sans préférence</span>
            </label>
            {(provider.artists ?? []).map((a) => (
              <label key={a.id} className="flex items-center gap-s">
                <input
                  type="radio"
                  name="artist"
                  checked={s.artistId === a.id}
                  onChange={() => dispatch({ type: 'setArtist', id: a.id })}
                />
                <span className="text-textPrimary">{a.name}</span>
              </label>
            ))}
          </div>
          <div className="mt-l flex gap-s">
            <Button variant="secondary" onClick={() => dispatch({ type: 'go', step: 'services' })}>
              Retour
            </Button>
            <Button onClick={() => dispatch({ type: 'go', step: 'slot' })}>
              Continuer
            </Button>
          </div>
        </div>
      ) : null}

      {/* Step: slot */}
      {s.step === 'slot' ? (
        <div>
          <h2 className="text-xl font-semibold text-textPrimary">
            Choisissez un créneau
          </h2>
          <input
            type="date"
            min={today()}
            value={s.date ?? ''}
            onChange={(e) => {
              dispatch({ type: 'setDate', date: e.target.value });
              if (e.target.value) loadSlots(e.target.value);
            }}
            className="mt-m rounded-lg border border-border bg-surface px-m py-s text-textPrimary"
          />
          {s.date ? (
            slotsLoading ? (
              <p className="mt-m text-textSecondary">Chargement des créneaux…</p>
            ) : slots.length === 0 ? (
              <p className="mt-m text-textSecondary">
                Aucun créneau ce jour. Essayez une autre date.
              </p>
            ) : (
              <div className="mt-m flex flex-wrap gap-s">
                {slots.map((iso) => (
                  <button
                    key={iso}
                    type="button"
                    onClick={() => dispatch({ type: 'setSlot', slot: iso })}
                    className={`rounded-lg border px-m py-s text-sm ${
                      s.slot === iso
                        ? 'border-primary bg-primary text-secondary'
                        : 'border-border bg-surface text-textPrimary'
                    }`}
                  >
                    {slotTime(iso)}
                  </button>
                ))}
              </div>
            )
          ) : null}
          <div className="mt-l flex gap-s">
            <Button variant="secondary" onClick={() => dispatch({ type: 'go', step: 'staff' })}>
              Retour
            </Button>
            <Button disabled={!s.slot} onClick={() => dispatch({ type: 'go', step: 'confirm' })}>
              Continuer
            </Button>
          </div>
        </div>
      ) : null}

      {/* Step: confirm + OTP */}
      {s.step === 'confirm' ? (
        <div>
          <h2 className="text-xl font-semibold text-textPrimary">Confirmation</h2>
          <dl className="mt-m space-y-xs text-sm">
            <Recap label="Salon" value={provider.name} />
            <Recap
              label="Prestations"
              value={selectedServices(provider, s.serviceIds).map((x) => x.name).join(', ')}
            />
            {s.slot ? (
              <Recap
                label="Date"
                value={`${formatDateFr(s.slot)} à ${slotTime(s.slot)}`}
              />
            ) : null}
            <Recap label="Total" value={totalLabel(provider, s.serviceIds)} />
            {provider.depositRequired ? (
              <Recap
                label="Acompte estimé"
                value={formatFcfa(estimatedDeposit(provider, s.serviceIds))}
              />
            ) : null}
          </dl>

          <p className="mt-m text-sm text-textSecondary">
            Confirmez avec votre numéro de téléphone (code par SMS).
          </p>
          <div className="mt-s flex flex-col gap-s">
            <PhoneField onChange={setPhone} />
            {!otpSent ? (
              <Button
                disabled={busy || !phone || !isPossiblePhoneNumber(phone)}
                onClick={sendCode}
              >
                Envoyer le code
              </Button>
            ) : (
              <>
                <input
                  type="text"
                  inputMode="numeric"
                  placeholder="Code à 6 chiffres"
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  className="rounded-lg border border-border bg-surface px-m py-s text-textPrimary"
                />
                {devCode ? (
                  <p className="text-xs text-textTertiary">Code (dev) : {devCode}</p>
                ) : null}
                <Button disabled={busy || code.length < 4} onClick={confirm}>
                  Confirmer la réservation
                </Button>
              </>
            )}
          </div>
          {error ? <p className="mt-s text-sm text-error">{error}</p> : null}
          <div className="mt-l">
            <Button variant="secondary" onClick={() => dispatch({ type: 'go', step: 'slot' })}>
              Retour
            </Button>
          </div>
        </div>
      ) : null}
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
