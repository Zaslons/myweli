'use client';

import 'react-phone-number-input/style.css';
import { useId, useState } from 'react';
import PhoneInput from 'react-phone-number-input';
import fr from 'react-phone-number-input/locale/fr.json';

/// Phone entry with a country picker — the React parity of the mobile
/// `PhoneNumberField`. Defaults to Côte d'Ivoire (🇨🇮 +225) but any country can
/// be picked or typed (`+225` / `+33` auto-selects the country). Emits the full
/// **E.164** (or '' when cleared).
///
/// Backed by `react-phone-number-input` (libphonenumber), so each country's
/// national format — including the trunk `0` that France/UK strip but Côte
/// d'Ivoire keeps — is parsed correctly into E.164. A hand-rolled concatenation
/// can't do that, so we lean on the engine.
///
/// B4 gives it the same shell as `<TextField>` — a real `<label htmlFor>` and
/// §6's error wiring. The library spreads unrecognised props onto its inner
/// number `<input>` (verified in PhoneInputWithCountry.js:443), so `id`,
/// `aria-invalid` and `aria-describedby` land on the control itself. The
/// placeholder "07 00 00 00 00" survives as a FORMAT EXAMPLE under the label —
/// the one legitimate placeholder role (§6). The field's own visual states live
/// in `.myweli-phone` (globals.css): borderStrong → borderFocus + 1px ring,
/// 48px min-height, and the country select's hand-written focus ring (it is an
/// invisible zero-opacity overlay, so the global ring cannot show on it — CSS on the
/// sibling icon is the only way it can show focus).
export function PhoneField({
  onChange,
  disabled,
  initialValue,
  label = 'Numéro de téléphone',
  hint,
  error,
  id: idProp,
}: {
  onChange: (e164: string) => void;
  disabled?: boolean;
  /** Prefill with an E.164 value (e.g. the profile's contact phone). */
  initialValue?: string;
  /** The visible French label — a placeholder is not a label (§6). */
  label?: string;
  hint?: string;
  error?: string | null;
  id?: string;
}) {
  const [value, setValue] = useState<string | undefined>(initialValue);
  const autoId = useId();
  const id = idProp ?? autoId;
  const hintId = `${id}-hint`;
  const errorId = `${id}-error`;
  const describedBy =
    [error ? errorId : null, hint ? hintId : null]
      .filter(Boolean)
      .join(' ') || undefined;

  return (
    <div>
      <label htmlFor={id} className="block text-labelMedium text-textSecondary">
        {label}
      </label>
      <PhoneInput
        international
        defaultCountry="CI"
        labels={fr}
        value={value}
        disabled={disabled}
        onChange={(v) => {
          setValue(v);
          onChange(v ?? '');
        }}
        className="myweli-phone mt-xs"
        placeholder="07 00 00 00 00"
        id={id}
        aria-invalid={error ? true : undefined}
        aria-describedby={describedBy}
      />
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
