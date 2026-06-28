'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { requestOtp, verifyOtp } from '../../lib/booking/client';
import { OtpLoginForm } from './OtpLoginForm';

export function ConnexionClient() {
  const router = useRouter();
  const params = useSearchParams();
  const raw = params.get('returnTo') ?? '/mon-compte';
  // Only allow internal paths (no open redirect).
  const returnTo = raw.startsWith('/') && !raw.startsWith('//') ? raw : '/mon-compte';
  return (
    <OtpLoginForm
      onSuccess={() => router.replace(returnTo)}
      requestCode={requestOtp}
      verifyCode={verifyOtp}
    />
  );
}
