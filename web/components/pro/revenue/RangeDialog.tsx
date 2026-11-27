'use client';

import { useState } from 'react';
import { Button } from '../../Button';
import { Modal } from '../../Modal';
import { TextField } from '../../TextField';
import {
  REVENUE_EARLIEST_DAY,
  customRangeError,
  isRevenueDay,
} from '../../../lib/pro/revenue';

/// « Dates… » (docs/design/pro-revenue-analytics.md §4.3, §5.1): two labelled
/// date fields, « Du » and « Au », bounded by the server's own limits
/// (2020-01-01 → the salon's today + 366 days). A range backwards or over
/// 366 days shows its error **under « Au »**, tied to the field — never a
/// toast. The shared Modal traps and restores focus.
export function RangeDialog({
  initialFrom,
  initialTo,
  latest,
  onApply,
  onClose,
}: {
  initialFrom: string;
  initialTo: string;
  /// The last day the server accepts.
  latest: string;
  onApply: (from: string, to: string) => void;
  onClose: () => void;
}) {
  const [from, setFrom] = useState(initialFrom);
  const [to, setTo] = useState(initialTo);
  const [tried, setTried] = useState(false);

  const fromError =
    tried && !isRevenueDay(from)
      ? 'Choisissez une date'
      : tried && (from < REVENUE_EARLIEST_DAY || from > latest)
        ? 'Date hors de la période possible'
        : undefined;
  const toError =
    tried && !isRevenueDay(to)
      ? 'Choisissez une date'
      : tried && (to < REVENUE_EARLIEST_DAY || to > latest)
        ? 'Date hors de la période possible'
        : isRevenueDay(from) && isRevenueDay(to)
          ? (customRangeError(from, to) ?? undefined)
          : undefined;

  function apply() {
    setTried(true);
    if (
      !isRevenueDay(from) ||
      !isRevenueDay(to) ||
      from < REVENUE_EARLIEST_DAY ||
      to > latest ||
      customRangeError(from, to) != null
    ) {
      return;
    }
    onApply(from, to);
  }

  return (
    <Modal title="Choisir les dates" onClose={onClose}>
      <form
        className="mt-m space-y-m"
        noValidate
        onSubmit={(e) => {
          e.preventDefault();
          apply();
        }}
      >
        <TextField
          label="Du"
          type="date"
          value={from}
          min={REVENUE_EARLIEST_DAY}
          max={latest}
          onChange={(e) => setFrom(e.target.value)}
          error={fromError}
        />
        <TextField
          label="Au"
          type="date"
          value={to}
          min={REVENUE_EARLIEST_DAY}
          max={latest}
          onChange={(e) => setTo(e.target.value)}
          error={toError}
        />
        <div className="flex flex-wrap justify-end gap-s">
          <Button type="button" variant="text" onClick={onClose}>
            Annuler
          </Button>
          <Button type="submit">Afficher</Button>
        </div>
      </form>
    </Modal>
  );
}
