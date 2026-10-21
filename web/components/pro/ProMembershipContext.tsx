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
import { rememberSalon, rememberedSalon } from '../../lib/pro/remembered-salon';
import { signOutPro } from '../../lib/pro/sign-out';
import {
  type GateExitReason,
  type Membership,
  type SalonMembership,
  type TeamInvitation,
  type TeamRole,
  hasCap,
  joinedSalonMessage,
  logoutErrorMessage,
  revokedLanding,
} from '../../lib/pro/team';
import { loadFailure, type LoadFailure } from '../../lib/api/load-failure';
import { type ToastKind, useToast } from '../../lib/useToast';
import { ProRevokedInvitations } from './ProRevokedInvitations';
import { ProSignOutRetry } from './ProSignOutRetry';

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
/// before — it fails CLOSED. Before that sign-out, /me is re-checked once —
/// after an empty list AND after a failed one (§10, as the app): an accept
/// that just activated the row empties the list too, and the re-check can
/// only keep a session the server ties to a salon.
///
/// A sign-out is real or it is not shown: the session is two httpOnly cookies
/// only the logout RESPONSE clears, so when that call fails the context does
/// not land on the (signed-out-looking) login — it locks on ProSignOutRetry,
/// which says why and retries.
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

/// A salon switch: done, or why not — no answer (`'offline'`) or the
/// server's refusal or failure (`'failed'`).
export type SwitchOutcome = 'switched' | LoadFailure;

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
  /// Why a switch did not happen, so the switcher can name the network
  /// (docs/design/web-pro-no-connection-copy.md §5).
  switchSalon: (salonId: string) => Promise<SwitchOutcome>;
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

