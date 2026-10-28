import { parsePhoneNumberFromString } from 'libphonenumber-js/max';
import { AppError } from './errors.ts';

export function normalizePhone(input: string, defaultCountry: 'BR' = 'BR'): string {
  const raw = input.trim();
  const parse = (s: string) => {
    const p = parsePhoneNumberFromString(s, defaultCountry);
    return p?.isValid() ? p : undefined;
  };
  // Bare 12-15 digits are tried as international first, then as national (e.g. "011987654321").
  const p = (/^\d{12,15}$/.test(raw) && parse(`+${raw}`)) || parse(raw);
  if (!p) throw new AppError('invalid_phone');
  return p.number.slice(1);
}
