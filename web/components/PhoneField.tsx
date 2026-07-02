'use client';

import 'react-phone-number-input/style.css';
import { useState } from 'react';
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
export function PhoneField({
  onChange,
  disabled,
  initialValue,
}: {
  onChange: (e164: string) => void;
  disabled?: boolean;
  /** Prefill with an E.164 value (e.g. the profile's contact phone). */
  initialValue?: string;
}) {
  const [value, setValue] = useState<string | undefined>(initialValue);

  return (
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
      className="myweli-phone"
      placeholder="07 00 00 00 00"
    />
  );
}
