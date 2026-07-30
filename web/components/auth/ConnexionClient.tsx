'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { LoginOptions } from './LoginOptions';

export function ConnexionClient() {
  const router = useRouter();
  const params = useSearchParams();
  const raw = params.get('returnTo') ?? '/mon-compte';
  // Only allow internal paths (no open redirect).
  const returnTo = raw.startsWith('/') && !raw.startsWith('//') ? raw : '/mon-compte';
  return <LoginOptions onSuccess={() => router.replace(returnTo)} />;
}
