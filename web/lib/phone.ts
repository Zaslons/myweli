import {
  type CountryCode,
  Metadata,
  getCountries,
  getCountryCallingCode,
  isPossiblePhoneNumber,
} from 'libphonenumber-js/min';

/// The one phone rule on the web (docs/design/phone-national-length.md §2.1,
/// §2.5) — the twin of the app's `Validators.phoneNumber` and the server's
/// check, which stays the authority:
///
/// - separators (spaces, dashes, dots, brackets) are not part of a number;
/// - nothing, or a calling code alone (« +225 »), is EMPTY — required asks for
///   a number, optional accepts it and sends '';
/// - a market's number has exactly its national length after the calling code
///   (Côte d'Ivoire: 10 digits since 2021), and the message says so (§14 rule 4);
/// - every other country keeps libphonenumber's verdict, on top of the API's
///   generic E.164 floor.
///
/// **No length is written here.** It is market data (WEB.md « Market data »),
/// read from libphonenumber's `min` metadata — the build react-phone-number-input
/// already ships, so the bundle carries one copy. `tests/phone-numbering-pin.test.ts`
/// holds that metadata, and the market list below, to the backend table
/// (`backend/lib/src/localities/phone_numbering.dart`).

/// The markets whose national length the API enforces — the countries of the
/// backend table, home market first (`PhoneField` opens on it). A country,
/// never a length: the pin test goes red while this list and the backend
/// table disagree.
export const PHONE_MARKETS: readonly CountryCode[] = ['CI'];

export const PHONE_REQUIRED = 'Saisissez un numéro de téléphone.';
export const PHONE_INVALID = 'Saisissez un numéro de téléphone valide.';

/// The server's generic floor (`^\+[1-9]\d{7,14}$`).
const E164 = /^\+[1-9]\d{7,14}$/;

/// Spaces (the NBSP of French formatting included), dots, brackets, dashes.
const SEPARATORS = /[\s.()-]/g;

let callingCodes: Set<string> | null = null;

function isCallingCode(digits: string): boolean {
  callingCodes ??= new Set(getCountries().map((c) => getCountryCallingCode(c)));
  return callingCodes.has(digits);
}

/// The value to SEND: separators stripped, and '' when nothing but a calling
/// code was typed — what is checked is what crosses.
export function normalizePhone(value: string | undefined): string {
  const phone = (value ?? '').replace(SEPARATORS, '');
  if (phone === '+') return '';
  if (phone.startsWith('+') && isCallingCode(phone.slice(1))) return '';
  return phone;
}

function nationalLengths(country: CountryCode): number[] {
  const metadata = new Metadata();
  metadata.selectNumberingPlan(country);
  return metadata.numberingPlan?.possibleLengths() ?? [];
}

/// The field's fault, or null — for `useFieldErrors` (validate on submit,
/// re-validate on change once errored).
export function phoneFieldError(
  value: string | undefined,
  { required }: { required: boolean },
): string | null {
  const phone = normalizePhone(value);
  if (!phone) return required ? PHONE_REQUIRED : null;
  for (const market of PHONE_MARKETS) {
    const code = getCountryCallingCode(market);
    if (!phone.startsWith(`+${code}`)) continue;
    // Calling codes are prefix-free (ITU-T E.164): the first match is the
    // only one.
    const lengths = nationalLengths(market);
    const national = phone.slice(code.length + 1);
    return /^\d+$/.test(national) && lengths.includes(national.length)
      ? null
      : `Le numéro doit comporter ${lengths.join(' ou ')} chiffres après +${code}.`;
  }
  return E164.test(phone) && isPossiblePhoneNumber(phone) ? null : PHONE_INVALID;
}
