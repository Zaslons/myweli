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
import { Toast } from '../Toast';
import {
  type ProProfile,
  getMyInvitations,
  getMyProvider,
  getMySalons,
  logoutPro,
  selectSalon,
} from '../../lib/api/pro';
import {
  type Membership,
  type SalonMembership,
  type TeamInvitation,
  type TeamRole,
  hasCap,
  joinedSalonMessage,
} from '../../lib/pro/team';
import { type ToastKind, useToast } from '../../lib/useToast';
import { ProRevokedInvitations } from './ProRevokedInvitations';

/// The membership context over the pro dashboard (team access R5b —
/// docs/design/web-team-access-r5.md §2.4). Fetches /api/pro/me on mount and
/// on EVERY pathname change — that re-fetch IS the revocation probe (threat
/// T38): a revoked member's next navigation hits `403 not_a_member`.
///
/// The rejoin gate (docs/design/pro-rejoin-gate.md §2): on not_a_member the
/// session is still live, so before signing out the context asks for the
/// account's OWN pending invitations. One or more → the « Invitations » page
/// replaces the dashboard and the session is kept; none, or any failure → the
/// sign-out onto /pro/connexion?motif=acces-retire (no PII in the URL), as
/// before — it fails CLOSED. An empty list is re-checked against /me once
/// first: an accept that just activated the row empties the list too.
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
  /// The provider-level toast — it outlives a page remount (a join re-keys
  /// the pages, and with them any toast a page would own).
  notify: (message: string, kind?: ToastKind) => void;
};

/// What a probe ended in. `revoked` covers both ends of the not_a_member
/// branch (the gate, or the sign-out); `entered` is that branch finding the
/// account a member after all (and entering its salon) — either way the
/// caller has nothing left to do.
type ProbeOutcome = 'member' | 'entered' | 'revoked' | 'other' | 'skipped';

const ProMembershipContext = createContext<ProMembershipValue | null>(null);

export function useProMembership(): ProMembershipValue {
  const ctx = useContext(ProMembershipContext);
  if (!ctx) {
    throw new Error('useProMembership requires <ProMembershipProvider>');
  }
  return ctx;
}

/// For a component that also renders outside the dashboard layout (its unit
/// tests mount it bare) — null there instead of a throw.
export function useOptionalProMembership(): ProMembershipValue | null {
  return useContext(ProMembershipContext);
}

