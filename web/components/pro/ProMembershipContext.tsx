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
import {
  type ProProfile,
  getMyProvider,
  getMySalons,
  logoutPro,
  selectSalon,
} from '../../lib/api/pro';
import {
  type Membership,
  type SalonMembership,
  type TeamRole,
  hasCap,
} from '../../lib/pro/team';

/// The membership context over the pro dashboard (team access R5b —
/// docs/design/web-team-access-r5.md §2.4). Fetches /api/pro/me on mount and
/// on EVERY pathname change — that re-fetch IS the revocation probe (threat
/// T38): a revoked member's next navigation hits `403 not_a_member` → sign
/// out → /pro/connexion?motif=acces-retire (no PII in the URL).
///
/// R6 multi-salons: the context also carries « Mes salons » + the switcher.
/// The selection lives in an httpOnly cookie the BFF threads as `?salonId=`;
/// a per-salon `403 forbidden` on the probe (revoked from the SELECTED salon)
/// clears the selection and falls back to the default salon — NEVER a
/// sign-out. A successful switch bumps [switchEpoch], which re-keys the page
/// subtree so every page client remounts and refetches for the new salon.
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
  /// « Mes salons » (R6): every membership, owned first.
  salons: SalonMembership[];
  /// Server-computed « Ajouter un salon » gate (live Réseau on an owned salon).
  canAddSalon: boolean;
  /// Bumped on each successful switch — the layout re-keys the pages on it.
  switchEpoch: number;
  can: (cap: string) => boolean;
  switchSalon: (salonId: string) => Promise<boolean>;
  refresh: () => Promise<void>;
  refreshSalons: () => Promise<void>;
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
  const [salons, setSalons] = useState<SalonMembership[]>([]);
  const [canAdd, setCanAdd] = useState(false);
  const [switchEpoch, setSwitchEpoch] = useState(0);
  // Serialize probes: only the latest one may commit state.
  const probeSeq = useRef(0);

  const commitProfile = useCallback((profile: ProProfile) => {
    setMembership(profile.membership ?? null);
    setSalonName(profile.provider.name || '');
    setProviderId(profile.provider.id);
    setEmail(profile.account.email ?? null);
  }, []);

  const refreshSalons = useCallback(async () => {
    const r = await getMySalons();
    if (r.status === 200) {
      setSalons(r.items);
      setCanAdd(r.canAddSalon);
    }
  }, []);

  const probe = useCallback(async () => {
    const seq = ++probeSeq.current;
    let r = await getMyProvider();
    if (seq !== probeSeq.current) return;
    if (r.status === 403 && r.error === 'forbidden') {
      // R6: a per-salon denial — the SELECTED salon revoked us (or vanished).
      // Clear the selection once and retry on the default salon; the session
      // survives. (A repeat 403 falls through to the error-keeping branch.)
      await selectSalon(null);
      r = await getMyProvider();
      if (seq !== probeSeq.current) return;
      if (r.status === 200) void refreshSalons();
    }
    if (r.status === 403 && r.error === 'not_a_member') {
      // Revoked mid-session: drop the cookies, land on the login screen
      // with the generic banner (the salon name never travels in the URL).
      await logoutPro();
      router.replace('/pro/connexion?motif=acces-retire');
      return;
    }
    if (r.status === 200 && r.profile) {
      commitProfile(r.profile);
    }
    // 401 → the page-level guards own the plain redirect (avoid racing two
    // router.replace calls); other errors keep the last known state so a
    // transient failure never locks the UI.
    setLoading(false);
  }, [router, commitProfile, refreshSalons]);

  useEffect(() => {
    probe();
  }, [probe, pathname]);

  // « Mes salons » loads once at mount (then on demand — switch/add).
  useEffect(() => {
    refreshSalons();
  }, [refreshSalons]);

  const switchSalon = useCallback(
    async (salonId: string) => {
      const r = await selectSalon(salonId);
      if (r.ok && r.profile) {
        commitProfile(r.profile);
        // Re-key the page subtree: every page client remounts and refetches
        // for the new salon (zero per-page wiring).
        setSwitchEpoch((e) => e + 1);
        void refreshSalons();
        return true;
      }
      // Refused (revoked there since the list loaded / unknown) — refresh
      // the list; the current salon stays.
      void refreshSalons();
      return false;
    },
    [commitProfile, refreshSalons],
  );

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
        salons,
        canAddSalon: canAdd,
        switchEpoch,
        can,
        switchSalon,
        refresh: probe,
        refreshSalons,
      }}
    >
      <div key={switchEpoch} className="contents">
        {children}
      </div>
    </ProMembershipContext.Provider>
  );
}
