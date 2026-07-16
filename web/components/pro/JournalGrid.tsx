'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { statusLabelFr } from '../../lib/account/appointments';
import type { ProProfile } from '../../lib/api/pro';
import { rescheduleAppointment } from '../../lib/api/pro';
import { formatFcfa } from '../../lib/format';
import {
  CLOSED_AXIS,
  type JournalDay,
  PX_PER_MIN,
  STATUS_STYLE,
  axisHeight,
  blockBox,
  breakBands,
  columnsFor,
  hourTicks,
  type JournalHours,
  isDraggable,
  isoAt,
  nowLineTop,
  parseHhmm,
  snapToQuarter,
  statusKey,
} from '../../lib/pro/journal';
import type { ProAppointment } from '../../lib/pro/today';
import { salonFormatter } from '../../lib/time';
import { JournalPanel } from './JournalPanel';
import { ManualBookingDialog } from './ManualBookingDialog';

let draggingAppt: ProAppointment | null = null;

const AXIS_W = 56;
const COL_MIN_W = 168;

/// The journal day grid (module journal J1 — docs/design/journal-j1-grid.md
/// §3): artist columns, 15-min axis, now-line, drag-reschedule (optimistic,
/// 409 snap-back), click-panel + quick-create. `providerId` owns the data;
/// the backend enforces it. `readOnly` (team access R5b, own-scope roles):
/// no drag, no quick-create — blocks still open the panel.
export function JournalGrid({
  providerId,
  day,
  profile,
  readOnly = false,
  onChanged,
  onToast,
}: {
  providerId: string;
  day: JournalDay;
  profile: ProProfile;
  readOnly?: boolean;
  onChanged: () => void;
  onToast: (msg: string) => void;
}) {
  const hours = day.hours ?? CLOSED_AXIS;
  // The ACTIVE salon's market (multi-pays MP3): its clock places blocks, the
  // now-line and drop instants; its currency labels the block prices.
  const tz = profile.provider.timezone ?? undefined;
  const currency = profile.provider.currency ?? undefined;
  const openMin = parseHhmm(hours.open);
  const columns = useMemo(() => columnsFor(day), [day]);
  const height = axisHeight(hours);
  const scrollRef = useRef<HTMLDivElement>(null);

  const [selected, setSelected] = useState<ProAppointment | null>(null);
  const [quick, setQuick] = useState<
    { artistId: string; minute: number } | null
  >(null);
  const [nowTop, setNowTop] = useState<number | null>(null);

  // Live « Maintenant » line.
  useEffect(() => {
    const tick = () => setNowTop(nowLineTop(new Date(), day.date, hours, tz));
    tick();
    const t = setInterval(tick, 60_000);
    return () => clearInterval(t);
  }, [day.date, hours, tz]);

  // Auto-scroll the now-line (or ~open) into view once.
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = Math.max(0, (nowTop ?? 0) - 120);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [day.date]);

  const byColumn = (artistId: string) =>
    day.appointments.filter((a) => (a.artistId ?? '') === artistId);

  async function drop(appt: ProAppointment, artistId: string, minute: number) {
    const newIso = isoAt(day.date, minute, tz);
    const columnChanged = (appt.artistId ?? '') !== artistId;
    if (newIso === appt.appointmentDate && !columnChanged) return;
    const r = await rescheduleAppointment(
      appt.id,
      newIso,
      columnChanged ? artistId : undefined,
    );
    if (r.ok) {
      onChanged();
    } else {
      onToast(
        r.status === 409
          ? 'Créneau indisponible.'
          : 'Le déplacement a échoué. Réessayez.',
      );
    }
  }

  return (
    <div className="relative">
      <div
        ref={scrollRef}
        // ds-ignore: viewport-relative scroll box.
        // eslint-disable-next-line tailwindcss/no-arbitrary-value
        className="max-h-[70vh] overflow-auto rounded-xl border border-border bg-secondary"
      >
        <div className="flex min-w-fit">
          {/* Time axis */}
          <div
            className="sticky left-0 z-sticky shrink-0 border-r border-border bg-secondary"
            style={{ width: AXIS_W, height: height + 8 }}
          >
            {hourTicks(hours).map((t) => (
              <div
                key={t.label}
                className="absolute -translate-y-1/2 pl-xs text-bodySmall text-textTertiary"
                style={{ top: t.top }}
              >
                {t.label}
              </div>
            ))}
          </div>

          {/* Artist columns */}
          {columns.map((col) => (
            <JournalColumn
              key={col.id || 'none'}
              artist={col}
              appts={byColumn(col.id)}
              openMin={openMin}
              height={height}
              hours={hours}
              nowTop={nowTop}
              readOnly={readOnly}
              onSelect={setSelected}
              onDrop={drop}
              onEmptyClick={(minute) =>
                setQuick({ artistId: col.id, minute })
              }
              colMinW={COL_MIN_W}
              tz={tz}
              currency={currency}
            />
          ))}
        </div>
      </div>

      {selected ? (
        <JournalPanel
          providerId={providerId}
          appt={selected}
          membership={profile.membership}
          tz={tz}
          currency={currency}
          serviceName={(id) =>
            profile.provider.services?.find((s) => s.id === id)?.name
          }
          onClose={() => setSelected(null)}
          onChanged={() => {
            setSelected(null);
            onChanged();
          }}
          onToast={onToast}
        />
      ) : null}

      {quick ? (
        <ManualBookingDialog
          providerId={providerId}
          profile={profile}
          artistId={quick.artistId}
          dateTimeIso={isoAt(day.date, quick.minute, tz)}
          onClose={() => setQuick(null)}
          onCreated={() => {
            setQuick(null);
            onChanged();
          }}
          onToast={onToast}
        />
      ) : null}
    </div>
  );
}

