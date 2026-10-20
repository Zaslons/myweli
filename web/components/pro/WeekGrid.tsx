"use client";

import { useMemo, useRef, useState } from "react";
import { statusLabelFr } from "../../lib/account/appointments";
import type { ProProfile } from "../../lib/api/pro";
import { rescheduleAppointment } from "../../lib/api/pro";
import { conflictMessage } from "../../lib/booking/window";
import {
  type JournalDay,
  PX_PER_MIN,
  STATUS_STYLE,
  axisHeight,
  blockBox,
  hourTicks,
  isDraggable,
  isoAt,
  nowLineTop,
  parseHhmm,
  snapToQuarter,
  statusKey,
} from "../../lib/pro/journal";
import type { ProAppointment } from "../../lib/pro/today";
import { weekStripDay, weekStripLabel } from "../../lib/pro/week-strip";
import { dayBands, filterArtist, lanesFor, weekAxis } from "../../lib/pro/week-view";
import { salonFormatter } from "../../lib/time";
import { JournalPanel } from "./JournalPanel";
import { ManualBookingDialog } from "./ManualBookingDialog";

let draggingAppt: ProAppointment | null = null;

const AXIS_W = 56;
/// Seven of these and the axis fit a desktop main pane; narrower, the table
/// scrolls inside its own box, never the page.
const DAY_MIN_W = 112;

