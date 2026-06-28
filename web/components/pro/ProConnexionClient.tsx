'use client';

import { useRouter } from 'next/navigation';
import { requestOtpPro, verifyOtpPro } from '../../lib/api/pro';
import { OtpLoginForm } from '../auth/OtpLoginForm';

export function ProConnexionClient() {
  const router = useRouter();
  return (
    <OtpLoginForm
      onSuccess={() => router.replace('/pro')}
      requestCode={requestOtpPro}
      verifyCode={verifyOtpPro}
      verifyErrorMessage={(e) =>
        e === 'provider_not_found'
          ? 'Compte introuvable. Inscrivez-vous dans l’app Myweli Pro.'
          : 'Code incorrect ou expiré.'
      }
    />
  );
}