const REVOKED_LANDING = '/pro/connexion?motif=acces-retire';

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
  const { toast, show } = useToast();

  // --- the rejoin gate ---------------------------------------------------
  /// Non-null while the « Invitations » page stands in for the dashboard.
  const [rejoinInvites, setRejoinInvites] = useState<TeamInvitation[] | null>(
    null,
  );
  /// Bumped at each gate entry so the page remounts on a fresh list.
  const [gateEpoch, setGateEpoch] = useState(0);
  const [lostSalon, setLostSalon] = useState('');
  const [joining, setJoining] = useState(false);
  /// Leaving the gate for /pro: the gate (in its loading state) stays until
  /// the navigation lands, so no page of the OLD path mounts under the new
  /// role (a member revoked on /pro/clients may rejoin as Collaborateur).
  const [leaving, setLeaving] = useState(false);
  const pathRef = useRef(pathname);
  pathRef.current = pathname;
  /// While the gate is up — accepts included — no navigation probe runs: only
  /// the gate's own events (a join, an emptied list) re-check, with `force`.
  /// The app's checkMembershipAlive does the same (`_rejoinPending`).
  const gated = useRef(false);
  /// Single-flight: concurrent not_a_member answers share ONE check.
  const revokedCheck = useRef<Promise<ProbeOutcome> | null>(null);
  /// The last salon this session acted in — the gate names it.
  const lastSalon = useRef('');

  const commitProfile = useCallback((profile: ProProfile) => {
    setMembership(profile.membership ?? null);
    setSalonName(profile.provider.name || '');
    setProviderId(profile.provider.id);
    setEmail(profile.account.email ?? null);
    lastSalon.current = profile.provider.name || '';
  }, []);

  const refreshSalons = useCallback(async () => {
    const r = await getMySalons();
    if (r.status === 200) {
      setSalons(r.items);
      setCanAdd(r.canAddSalon);
    }
  }, []);

  /// Today's sign-out, unchanged in effect: drop the cookies, land on the
  /// login with the generic banner. A failed logout call still lands there.
  const signOutRevoked = useCallback(async () => {
    await logoutPro().catch(() => undefined);
    router.replace(REVOKED_LANDING);
  }, [router]);

  /// The gate opens: the session stays, the lost salon's context goes.
  const enterGate = useCallback((invitations: TeamInvitation[]) => {
    gated.current = true;
    setLostSalon(lastSalon.current);
    setMembership(null);
    setSalonName('');
    setProviderId(null);
    setEmail(null);
    setSalons([]);
    setCanAdd(false);
    setJoining(false);
    setRejoinInvites(invitations);
    setGateEpoch((e) => e + 1);
    setLoading(false);
  }, []);

  /// Into a salon after the gate (or after a check that found the account a
  /// member again): its dashboard at /pro — the role may differ from the one
  /// whose page was showing — with every page remounted for it.
  const enterSalon = useCallback(() => {
    gated.current = false;
    setLoading(false);
    setSwitchEpoch((e) => e + 1);
    router.replace('/pro');
    void refreshSalons();
    if (pathRef.current === '/pro') {
      setRejoinInvites(null);
      setJoining(false);
    } else {
      setJoining(true);
      setLeaving(true);
    }
  }, [router, refreshSalons]);

  useEffect(() => {
    if (leaving && pathname === '/pro') {
      setLeaving(false);
      setRejoinInvites(null);
      setJoining(false);
    }
  }, [leaving, pathname]);

  /// Before a sign-out decided from an EMPTY list: one more look at /me. A
  /// 200 means an accept activated the row (that is why the list is empty) —
  /// enter instead. Anything else signs out.
  const confirmOrSignOut = useCallback(async (): Promise<ProbeOutcome> => {
    const me = await getMyProvider().catch(() => null);
    if (me?.status === 200 && me.profile) {
      commitProfile(me.profile);
      enterSalon();
      return 'entered';
    }
    await signOutRevoked();
    return 'revoked';
  }, [commitProfile, enterSalon, signOutRevoked]);

  const checkRevoked = useCallback((): Promise<ProbeOutcome> => {
    if (revokedCheck.current) return revokedCheck.current;
    const run = (async (): Promise<ProbeOutcome> => {
      // An account with no active membership has no salon to act in: drop
      // the selection first, so every read after this one is unscoped.
      await selectSalon(null).catch(() => undefined);
      const inv = await getMyInvitations().catch(() => ({
        status: 0,
        invitations: [] as TeamInvitation[],
      }));
      if (inv.status === 200 && inv.invitations.length > 0) {
        enterGate(inv.invitations);
        return 'revoked';
      }
      if (inv.status === 200) return confirmOrSignOut();
      // 401, non-200, no network: fail closed.
      await signOutRevoked();
      return 'revoked';
    })().finally(() => {
      revokedCheck.current = null;
    });
    revokedCheck.current = run;
    return run;
  }, [enterGate, confirmOrSignOut, signOutRevoked]);

  const runProbe = useCallback(
    async (force = false): Promise<ProbeOutcome> => {
      if (gated.current && !force) return 'skipped';
      const seq = ++probeSeq.current;
      const failed = { status: 0 } as Awaited<ReturnType<typeof getMyProvider>>;
      let r = await getMyProvider().catch(() => failed);
      if (seq !== probeSeq.current) return 'skipped';
      // The gate opened while this probe was out: it is no longer its call.
      if (gated.current && !force) return 'skipped';
      if (r.status === 403 && r.error === 'forbidden') {
        // R6: a per-salon denial — the SELECTED salon revoked us (or vanished).
        // Clear the selection once and retry on the default salon; the session
        // survives. (A repeat 403 falls through to the error-keeping branch.)
        await selectSalon(null).catch(() => undefined);
        r = await getMyProvider().catch(() => failed);
        if (seq !== probeSeq.current) return 'skipped';
        if (r.status === 200) void refreshSalons();
      }
      if (r.status === 403 && r.error === 'not_a_member') {
        return checkRevoked();
      }
      if (r.status === 200 && r.profile) {
        commitProfile(r.profile);
        setLoading(false);
        return 'member';
      }
      // 401 → the page-level guards own the plain redirect (avoid racing two
      // router.replace calls); other errors keep the last known state so a
      // transient failure never locks the UI.
      setLoading(false);
      return 'other';
    },
    [commitProfile, refreshSalons, checkRevoked],
  );

  const probe = useCallback(async () => {
    await runProbe();
  }, [runProbe]);

  useEffect(() => {
    probe();
  }, [probe, pathname]);

  // « Mes salons » loads once at mount (then on demand — switch/add).
  useEffect(() => {
    refreshSalons();
  }, [refreshSalons]);

  /// S2: « Rejoindre » succeeded. Wait for /me to say so, then the joined
  /// salon's dashboard and « Vous avez rejoint {salon} ».
  const onJoined = useCallback(
    async (inv: TeamInvitation) => {
      setJoining(true);
      const outcome = await runProbe(true);
      // Still not a member (the gate reopened on what is left, or signed out).
      if (outcome === 'revoked') return;
      // A 200 — or a transient failure after an accept the server confirmed:
      // the membership is active, so the dashboard (and its own error state)
      // is the honest place to land. (`entered`: the check already did.)
      if (outcome !== 'entered') enterSalon();
      show(joinedSalonMessage(inv.salonName), 'success');
    },
    [runProbe, enterSalon, show],
  );

  /// S3/S6: the last card went (declined, expired, withdrawn).
  const onEmptied = useCallback(() => {
    void confirmOrSignOut();
  }, [confirmOrSignOut]);

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
        notify: show,
      }}
    >
      {rejoinInvites ? (
        <ProRevokedInvitations
          key={gateEpoch}
          invitations={rejoinInvites}
          lostSalon={lostSalon}
          joining={joining}
          onJoined={(inv) => void onJoined(inv)}
          onEmptied={onEmptied}
        />
      ) : (
        <div key={switchEpoch} className="contents">
          {children}
        </div>
      )}
      {/* Always mounted: a live region must exist before its text lands
          (WEB-SYSTEM §7) — and it must survive the gate → dashboard swap. */}
      <Toast toast={toast} />
    </ProMembershipContext.Provider>
  );
}
