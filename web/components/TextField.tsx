'use client';

import type { InputHTMLAttributes, TextareaHTMLAttributes } from 'react';
import { useId } from 'react';

/// The shared text field — §10's "single highest-value primitive", and the web
/// parity of the app's `AppTextField` (docs/design/web-b4-controls.md).
///
/// Why it exists: before B4 the app had 7+ ad-hoc input copies and, measured
/// across ~105 real controls, `htmlFor` = 0, `aria-invalid` = 0,
/// `aria-describedby` = 0 — not one error was programmatically tied to its
/// field, and every input wore the decorative 1.44:1 `border` instead of §3.3's
/// mandatory `borderStrong`. One primitive is how that stays fixed.
///
/// The state table is mobile's `InputDecorationTheme`, ported: enabled =
/// borderStrong · focused = borderFocus + a 1px ring (the ring fakes mobile's
/// 2nd border pixel *outside* the border-box — zero layout shift) · error =
/// error (+ring when focused) · disabled = soft `border`, receding below
/// enabled. The global §5 :focus-visible ring composes on top at 2px offset for
/// keyboard focus — both indicators are intended (§3.3 designed the offset so
/// they never merge).
///
/// §14 contract: `error` renders under the field, persists until fixed, and is
/// announced (`role="alert"`) and associated (`aria-invalid` +
/// `aria-describedby`, error id first, hint id second). A placeholder is never
/// the label — it may only supplement one ("07 00 00 00 00" as a format
/// example). Optional fields say so in the label: « Note (optionnelle) ».
type Shared = {
  /** The visible French label. Required — a placeholder is not a label (§6). */
  label: string;
  /** Render the label sr-only (the hero search, date/time grid cells) — the
   *  accessible name stays, the pixels don't move. */
  hideLabel?: boolean;
  /** Persistent helper text under the field (swapped below the error, both
   *  referenced by aria-describedby while present). */
  hint?: string;
  /** The field-level fault (§14). Truthy = aria-invalid + role="alert". */
  error?: string | null;
  id?: string;
  className?: string;
};

type Props = Shared &
  (
    | ({ multiline?: false } & InputHTMLAttributes<HTMLInputElement>)
    | ({ multiline: true } & TextareaHTMLAttributes<HTMLTextAreaElement>)
  );

export function TextField({
  label,
  hideLabel = false,
  hint,
  error,
  id: idProp,
  className = '',
  multiline,
  ...rest
}: Props) {
  const autoId = useId();
  const id = idProp ?? autoId;
  const hintId = `${id}-hint`;
  const errorId = `${id}-error`;
  const describedBy =
    [error ? errorId : null, hint ? hintId : null]
      .filter(Boolean)
      .join(' ') || undefined;

  const field = [
    'mt-xs w-full min-h-12 rounded-lg border bg-surface p-m text-bodyMedium',
    'text-textPrimary placeholder:text-textTertiary',
    'disabled:border-border disabled:text-textDisabled',
    error
      ? 'border-error focus:border-error focus:ring-1 focus:ring-error'
      : 'border-borderStrong focus:border-borderFocus focus:ring-1 focus:ring-borderFocus',
  ].join(' ');

  return (
    <div className={className}>
      <label
        htmlFor={id}
        className={
          hideLabel ? 'sr-only' : 'block text-labelMedium text-textSecondary'
        }
      >
        {label}
      </label>
      {multiline ? (
        <textarea
          id={id}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          className={field}
          {...(rest as TextareaHTMLAttributes<HTMLTextAreaElement>)}
        />
      ) : (
        <input
          id={id}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          className={field}
          {...(rest as InputHTMLAttributes<HTMLInputElement>)}
        />
      )}
      {error ? (
        <p id={errorId} role="alert" className="mt-xs text-bodySmall text-error">
          {error}
        </p>
      ) : null}
      {hint ? (
        <p id={hintId} className="mt-xs text-bodyMedium text-textTertiary">
          {hint}
        </p>
      ) : null}
    </div>
  );
}
