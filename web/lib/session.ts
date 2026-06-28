import type { NextResponse } from 'next/server';

/// Web session = httpOnly cookies on the Next origin (the BFF sets them after
/// OTP verify). Tokens never reach the browser JS. Design: docs/design/web-m5-booking.md.

export const AT_COOKIE = 'myweli_web_at';
export const RT_COOKIE = 'myweli_web_rt';

// Pro web session — distinct cookie names so consumer + provider never collide.
export const PRO_AT_COOKIE = 'myweli_pro_at';
export const PRO_RT_COOKIE = 'myweli_pro_rt';

const secure = process.env.NODE_ENV === 'production';
const base = {
  httpOnly: true,
  secure,
  sameSite: 'lax' as const,
  path: '/',
};

export function setSessionCookies(
  res: NextResponse,
  accessToken: string,
  refreshToken: string,
): void {
  res.cookies.set(AT_COOKIE, accessToken, { ...base, maxAge: 60 * 15 });
  res.cookies.set(RT_COOKIE, refreshToken, {
    ...base,
    maxAge: 60 * 60 * 24 * 30,
  });
}

export function clearSessionCookies(res: NextResponse): void {
  res.cookies.delete(AT_COOKIE);
  res.cookies.delete(RT_COOKIE);
}

export function setProSessionCookies(
  res: NextResponse,
  accessToken: string,
  refreshToken: string,
): void {
  res.cookies.set(PRO_AT_COOKIE, accessToken, { ...base, maxAge: 60 * 15 });
  res.cookies.set(PRO_RT_COOKIE, refreshToken, {
    ...base,
    maxAge: 60 * 60 * 24 * 30,
  });
}

export function clearProSessionCookies(res: NextResponse): void {
  res.cookies.delete(PRO_AT_COOKIE);
  res.cookies.delete(PRO_RT_COOKIE);
}
