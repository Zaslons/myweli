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
import { JournalPanel } from './JournalPanel';
import { QuickCreatePopover } from './QuickCreatePopover';

let draggingAppt: ProAppointment | null = null;

const AXIS_W = 56;
const COL_MIN_W = 168;

/// The journal day grid (module journal J1 — docs/design/journal-j1-grid.md
/// §3): artist columns, 15-min axis, now-line, drag-reschedule (optimistic,
/// 409 snap-back), click-panel + quick-create. `providerId` owns the data;
/// the backend enforces it.
export function JournalGrid({
  providerId,
  day,
  profile,
  onChanged,
  onToast,
}: {
  providerId: string;
  day: JournalDay;
  profile: ProProfile;
  onChanged: () => void;
  onToast: (msg: string) => void;
}) {
  const hours = day.hours ?? CLOSED_AXIS;
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
    const tick = () => setNowTop(nowLineTop(new Date(), day.date, hours));
    tick();
    const t = setInterval(tick, 60_000);
    return () => clearInterval(t);
  }, [day.date, hours]);

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
    const newIso = isoAt(day.date, minute);
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
        className="max-h-[70vh] overflow-auto rounded-xl border border-border bg-secondary"
      >
        <div className="flex min-w-fit">
          {/* Time axis */}
          <div
            className="sticky left-0 z-10 shrink-0 border-r border-border bg-secondary"
            style={{ width: AXIS_W, height: height + 8 }}
          >
            {hourTicks(hours).map((t) => (
              <div
                key={t.label}
                className="absolute -translate-y-1/2 pl-xs text-xs text-textTertiary"
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
              onSelect={setSelected}
              onDrop={drop}
              onEmptyClick={(minute) =>
                setQuick({ artistId: col.id, minute })
              }
              colMinW={COL_MIN_W}
            />
          ))}
        </div>
      </div>

      {selected ? (
        <JournalPanel
          providerId={providerId}
          appt={selected}
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
        <QuickCreatePopover
          providerId={providerId}
          profile={profile}
          artistId={quick.artistId}
          dateTimeIso={isoAt(day.date, quick.minute)}
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
  onSelect,
  onDrop,
  onEmptyClick,
  colMinW,
}: {
  artist: { id: string; name: string };
  appts: ProAppointment[];
  openMin: number;
  height: number;
  hours: JournalHours;
  nowTop: number | null;
  onSelect: (a: ProAppointment) => void;
  onDrop: (a: ProAppointment, artistId: string, minute: number) => void;
  onEmptyClick: (minute: number) => void;
  colMinW: number;
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
      {/* header */}
      <div className="sticky top-0 z-[5] flex h-8 items-center justify-center border-b border-border bg-surface text-xs font-medium text-textPrimary">
        {artist.name}
      </div>

      {/* click-to-create surface + break bands */}
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
            className="absolute inset-x-0 bg-[repeating-linear-gradient(45deg,transparent,transparent_6px,rgba(0,0,0,0.04)_6px,rgba(0,0,0,0.04)_12px)]"
            style={{ top: b.top, height: b.height }}
          />
        ))}
      </button>

      {/* now line */}
      {nowTop !== null ? (
        <div
          className="pointer-events-none absolute inset-x-0 z-[6] border-t border-error"
          style={{ top: 32 + nowTop }}
        />
      ) : null}

      {/* blocks */}
      {appts.map((a) => {
        const box = blockBox(a, openMin);
        const draggable = isDraggable(a);
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
            className={`absolute inset-x-1 z-[7] overflow-hidden rounded-md border px-1 py-0.5 text-left text-[11px] leading-tight ${
              STATUS_STYLE[statusKey(a)] ?? STATUS_STYLE.confirmed
            } ${draggable ? 'cursor-grab' : 'cursor-pointer'}`}
            style={{ top: 32 + box.top, height: box.height }}
          >
            <span className="block font-medium">
              {new Date(a.appointmentDate).toISOString().slice(11, 16)}{' '}
              {a.clientName ?? 'Client'}
            </span>
            {box.height > 34 ? (
              <span className="block text-textSecondary">
                {typeof a.totalPrice === 'number' ? formatFcfa(a.totalPrice) : ''}
                {a.depositAmount && a.depositAmount > 0 ? ' · ₣' : ''}
              </span>
            ) : null}
          </button>
        );
      })}
    </div>
  );
}