/// A revoked sign-out whose logout call failed: what the locked page says,
/// and where its retry lands.
type SignOutLock = { error: string; landing: string };

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
  /// The gate's full-page wait: S2's join on its way to the salon, S6's
  /// sign-out on its way to the login. Nothing is actionable meanwhile.
  const [waiting, setWaiting] = useState(false);
  /// Leaving the gate for /pro: the gate (in its loading state) stays until
  /// the navigation lands, so no page of the OLD path mounts under the new
  /// role (a member revoked on /pro/clients may rejoin as Collaborateur).
  const [leaving, setLeaving] = useState(false);
  /// Non-null when a revoked sign-out's logout call failed: the locked page.
  const [signOutLock, setSignOutLock] = useState<SignOutLock | null>(null);
  const pathRef = useRef(pathname);
  pathRef.current = pathname;
  /// While the gate is up — accepts included — no navigation probe runs: only
  /// the gate's own events (a join, an emptied list) re-check, with `force`.
  /// The app's checkMembershipAlive does the same (`_rejoinPending`). The
  /// locked sign-out page holds it too.
  const gated = useRef(false);
  /// Single-flight: concurrent not_a_member answers share ONE check.
  const revokedCheck = useRef<Promise<ProbeOutcome> | null>(null);
  /// The last salon this page acted in — the gate names it. After a reload
  /// it is empty, and the salon the BROWSER remembers names it instead
  /// (decision 14, docs/design/web-pro-truthful-failure.md §2.4).
  const lastSalon = useRef('');
  /// No profile has committed — none yet (the page just loaded), or none
  /// since the gate wiped the membership: the sidebar keeps its skeleton
  /// rather than draw a nav from an ABSENT membership (hasCap's owner-shaped
  /// fallback would hand a Collaborateur the owner's entries). It used to
  /// start false, so a FIRST /me that failed drew the owner's menu for any
  /// role (B4.4).
  const awaitingProfile = useRef(true);
  /// The cookies were cleared (a sign-out landed): a late « Rejoindre »
  /// answer is dropped, never walked into a salon.
  const signedOut = useRef(false);

  const commitProfile = useCallback((profile: ProProfile) => {
    awaitingProfile.current = false;
    setMembership(profile.membership ?? null);
    setSalonName(profile.provider.name || '');
    setProviderId(profile.provider.id);
    setEmail(profile.account.email ?? null);
    lastSalon.current = profile.provider.name || '';
    rememberSalon({ id: profile.provider.id, name: profile.provider.name || '' });
  }, []);

  const refreshSalons = useCallback(async () => {
    const r = await getMySalons();
    if (r.status === 200) {
      setSalons(r.items);
      setCanAdd(r.canAddSalon);
    }
  }, []);

  /// The lost salon's context goes (its agenda, its clients do not stay in
  /// memory): the gate and the locked page both stand on this.
  const dropSalon = useCallback(() => {
    awaitingProfile.current = true;
    setLostSalon(lastSalon.current || rememberedSalon()?.name || '');
    setMembership(null);
    setSalonName('');
    setProviderId(null);
    setEmail(null);
    setSalons([]);
    setCanAdd(false);
  }, []);

  const markSignedOut = useCallback(() => {
    signedOut.current = true;
  }, []);

  /// Today's sign-out: drop the cookies, land on the login with the generic
  /// banner (and, when the gate's last card went on the server's word, why).
  /// Only once the logout RESPONSE came back OK — otherwise the session still
  /// lives, and the context locks on a page that says so and retries.
  const signOutRevoked = useCallback(
    async (reason?: GateExitReason) => {
      const landing = revokedLanding(reason);
      const outcome = await signOutPro();
      if (outcome === 'ok') {
        signedOut.current = true;
        router.replace(landing);
        return;
      }
      gated.current = true;
      dropSalon();
      setRejoinInvites(null);
      setWaiting(false);
      setLoading(false);
      setSignOutLock({ error: logoutErrorMessage(outcome), landing });
    },
    [router, dropSalon],
  );

  /// The gate opens: the session stays, the lost salon's context goes.
  const enterGate = useCallback(
    (invitations: TeamInvitation[]) => {
      gated.current = true;
      dropSalon();
      setSignOutLock(null);
      setWaiting(false);
      setRejoinInvites(invitations);
      setGateEpoch((e) => e + 1);
      setLoading(false);
    },
    [dropSalon],
  );

  /// Into a salon after the gate (or after a check that found the account a
  /// member again): its dashboard at /pro — the role may differ from the one
  /// whose page was showing — with every page remounted for it. With no
  /// profile committed yet the sidebar stays a skeleton (`loading`).
  const enterSalon = useCallback(() => {
    gated.current = false;
    setLoading(awaitingProfile.current);
    setSwitchEpoch((e) => e + 1);
    router.replace('/pro');
    void refreshSalons();
    if (pathRef.current === '/pro') {
      setRejoinInvites(null);
      setWaiting(false);
    } else {
      setWaiting(true);
      setLeaving(true);
    }
  }, [router, refreshSalons]);

  useEffect(() => {
    if (leaving && pathname === '/pro') {
      setLeaving(false);
      setRejoinInvites(null);
      setWaiting(false);
    }
  }, [leaving, pathname]);

  /// Before a sign-out decided on an empty OR failed list (or on the gate's
  /// last card going): one more look at /me. A 200 means an accept activated
  /// the row (that is why the list is empty) — enter instead. Anything else
  /// signs out: the look can only keep a session the server ties to a salon.
  const confirmOrSignOut = useCallback(
    async (reason?: GateExitReason): Promise<ProbeOutcome> => {
      const me = await getMyProvider().catch(() => null);
      if (me?.status === 200 && me.profile) {
        commitProfile(me.profile);
        enterSalon();
        return 'entered';
      }
      await signOutRevoked(reason);
      return 'revoked';
    },
    [commitProfile, enterSalon, signOutRevoked],
  );

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
      // None — or the list failed (401, 5xx, no network): the re-check, then
      // the sign-out. Fail closed.
      return confirmOrSignOut();
    })().finally(() => {
      revokedCheck.current = null;
    });
    revokedCheck.current = run;
    return run;
  }, [enterGate, confirmOrSignOut]);

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
      // transient failure never locks the UI — except when there IS no known
      // state (none yet, or the gate wiped it): then the sidebar keeps
      // waiting, and `probe` keeps asking.
      if (!awaitingProfile.current) setLoading(false);
      return 'other';
    },
    [commitProfile, refreshSalons, checkRevoked],
  );

  /// The provider outlives nothing it schedules: a heal loop stops with it.
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  /// After a join whose /me failed: keep asking, with a growing pause (1, 2,
  /// 4, 8, 16 s, then every 30 s), until a profile commits — the sidebar's
  /// skeleton then fills with the member's OWN nav. One follow-up probe was
  /// not enough: if it failed too, the sidebar stayed a skeleton with no
  /// retry anywhere unless the page's own /me failed (found by the review of
  /// the fixes). Stops on a commit, a sign-out, the gate reopening, or unmount.
  /// Single-flight: a join and a page's own probe may both start it.
  const healing = useRef(false);
  const healProfile = useCallback(async () => {
    if (healing.current) return;
    healing.current = true;
    try {
      const pauses = [1000, 2000, 4000, 8000, 16000];
      for (let i = 0; ; i += 1) {
        if (!alive.current || signedOut.current || !awaitingProfile.current) return;
        const outcome = await runProbe();
        if (outcome === 'member' || outcome === 'entered' || outcome === 'revoked') return;
        if (!awaitingProfile.current) return;
        const pause = i < pauses.length ? pauses[i] : 30000;
        await new Promise((resolve) => setTimeout(resolve, pause));
      }
    } finally {
      healing.current = false;
    }
  }, [runProbe]);

  /// A navigation's probe (and a page's « Réessayer »). One that fails with
  /// no profile committed yet — the page's FIRST /me — keeps asking rather
  /// than leave the sidebar waiting with nothing to wake it (B4.4).
  const probe = useCallback(async () => {
    const outcome = await runProbe();
    if (outcome === 'other' && awaitingProfile.current) void healProfile();
  }, [runProbe, healProfile]);

  useEffect(() => {
    probe();
  }, [probe, pathname]);

  // « Mes salons » loads once at mount (then on demand — switch/add).
  useEffect(() => {
    refreshSalons();
  }, [refreshSalons]);

  /// An accept that answered after a sign-out landed: never walked into a
  /// salon. Its response may have carried a refreshed session (the BFF sets
  /// the cookies again on a refresh), so the logout runs once more.
  const dropLateJoin = useCallback(() => {
    void logoutPro();
  }, []);

  /// S2: « Rejoindre » succeeded. Wait for /me to say so, then the joined
  /// salon's dashboard and « Vous avez rejoint {salon} ».
  const onJoined = useCallback(
    async (inv: TeamInvitation) => {
      if (signedOut.current) return dropLateJoin();
      setWaiting(true);
      const outcome = await runProbe(true);
      if (signedOut.current) return dropLateJoin();
      // Still not a member (the gate reopened on what is left, or signed out).
      if (outcome === 'revoked') return;
      // A 200 — or a transient failure after an accept the server confirmed:
      // the membership is active, so the dashboard (and its own error state)
      // is the honest place to land. (`entered`: the check already did.)
      if (outcome !== 'entered') enterSalon();
      // No profile committed (the forced /me failed): the sidebar waits in
      // its skeleton while the provider keeps asking (healProfile) — at /pro
      // no navigation will run a probe. The page's « Réessayer » re-probes too.
      if (outcome === 'other' || outcome === 'skipped') void healProfile();
      show(joinedSalonMessage(inv.salonName), 'success');
    },
    [runProbe, enterSalon, show, dropLateJoin, healProfile],
  );

  /// S3/S6: the last card went (declined, or gone on the server's word — the
  /// reason then travels to the login). The wait shows while it is decided.
  const onEmptied = useCallback(
    (reason?: GateExitReason) => {
      setWaiting(true);
      void confirmOrSignOut(reason);
    },
    [confirmOrSignOut],
  );

  /// A card's answer was 401: the session died under the gate (signed out in
  /// another tab, refresh token expired). Out to the login, as today.
  const onUnauthenticated = useCallback(() => {
    setWaiting(true);
    void signOutRevoked();
  }, [signOutRevoked]);

  const switchSalon = useCallback(
    async (salonId: string) => {
      // A /me already out was asked for the salon BEFORE this switch: its
      // answer must not land after the switch commits and put the rail back
      // on the old salon while the server acts for the new one. Bumping the
      // probe sequence retires it — before the select (probes already out)
      // and after it (one that left while the select was in flight). Found
      // when a notification's `?salon=` switched during the page-load probe
      // (docs/design/web-pro-notifications.md §3.4).
      probeSeq.current++;
      const r = await selectSalon(salonId);
      probeSeq.current++;
      if (r.ok && r.profile) {
        commitProfile(r.profile);
        // The probe this switch retired may have been the first one — the
        // one that ends the initial loading. A switch that commits a profile
        // ends it too, or the rail would wait in its skeleton for ever.
        setLoading(false);
        // Re-key the page subtree: every page client remounts and refetches
        // for the new salon (zero per-page wiring).
        setSwitchEpoch((e) => e + 1);
        void refreshSalons();
        return 'switched';
      }
      // Refused (revoked there since the list loaded / unknown) — refresh
      // the list; the current salon stays.
      void refreshSalons();
      // No usable answer: nothing came back (status 0), or a 2xx whose
      // profile was lost on the way (a write stays `ok` without its payload,
      // web-pro-network-failure.md §2). The person's connection — and picking
      // again is safe, the selection is idempotent.
      return r.ok ? 'offline' : loadFailure(r.status);
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
      {signOutLock ? (
        <ProSignOutRetry
          lostSalon={lostSalon}
          error={signOutLock.error}
          redirectTo={signOutLock.landing}
          onSignedOut={markSignedOut}
        />
      ) : rejoinInvites ? (
        <ProRevokedInvitations
          key={gateEpoch}
          invitations={rejoinInvites}
          lostSalon={lostSalon}
          waiting={waiting}
          onJoined={(inv) => void onJoined(inv)}
          onEmptied={onEmptied}
          onUnauthenticated={onUnauthenticated}
          onSignedOut={markSignedOut}
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
