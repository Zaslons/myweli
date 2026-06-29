'use client';

import { useMemo, useState } from 'react';
import { getCountries, getCountryCallingCode } from 'react-phone-number-input';

type CountryCode = ReturnType<typeof getCountries>[number];
const regionNames = new Intl.DisplayNames(['fr'], { type: 'region' });

/// Phone entry with a country-code picker (defaults to Côte d'Ivoire, +225 —
/// users can pick any country). Emits the full **E.164** (or '' when cleared).
/// The React parity of the mobile `PhoneNumberField`: plain controlled inputs
/// (so it's predictable + themed to the app), with country names via
/// `Intl.DisplayNames` and dial codes/validation via libphonenumber-js.
export function PhoneField({
  onChange,
  disabled,
}: {
  onChange: (e164: string) => void;
  disabled?: boolean;
}) {
  const countries = useMemo(
    () =>
      getCountries()
        .map((c) => ({
          code: c,
          name: regionNames.of(c) ?? c,
          dial: getCountryCallingCode(c),
        }))
        .sort((a, b) => a.name.localeCompare(b.name, 'fr')),
    [],
  );
  const [country, setCountry] = useState<CountryCode>('CI');
  const [national, setNational] = useState('');

  function emit(c: CountryCode, n: string) {
    const digits = n.replace(/\D/g, '');
    onChange(digits ? `+${getCountryCallingCode(c)}${digits}` : '');
  }

  return (
    <div className="flex gap-s">
      <select
        aria-label="Indicatif pays"
        value={country}
        disabled={disabled}
        onChange={(e) => {
          const c = e.target.value as CountryCode;
          setCountry(c);
          emit(c, national);
        }}
        className="max-w-[9rem] rounded-lg border border-border bg-surface px-s py-s text-textPrimary"
      >
        {countries.map((c) => (
          <option key={c.code} value={c.code}>
            {c.name} (+{c.dial})
          </option>
        ))}
      </select>
      <input
        type="tel"
        inputMode="tel"
        placeholder="07 00 00 00 00"
        value={national}
        disabled={disabled}
        onChange={(e) => {
          setNational(e.target.value);
          emit(country, e.target.value);
        }}
        className="flex-1 rounded-lg border border-border bg-surface px-m py-s text-textPrimary"
      />
    </div>
  );
}
