'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { teamErrorMessage } from '../../lib/pro/team';
import { ProLoginOptions } from './ProLoginOptions';

/// The salon login client. `?motif=acces-retire` (team access R5b) is the
/// revoked-mid-session landing — a generic banner, no salon name in the URL.
export function ProConnexionClient() {
  const router = useRouter();
  const revoked = useSearchParams().get('motif') === 'acces-retire';
  return (
    <div className="flex flex-col gap-s">
      {revoked ? (
        <p
          role="alert"
          className="rounded-lg border border-error/40 bg-error/10 p-m text-sm text-error"
        >
          {teamErrorMessage('not_a_member')}
        </p>
      ) : null}
      <ProLoginOptions onSuccess={() => router.replace('/pro')} />
    </div>
  );
}