/// The « Semaine » grid (docs/design/web-pro-week-view.md, owner decisions
/// 2026-10-20): one column per day on one axis, the artists side by side in
/// lanes, the Journée's panel, click-to-create and drag to another day or
/// time. An ARIA **table** — a header row of days, one row of day cells — not
/// a `grid`, which would promise arrow-key moves between cells.
export function WeekGrid({
  providerId,
  days,
  profile,
  readOnly = false,
  artistFilter,
  showCancelled,
  onChanged,
  onToast,
  bookingQuery = "",
}: {
  providerId: string;
  /// Monday → Sunday, each the Journée's read of that day.
  days: JournalDay[];
  profile: ProProfile;
  readOnly?: boolean;
  /// null = « Tous »; '' = « Sans artiste ».
  artistFilter: string | null;
  showCancelled: boolean;
  onChanged: () => void;
  onToast: (msg: string) => void;
  bookingQuery?: string;
}) {
  const tz = profile.provider.timezone ?? undefined;
  const currency = profile.provider.currency ?? undefined;
  const axis = useMemo(() => weekAxis(days), [days]);
  const axisOpen = parseHhmm(axis.open);
  const height = axisHeight(axis);
  const today = salonFormatter(
    { year: "numeric", month: "2-digit", day: "2-digit" },
    tz,
    "en-CA",
  ).format(new Date());
  const artistName = useMemo(() => {
    const m = new Map<string, string>();
    for (const d of days) for (const a of d.artists) m.set(a.id, a.name);
    return (id?: string | null) => (id ? (m.get(id) ?? "Sans artiste") : "Sans artiste");
  }, [days]);

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const selected =
    days.flatMap((d) => d.appointments).find((a) => a.id === selectedId) ?? null;
  const [quick, setQuick] = useState<{ dayKey: string; minute: number } | null>(null);

  const shown = (d: JournalDay) =>
    filterArtist(
      d.appointments.filter((a) => showCancelled || a.status !== "cancelled"),
      artistFilter,
    );

  async function drop(appt: ProAppointment, dayKey: string, minute: number) {
    const newIso = isoAt(dayKey, minute, tz);
    if (newIso === appt.appointmentDate) return;
    // The artist is kept: a week column is a day, not an artist.
    const r = await rescheduleAppointment(appt.id, newIso);
    if (r.ok) {
      onChanged();
    } else {
      onToast(
        conflictMessage(r.error, {
          audience: "salon",
          taken: "Créneau indisponible.",
          fallback: "Le déplacement a échoué. Réessayez.",
        }),
      );
    }
  }

  return (
    <div className="relative">
      <div
        role="table"
        aria-label={weekStripLabel(days.map((d) => d.date), tz)}
        // ds-ignore: viewport-relative scroll box (the Journée's).
        // eslint-disable-next-line tailwindcss/no-arbitrary-value
        className="max-h-[70vh] overflow-auto rounded-xl border border-border bg-secondary"
      >
        <div role="row" className="sticky top-0 z-sticky flex min-w-fit border-b border-border bg-surface">
          <div aria-hidden="true" className="shrink-0" style={{ width: AXIS_W }} />
          {days.map((d) => {
            const w = weekStripDay(d.date, 0, false, tz);
            const isToday = d.date === today;
            return (
              <div
                key={d.date}
                role="columnheader"
                className={`flex h-8 flex-1 items-center justify-center border-l border-border text-labelMedium font-medium ${
                  isToday ? "text-textPrimary underline" : "text-textPrimary"
                }`}
                style={{ minWidth: DAY_MIN_W }}
              >
                {`${w.short} ${w.day}`}
              </div>
            );
          })}
        </div>
        <div role="row" className="flex min-w-fit">
          <div
            aria-hidden="true"
            className="sticky left-0 z-sticky shrink-0 border-r border-border bg-secondary"
            style={{ width: AXIS_W, height: height + 8 }}
          >
            {hourTicks(axis).map((t) => (
              <div
                key={t.label}
                className="absolute -translate-y-1/2 pl-xs text-bodySmall text-textTertiary"
                style={{ top: t.top }}
              >
                {t.label}
              </div>
            ))}
          </div>
          {days.map((d) => (
            <DayColumn
              key={d.date}
              day={d}
              appts={shown(d)}
              axisOpen={axisOpen}
              height={height}
              bands={dayBands(d, axis)}
              nowTop={nowLineTop(new Date(), d.date, axis, tz)}
              readOnly={readOnly}
              tz={tz}
              artistName={artistName}
              onSelect={(a) => setSelectedId(a.id)}
              onDrop={drop}
              onEmptyClick={(minute) => setQuick({ dayKey: d.date, minute })}
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
          serviceName={(id) => profile.provider.services?.find((s) => s.id === id)?.name}
          onClose={() => setSelectedId(null)}
          onChanged={() => {
            setSelectedId(null);
            onChanged();
          }}
          onToast={onToast}
          bookingQuery={bookingQuery}
        />
      ) : null}

      {quick ? (
        <ManualBookingDialog
          providerId={providerId}
          profile={profile}
          artistId={artistFilter ?? ""}
          dateTimeIso={isoAt(quick.dayKey, quick.minute, tz)}
          onClose={() => setQuick(null)}
          onCreated={() => {
            setQuick(null);
            onChanged();
          }}
        />
      ) : null}
    </div>
  );
}

function DayColumn({
  day,
  appts,
  axisOpen,
  height,
  bands,
  nowTop,
  readOnly,
  tz,
  artistName,
  onSelect,
  onDrop,
  onEmptyClick,
}: {
  day: JournalDay;
  appts: ProAppointment[];
  axisOpen: number;
  height: number;
  bands: { top: number; height: number }[];
  nowTop: number | null;
  readOnly: boolean;
  tz?: string;
  artistName: (id?: string | null) => string;
  onSelect: (a: ProAppointment) => void;
  onDrop: (a: ProAppointment, dayKey: string, minute: number) => void;
  onEmptyClick: (minute: number) => void;
}) {
  const surfaceRef = useRef<HTMLButtonElement>(null);
  const w = weekStripDay(day.date, 0, false, tz);
  const dayName = `${w.short} ${w.day}`;
  const closed = day.hours == null;
  const lanes = lanesFor(appts, tz);
  const time = salonFormatter({ hour: "2-digit", minute: "2-digit" }, tz);

  const minuteAt = (clientY: number): number => {
    const rect = surfaceRef.current?.getBoundingClientRect();
    // A pointer event without a position (jsdom's drag events) must not
    // become an Invalid Date: it lands at the axis top.
    const y = rect && Number.isFinite(clientY) ? clientY - rect.top : 0;
    return snapToQuarter(axisOpen + Math.max(0, y) / PX_PER_MIN);
  };

  const hatch = bands.map((b, i) => (
    <div
      key={i}
      // ds-ignore: the closed/break hatch is a GRADIENT, not a colour —
      // there is no token shape that can hold it (the Journée's).
      // eslint-disable-next-line tailwindcss/no-arbitrary-value
      className="pointer-events-none absolute inset-x-0 bg-[repeating-linear-gradient(45deg,transparent,transparent_6px,rgba(0,0,0,0.04)_6px,rgba(0,0,0,0.04)_12px)]"
      style={{ top: b.top, height: b.height }}
    />
  ));

  return (
    <div
      role="cell"
      className="relative flex-1 border-l border-border"
      style={{ minWidth: DAY_MIN_W, height: height + 8 }}
    >
      {/* Paint order = DOM order (no z-index here — WEB-SYSTEM §9, as in the
          Journée): surface → now-line → blocks. */}
      {readOnly || closed ? (
        <div className="absolute inset-x-0 top-0" style={{ height }}>
          {hatch}
        </div>
      ) : (
        <button
          type="button"
          ref={surfaceRef}
          aria-label={`Créer un rendez-vous — ${dayName}`}
          className="absolute inset-x-0 top-0 cursor-copy"
          style={{ height }}
          onClick={(e) => onEmptyClick(minuteAt(e.clientY))}
          onDragOver={(e) => e.preventDefault()}
          onDrop={(e) => {
            e.preventDefault();
            // The booking comes from ANY day's column: the dragged one is
            // held at module level (the Journée's idiom), checked by its id.
            const id = e.dataTransfer.getData("text/appt");
            const appt = draggingAppt;
            if (appt && appt.id === id) onDrop(appt, day.date, minuteAt(e.clientY));
          }}
        >
          {hatch}
        </button>
      )}
      {closed ? (
        <p className="pointer-events-none absolute inset-x-0 top-s text-center text-bodySmall text-textTertiary">
          Fermé
        </p>
      ) : null}

      {nowTop !== null ? (
        <div
          className="pointer-events-none absolute inset-x-0 border-t border-error"
          style={{ top: nowTop }}
        />
      ) : null}

      {appts.map((a) => {
        const box = blockBox(a, axisOpen, tz);
        const lane = lanes.get(a.id) ?? { lane: 0, lanes: 1 };
        const draggable = !readOnly && isDraggable(a);
        const client = a.clientDisplayName ?? a.clientName ?? "Client";
        const artist = artistName(a.artistId);
        const at = time.format(new Date(a.appointmentDate));
        return (
          <button
            key={a.id}
            type="button"
            draggable={draggable}
            onDragStart={(e) => {
              e.dataTransfer.setData("text/appt", a.id);
              draggingAppt = a;
            }}
            onDragEnd={() => {
              draggingAppt = null;
            }}
            onClick={() => onSelect(a)}
            aria-label={`${client}, ${statusLabelFr(statusKey(a))} — ${artist}, ${dayName} à ${at}`}
            className={`absolute overflow-hidden rounded-md border px-xs text-left text-labelSmall leading-tight ${
              STATUS_STYLE[statusKey(a)] ?? STATUS_STYLE.confirmed
            } ${draggable ? "cursor-grab" : "cursor-pointer"}`}
            style={{
              top: box.top,
              height: box.height,
              left: `calc(${(lane.lane / lane.lanes) * 100}% + 2px)`,
              width: `calc(${100 / lane.lanes}% - 4px)`,
            }}
          >
            <span className="block font-medium">
              {at} {client}
            </span>
            <span className="block text-textSecondary">{artist}</span>
          </button>
        );
      })}
    </div>
  );
}