function JournalColumn({
  artist,
  appts,
  openMin,
  height,
  hours,
  nowTop,
  readOnly,
  onSelect,
  onDrop,
  onEmptyClick,
  colMinW,
  tz,
  currency,
}: {
  artist: { id: string; name: string };
  appts: ProAppointment[];
  openMin: number;
  height: number;
  hours: JournalHours;
  nowTop: number | null;
  readOnly: boolean;
  onSelect: (a: ProAppointment) => void;
  onDrop: (a: ProAppointment, artistId: string, minute: number) => void;
  onEmptyClick: (minute: number) => void;
  colMinW: number;
  tz?: string;
  currency?: string;
}) {
  const colRef = useRef<HTMLButtonElement>(null);

  const minuteAt = (clientY: number): number => {
    const rect = colRef.current?.getBoundingClientRect();
    if (!rect) return openMin;
    const y = clientY - rect.top;
    return snapToQuarter(openMin + y / PX_PER_MIN);
  };

  return (
    <div
      className="relative shrink-0 border-r border-border"
      style={{ minWidth: colMinW, height: height + 8 }}
    >
      {/* The children are ordered bottom-to-top ON PURPOSE: surface → header →
          now-line → blocks. They used to say z-[5]/[6]/[7], but no ancestor here
          creates a stacking context (`relative` with z-auto doesn't, and neither
          does `overflow-auto`), so those were GLOBAL layers that merely happened
          to sit under the page's own scale. All four are positioned with z-auto
          now, so paint order = DOM order — the same result, and immune to the
          global scale (WEB-SYSTEM §9). Do not reorder without reading this. */}

      {/* click-to-create surface + break bands (inert when readOnly) */}
      {readOnly ? (
        <div className="absolute inset-x-0" style={{ top: 32, height }}>
          {breakBands(hours).map((b, i) => (
            <div
              key={i}
              // ds-ignore: the break-band hatch is a GRADIENT, not a colour —
              // there is no token shape that can hold it.
              // eslint-disable-next-line tailwindcss/no-arbitrary-value
              className="absolute inset-x-0 bg-[repeating-linear-gradient(45deg,transparent,transparent_6px,rgba(0,0,0,0.04)_6px,rgba(0,0,0,0.04)_12px)]"
              style={{ top: b.top, height: b.height }}
            />
          ))}
        </div>
      ) : (
        <button
          type="button"
          ref={colRef}
          aria-label={`Créer un rendez-vous — ${artist.name}`}
          className="absolute inset-x-0 cursor-copy"
          style={{ top: 32, height }}
          onClick={(e) => onEmptyClick(minuteAt(e.clientY))}
          onDragOver={(e) => e.preventDefault()}
          onDrop={(e) => {
            e.preventDefault();
            const id = e.dataTransfer.getData('text/appt');
            const appt = appts.find((a) => a.id === id) ?? draggingAppt;
            if (appt) onDrop(appt, artist.id, minuteAt(e.clientY));
          }}
        >
          {breakBands(hours).map((b, i) => (
            <div
              key={i}
              // ds-ignore: the break-band hatch is a GRADIENT, not a colour —
              // there is no token shape that can hold it.
              // eslint-disable-next-line tailwindcss/no-arbitrary-value
              className="absolute inset-x-0 bg-[repeating-linear-gradient(45deg,transparent,transparent_6px,rgba(0,0,0,0.04)_6px,rgba(0,0,0,0.04)_12px)]"
              style={{ top: b.top, height: b.height }}
            />
          ))}
        </button>
      )}

      {/* header — the column's only IN-FLOW child, so it still starts at y=0
          despite coming after the absolutes above (they take no flow space). */}
      <div className="sticky top-0 flex h-8 items-center justify-center border-b border-border bg-surface text-labelMedium font-medium text-textPrimary">
        {artist.name}
      </div>

      {/* now line */}
      {nowTop !== null ? (
        <div
          className="pointer-events-none absolute inset-x-0 border-t border-error"
          style={{ top: 32 + nowTop }}
        />
      ) : null}

      {/* blocks */}
      {appts.map((a) => {
        const box = blockBox(a, openMin, tz);
        const draggable = !readOnly && isDraggable(a);
        return (
          <button
            key={a.id}
            type="button"
            draggable={draggable}
            onDragStart={(e) => {
              e.dataTransfer.setData('text/appt', a.id);
              draggingAppt = a;
            }}
            onDragEnd={() => {
              draggingAppt = null;
            }}
            onClick={() => onSelect(a)}
            aria-label={`${a.clientName ?? 'Client'}, ${statusLabelFr(
              statusKey(a),
            )}`}
            // ds-ignore: py-[2px] is below the 4px grid floor — a 15-min block
            // is ~15px tall, so 4px padding would clip the label. (The label is
            // text-labelSmall now; `leading-tight` still overrides the token's
            // 16px line, so the block keeps the 13.75px it has always had.)
            // eslint-disable-next-line tailwindcss/no-arbitrary-value
            className={`absolute inset-x-1 overflow-hidden rounded-md border px-xs py-[2px] text-left text-labelSmall leading-tight ${
              STATUS_STYLE[statusKey(a)] ?? STATUS_STYLE.confirmed
            } ${draggable ? 'cursor-grab' : 'cursor-pointer'}`}
            style={{ top: 32 + box.top, height: box.height }}
          >
            <span className="block font-medium">
              {salonFormatter({ hour: '2-digit', minute: '2-digit' }, tz).format(
                new Date(a.appointmentDate),
              )}{' '}
              {a.clientName ?? 'Client'}
            </span>
            {box.height > 34 ? (
              <span className="block text-textSecondary">
                {typeof a.totalPrice === 'number'
                  ? formatFcfa(a.totalPrice, currency)
                  : ''}
                {a.depositAmount && a.depositAmount > 0 ? ' · ₣' : ''}
              </span>
            ) : null}
          </button>
        );
      })}
    </div>
  );
}
