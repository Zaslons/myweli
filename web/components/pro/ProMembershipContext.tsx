'use client';

import { usePathname, useRouter } from 'next/navigation';
import {
  type ReactNode,
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from 'react';
import { getMyProvider, logoutPro } from '../../lib/api/pro';
import { type Membership, type TeamRole, hasCap } from '../../lib/pro/team';

/// The membership context over the pro dashboard (team access R5b —
/// docs/design/web-team-access-r5.md §2.4). Fetches /api/pro/me on mount and
/// on EVERY pathname change — that re-fetch IS the revocation probe (threat
/// T38): a revoked member's next navigation hits `403 not_a_member` → sign
/// out → /pro/connexion?motif=acces-retire (no PII in the URL).
///
/// Pages keep gating off their OWN getMyProvider payload; this context powers
/// the sidebar + the probe only. UI gating stays convenience — the server
/// 403s regardless.

type ProMembershipValue = {
  loading: boolean;
  /// null = legacy owner-shaped payload (no membership block).
  membership: Membership | null;
  role: TeamRole | null;
  salonName: string;
  providerId: string | null;
  email: string | null;
  can: (cap: string) => boolean;
  refresh: () => Promise<void>;
};

const ProMembershipContext = createContext<ProMembershipValue | null>(null);

export function useProMembership(): ProMembershipValue {
  const ctx = useContext(ProMembershipContext);
  if (!ctx) {
    throw new Error('useProMembership requires <ProMembershipProvider>');
  }
  return ctx;
}

export function ProMembershipProvider({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [loading, setLoading] = useState(true);
  const [membership, setMembership] = useState<Membership | null>(null);
  const [salonName, setSalonName] = useState('');
  const [providerId, setProviderId] = useState<string | null>(null);
  const [email, setEmail] = useState<string | null>(null);
  // Serialize probes: only the latest one may commit state.
  const probeSeq = useRef(0);

  const probe = useCallback(async () => {
    const seq = ++probeSeq.current;
    const r = await getMyProvider();
    if (seq !== probeSeq.current) return;
    if (r.status === 403 && r.error === 'not_a_member') {
      // Revoked mid-session: drop the cookies, land on the login screen
      // with the generic banner (the salon name never travels in the URL).
      await logoutPro();
      router.replace('/pro/connexion?motif=acces-retire');
      return;
    }
    if (r.status === 200 && r.profile) {
      setMembership(r.profile.membership ?? null);
      setSalonName(r.profile.provider.name || '');
      setProviderId(r.profile.provider.id);
      setEmail(r.profile.account.email ?? null);
    }
    // 401 → the page-level guards own the plain redirect (avoid racing two
    // router.replace calls); other errors keep the last known state so a
    // transient failure never locks the UI.
    setLoading(false);
  }, [router]);

  useEffect(() => {
    probe();
  }, [probe, pathname]);

  const can = useCallback(
    (cap: string) => hasCap(membership, cap),
    [membership],
  );

  return (
    <ProMembershipContext.Provider
      value={{
        loading,
        membership,
        role: (membership?.role as TeamRole | undefined) ?? null,
        salonName,
        providerId,
        email,
        can,
        refresh: probe,
      }}
    >
      {children}
    </ProMembershipContext.Provider>
  );
}
