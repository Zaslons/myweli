'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { safeReturnTo } from '../../lib/auth/return-to';
import { LoginOptions } from './LoginOptions';

export function ConnexionClient() {
  const router = useRouter();
  const params = useSearchParams();
  const raw = params.get('returnTo');
  // A page of this site only (no open redirect) — resolved in the browser,
  // where the origin is known (lib/auth/return-to.ts).
  return (
    <LoginOptions
      onSuccess={() => router.replace(safeReturnTo(raw, window.location.origin))}
    />
  );
}
