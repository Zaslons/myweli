import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../core/access/pro_access_guard.dart';
import '../core/access/pro_salon_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/constants/unnamed_salon.dart';
import '../core/di/dependency_injection.dart';
import '../core/router/pro_router.dart';
import '../core/utils/salon_id.dart';
import '../models/pro_membership.dart';
import '../models/provider.dart';
import '../models/provider_login_result.dart';
import '../models/provider_session.dart';
import '../models/provider_user.dart';
import '../models/salon_facts.dart';
import '../models/salon_market.dart';
import '../models/salon_membership_info.dart';
import '../models/team_invitation.dart';
import '../models/team_member.dart';
import '../services/interfaces/auth_service_interface.dart';
import '../services/interfaces/pro_service_interface.dart';

/// Why a salon switch did not happen ([ProAuthProvider.switchSalonOutcome]):
/// no answer — the network, or a body that could not be read — or the
/// server's refusal (revoked there, salon gone; a 5xx too).
enum SalonSwitchOutcome { switched, offline, refused }

class ProAuthProvider extends ChangeNotifier {
  final AuthServiceInterface _authService = serviceLocator.authService;

  ProviderUser? _provider;
  bool _isLoading = false;
  String? _error;

  ProviderUser? get provider => _provider;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _provider != null;

  // ---- Membership (team access R4b) ----------------------------------------

  /// The acting membership from GET /me/provider — cached in the persisted
  /// session for instant cold-start shaping, refreshed each start. UI gating
  /// only; the server recomputes every decision (T38).
  ProMembership? _membership;
  ProMembership? get membership => _membership;

  TeamRole get role => _membership?.role ?? TeamRole.owner;
  bool get isStaff => _membership?.role == TeamRole.staff;

  // ---- Salon market facts (multi-pays MP2) ----------------------------------

  /// The acting salon's payload from GET /me/provider — the carrier of its
  /// server-derived market facts (multi-pays-end-version.md §3–5). Refreshed
  /// with the membership on every probe AND on every salon switch. Live only:
  /// null after a cold start whose refresh failed.
  Provider? _activeSalon;
  Provider? get activeSalon => _activeSalon;

  /// The salon's market facts — from the live payload, or restored from the
  /// session at cold start (docs/design/pro-app-salon-not-loaded.md §3.1).
  SalonMarket? _market;

  /// [_market] while it is the facts of the salon the session ACTS in — never
  /// another's: after an R6 fallback whose refetch failed, the facts are
  /// still the lost selection's, and its clock is not this salon's.
  SalonMarket? get _actingMarket {
    final market = _market;
    return market != null && market.salonId == activeSalonId ? market : null;
  }

  /// The acting salon's market facts are known. A known salon whose
  /// [salonTimezone] is null IS on Abidjan — the server's own default; an
  /// unknown one is never guessed (pro-app-salon-not-loaded.md §2).
  bool get salonKnown => _actingMarket != null;

  /// Signed in, off the rejoin gate (which holds a session with no salon on
  /// purpose and shows no hour), and the salon unknown: no Pro page may
  /// render — `ProSalonGate` stands in for them (§3.2).
  bool get needsSalon => isAuthenticated && !_rejoinPending && !salonKnown;

  /// The stored session is not read yet, or the membership refresh is out
  /// (the cold start's, a sign-in's, « Réessayer »): the gate waits rather
  /// than says it failed. A guard probe is not counted — with the gate up no
  /// page is built, so nothing can start one.
  bool get salonLoading => !sessionRestored || _membershipRefresh != null;

  /// IANA timezone every pro time-display/day-boundary call site passes into
  /// the salon_time helpers. Null → the Abidjan fallback, which is right only
  /// for a KNOWN salon ([salonKnown]); `ProSalonGate` keeps every page off
  /// screen otherwise.
  String? get salonTimezone => _actingMarket?.timezone;

  /// ISO-4217 currency every pro money call site passes into the formatters.
  String? get salonCurrency => _actingMarket?.currency;

  String? get salonCountryCode => _actingMarket?.countryCode;
  String? get salonAreaId => _actingMarket?.areaId;

  /// Takes the shape GET /me/provider answered — the membership, the salon,
  /// its market facts — then caches it for the next cold start. The ONE
  /// place a /me answer lands, so no path can take the salon and forget its
  /// facts.
  Future<void> _takeShape(MyProviderInfo info) async {
    _applyShape(info);
    await _cacheShape();
  }

  /// The fields alone, with no await: no frame sees the membership of one
  /// salon with the facts of another.
  void _applyShape(MyProviderInfo info) {
    _membership = info.membership;
    _activeSalon = info.salon;
    _market = SalonMarket.of(info.salon);
  }

  /// One write after the other: each read-modify-writes the same session
  /// blob, and two in flight at once would lose one of them.
  Future<void> _cacheShape() async {
    await _authService.cacheProviderMembership(_membership);
    await _authService.cacheProviderSalonMarket(_market);
    _keptFacts = _activeSalon == null ? null : SalonFacts.of(_activeSalon!);
    await _authService.cacheProviderSalonFacts(_keptFacts);
  }

  /// The copy of the acting salon's « Profil » facts the session keeps
  /// (B8.3) — restored at cold start, replaced by every live read.
  SalonFacts? _keptFacts;

  /// What « Profil » shows of the acting salon: the live salon, else the copy
  /// kept from the last read — for THAT salon only, never one the session has
  /// since moved away from (docs/design/product-questions-batch8.md §2.3).
  SalonFacts? get salonFacts {
    final live = _activeSalon;
    if (live != null) return SalonFacts.of(live);
    final kept = _keptFacts;
    return kept != null && kept.salonId == activeSalonId ? kept : null;
  }

  /// « Réessayer » on the gate: one more GET /me/provider. Notifies at the
  /// start (the gate shows the wait) and at the end — a failed refresh
  /// notifies nothing on its own.
  Future<void> retrySalon() async {
    final refresh = refreshMembership();
    notifyListeners();
    await refresh;
    notifyListeners();
  }

  // ---- Multi-salons (team access R6) ----------------------------------------

  /// The salon the user SWITCHED to (« Mes salons »), null = the default.
  /// Persisted in the session (cold-start continuity) and revalidated by
  /// every `?salonId=` request server-side (T55).
  SalonId? _selectedSalonId;
  SalonId? get selectedSalonId => _selectedSalonId;

  /// « Mes salons » — the switcher payload (loaded at start + on demand).
  List<SalonMembershipInfo> _salons = const [];
  List<SalonMembershipInfo> get salons => _salons;
  bool get hasMultipleSalons => _salons.length > 1;

  /// Whether deleting this account removes a salon. The server removes every
  /// salon the account OWNS — its linked salon and each active owner
  /// membership (`provider_account_service.dart` deleteAccount) — and nothing
  /// of a salon where it is only a member. Not the role in the salon on
  /// screen: an owner looking at a salon they only manage still owns theirs.
  /// docs/design/pro-app-batch7.md §2.3 (B7.3).
  bool get ownsASalon =>
      (_provider?.providerId?.isNotEmpty ?? false) ||
      _salons.any((s) => s.isOwner);

  bool _loadingSalons = false;

  /// A join landed while a load was out ([acceptInvitation]): that load may
  /// have been answered before the join, so one more runs after it.
  bool _salonsAgain = false;

  /// Refresh « Mes salons » (best-effort — the switcher opens on cached
  /// data and refreshes in place).
  Future<void> loadMySalons() async {
    if (_provider == null || _loadingSalons) return;
    _loadingSalons = true;
    try {
      final res = await serviceLocator.proService.getMySalons();
      if (res.success && res.data != null) {
        _salons = res.data!.items;
        notifyListeners();
      }
    } catch (_) {
      /* keep the cached list */
    } finally {
      _loadingSalons = false;
      if (_salonsAgain) {
        _salonsAgain = false;
        unawaited(loadMySalons());
      }
    }
  }

  /// Switch the acting salon: validate against the server (the membership
  /// there becomes the new shape), persist the selection, and RESET every
  /// per-salon provider so no stale cross-salon data lingers. False = the
  /// switch did not happen — the caller stays on the current salon and the
  /// list refreshes; [switchSalonOutcome] says why.
  Future<bool> switchSalon(SalonId salonId) async =>
      await switchSalonOutcome(salonId) == SalonSwitchOutcome.switched;

  /// [switchSalon], saying why it did not happen — the picker names the
  /// network (docs/design/web-pro-no-connection-copy.md §5).
  Future<SalonSwitchOutcome> switchSalonOutcome(SalonId salonId) async {
    if (_provider == null) return SalonSwitchOutcome.refused;
    if (salonId == activeSalonId) return SalonSwitchOutcome.switched;
    _isLoading = true;
    notifyListeners();
    try {
      final res = await serviceLocator.proService.getMyProvider(
        salonId: salonId,
      );
      if (res.success && res.data != null) {
        // The selection and the salon's shape move together, before any
        // await — a frame between them would see the new salon with the old
        // salon's clock.
        _selectedSalonId = salonId;
        _applyShape(res.data!);
        await _authService.setSelectedProviderSalon(salonId);
        await _cacheShape();
        ProSalonScope.resetAll();
        return SalonSwitchOutcome.switched;
      }
      // A per-salon denial (uniform 403) — likely revoked there since the
      // list loaded — or no answer at all. Refresh the list; the session
      // stays intact.
      await loadMySalons();
      return res.code == 'network'
          ? SalonSwitchOutcome.offline
          : SalonSwitchOutcome.refused;
    } catch (_) {
      // An answer that could not be read (the probe's decode threw): nothing
      // usable came back, as the web's unreadable 2xx — and choosing again
      // is safe, the selection is only persisted once the probe succeeds.
      return SalonSwitchOutcome.offline;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Drop the selection back to the default salon (used when the selected
  /// salon refuses the session mid-flight).
  Future<void> _clearSalonSelection() async {
    _selectedSalonId = null;
    try {
      await _authService.setSelectedProviderSalon(null);
    } catch (_) {
      /* best-effort */
    }
  }

  /// The salon the session acts in: the switched-to salon first (R6), then
  /// the owner's linked salon, else the membership's. Screens use THIS
  /// (never `provider.id` — an account id is not a salon id). The services
  /// that read the salon from the session resolve it by the same function
  /// (docs/design/services-acting-salon.md).
  SalonId? get activeSalonId => resolveActingSalonId(
    selected: _selectedSalonId,
    linked: _provider?.providerId,
    membership: _membership?.salonId,
  );

  /// The acting salon's name: the membership's (cached in the session, so
  /// known at cold start; the salon payload arrives in the same response, so
  /// it never knows a name the membership doesn't). The account's
  /// `businessName` is a sign-up copy of its DEFAULT salon, so it answers
  /// only while that salon is the acting one — never after a switch
  /// (docs/design/r6-salon-fact-reads.md §2.3).
  ///
  /// [salonName] is for a sentence (« … l'accès à votre salon »); a title
  /// reads [knownSalonName] and writes « Salon » itself (unnamed_salon.dart).
  String get salonName => salonNameOr(knownSalonName, kUnnamedOwnSalon);

  /// The acting salon's name, or null when none is known.
  String? get knownSalonName {
    final fromMembership = _membership?.salonName;
    if (fromMembership != null && fromMembership.isNotEmpty) {
      return fromMembership;
    }
    final actingInDefault = _selectedSalonId == null && activeSalonId != null;
    final business = actingInDefault ? _provider?.businessName : null;
    return (business == null || business.isEmpty) ? null : business;
  }

  /// Capability gate. Fallback without a membership (legacy session /
  /// offline first frame): a linked OWNER account stays owner-shaped; a bare
  /// member gets the minimal surface until the fetch lands.
  bool can(String capability) =>
      _membership?.can(capability) ?? (_provider?.providerId != null);

  /// The refresh in flight, shared: a second caller joins it rather than
  /// returning early, so [completeRejoin] can wait for one started before the
  /// accept before it asks again.
  Future<void>? _membershipRefresh;

  /// Fetch + cache the membership. On `not_a_member` (revoked — R4a) the
  /// rejoin rule decides between « Invitations » and the « accès retiré »
  /// sign-out ([_onNotAMember]). R6: a `forbidden` on a SELECTED salon is a
  /// per-salon denial — the selection silently falls back to the default
  /// salon, never a sign-out.
  Future<void> refreshMembership() {
    if (_provider == null) return Future<void>.value();
    return _membershipRefresh ??= _refreshMembership().whenComplete(() {
      _membershipRefresh = null;
    });
  }

  Future<void> _refreshMembership() async {
    try {
      var res = await serviceLocator.proService.getMyProvider();
      if (!res.success && res.code == 'forbidden' && _selectedSalonId != null) {
        await _clearSalonSelection();
        // The lost salon's stores go with it, whatever the refetch answers
        // (B7.14 — docs/design/pro-app-batch7.md §2.14). Here, not inside
        // `_clearSalonSelection`: the rejoin gate calls that after its
        // awaits, and a reset there would empty the cards it seeded (S9).
        ProSalonScope.resetAll();
        res = await serviceLocator.proService.getMyProvider();
      }
      if (res.success && res.data != null) {
        await _takeShape(res.data!);
        notifyListeners();
      } else if (res.code == 'not_a_member') {
        await _onNotAMember();
      }
      // Network/other failures: keep the cached shape — server still guards.
    } catch (_) {
      /* keep the cached shape */
    }
  }

  bool _probing = false;

  /// The ProAccessGuard handler: a forbidden response somewhere probes the
  /// membership ONCE — an active member (capability miss) sees nothing; a
  /// revoked member goes through the rejoin rule (§5.3, no dead-end
  /// screens). Stands down while the rejoin gate holds the session or an
  /// accept is in flight: a 403 then is the lost salon's, already handled —
  /// or one answered BEFORE the accept, which must not undo it (C2).
  Future<void> checkMembershipAlive() async {
    if (_provider == null || _probing || _rejoinPending || _accepting) return;
    _probing = true;
    var fellBack = false;
    try {
      var res = await serviceLocator.proService.getMyProvider();
      if (!res.success && res.code == 'forbidden' && _selectedSalonId != null) {
        // R6: revoked from the SELECTED salon only — fall back to the
        // default salon and reshape; the session survives.
        await _clearSalonSelection();
        fellBack = true;
        // Whatever the refetch answers (B7.14): a failed one used to keep
        // the lost salon's stores, shown under the default salon's name.
        ProSalonScope.resetAll();
        res = await serviceLocator.proService.getMyProvider();
        if (res.success && res.data != null) {
          await loadMySalons();
        }
      }
      if (res.code == 'not_a_member') {
        await _onNotAMember();
      } else if (res.success && res.data != null) {
        await _takeShape(res.data!);
        notifyListeners();
        fellBack = false; // notified
      }
    } catch (_) {
      /* transient — the next action retries */
    } finally {
      _probing = false;
      // The selection fell back and the default salon did not answer: the
      // session now acts in a salon it does not know — the gate must learn
      // it, though nothing else changed on screen.
      if (fellBack) notifyListeners();
    }
  }

  String? _revokedNotice;

  /// One-shot: the revoked salon's name for the login banner.
  String? consumeRevokedNotice() {
    final notice = _revokedNotice;
    _revokedNotice = null;
    return notice;
  }

  /// [notice] is the salon named by the login banner — taken by the caller
  /// BEFORE anything is nulled (C1: a second answer computing it afterwards
  /// renamed it « votre salon »).
  Future<void> _signOutRevoked(String notice) async {
    _revokedNotice = notice;
    _membership = null;
    _activeSalon = null;
    _keptFacts = null;
    await logout();
    _router.go('/pro/login');
  }

  // ---- The rejoin gate (docs/design/pro-rejoin-gate.md) ---------------------
  //
  // A former member re-invited used to be signed out by the very sign-in the
  // invitation e-mail asked for. On `not_a_member`, while the session is
  // still live, the pending invitations are asked for first: one or more →
  // « Invitations » in a locked mode, the session kept and the lost salon's
  // context dropped; none, or the question fails → today's sign-out (fail
  // closed). One decision point for all three paths — sign-in, cold start,
  // mid-session.

  bool _rejoinPending = false;

  /// The session is held on « Invitations » (§3): signed in, no salon.
  /// Nothing of the lost salon is reachable, and notification taps wait.
  bool get rejoinPending => _rejoinPending;

  List<TeamInvitation> _rejoinInvitations = const [];

  /// The cards the gate opens on — the list the decision already fetched.
  List<TeamInvitation> get rejoinInvitations => _rejoinInvitations;

  String? _rejoinNotice;
  String? _rejoinLostSalon;

  /// The salon whose access was lost, for the gate's banner — null when none
  /// is known: a sign-in from nothing has no membership, and « ce salon »
  /// above ANOTHER salon's card would read as that salon (§3).
  String? get rejoinRevokedSalon => _rejoinLostSalon;

  /// « Rejoindre » in flight — through [completeRejoin].
  bool _accepting = false;

  /// The not_a_member decision in flight. Single-flight (C1): the cold-start
  /// refresh and a guard probe can both answer not_a_member; they make ONE
  /// check, and the banner keeps the name taken by the first.
  Future<void>? _revokedCheck;

  Future<void> _onNotAMember() =>
      _revokedCheck ??= _decideOnRevoked().whenComplete(() {
        _revokedCheck = null;
      });

  Future<void> _decideOnRevoked() async {
    // Live session only; and while the gate holds it or an accept runs, a
    // not_a_member is the lost salon's, or older than the accept (C2).
    if (_provider == null || _rejoinPending || _accepting) return;
    final notice = salonName;
    final lostSalon = _membership?.salonName;
    final cards = await _invitationsOrNone();
    if (_provider == null || _rejoinPending || _accepting) return;
    if (cards.isNotEmpty) {
      await _enterRejoin(cards, notice: notice, lostSalon: lostSalon);
      return;
    }
    // An empty (or failed) list may be an accept that just made the row
    // active — the reason it is no longer pending. Ask once more before
    // ending a session that may have a salon after all.
    if (await _membershipCameBack()) return;
    if (_provider == null || _rejoinPending || _accepting) return;
    await _signOutRevoked(notice);
  }

  /// GET /me/provider/invitations — empty on ANY failure (offline, 401,
  /// 5xx): in doubt, no session without a salon is kept (§2.3, fail closed).
  Future<List<TeamInvitation>> _invitationsOrNone() async {
    try {
      final res = await serviceLocator.proTeamService.getMyInvitations();
      return res.success ? (res.data ?? const []) : const [];
    } catch (_) {
      return const [];
    }
  }

  /// The re-check before a sign-out (§2.4): a 200 means a membership exists
  /// again — the app takes its shape in place, as the R6 fallback does.
  Future<bool> _membershipCameBack() async {
    try {
      final res = await serviceLocator.proService.getMyProvider();
      if (!res.success || res.data == null || _provider == null) return false;
      await _takeShape(res.data!);
      ProSalonScope.resetAll();
      unawaited(loadMySalons());
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Gate entry (§2.2): the session is kept, the lost salon is not — its
  /// membership, its cached shape, its selection and every per-salon store
  /// go now, BEFORE the gate seeds its cards (the reset empties them too).
  ///
  /// The stores are reset in the same synchronous block that raises
  /// [rejoinPending], before the first await: the storage writes below are
  /// platform-channel round trips on a phone, and a splash whose spin ends
  /// inside them reads [rejoinPending] and opens the gate (S9) — whose seed
  /// a reset arriving after it would empty, leaving a spinner.
  Future<void> _enterRejoin(
    List<TeamInvitation> cards, {
    required String notice,
    String? lostSalon,
  }) async {
    _rejoinPending = true;
    _rejoinInvitations = List.unmodifiable(cards);
    _rejoinNotice = notice;
    _rejoinLostSalon = (lostSalon?.isNotEmpty ?? false) ? lostSalon : null;
    _membership = null;
    _activeSalon = null;
    _market = null;
    _keptFacts = null;
    _salons = const [];
    _salonsAgain = false;
    // No store's reset reloads anything, so the selection cleared just
    // below (after an await) is not read in between.
    ProSalonScope.resetAll();
    try {
      await _authService.cacheProviderMembership(null);
      await _authService.cacheProviderSalonMarket(null);
      await _authService.cacheProviderSalonFacts(null);
    } catch (_) {
      /* best-effort — the next refresh overwrites it */
    }
    await _clearSalonSelection();
    notifyListeners();
    _router.go('/pro/invitations');
  }

  /// « Déconnexion » on the gate (§4 S8): today's sign-out, the banner naming
  /// the lost salon. Plain — no re-check: the person asked to leave.
  Future<void> signOutRevoked() => _signOutRevoked(_rejoinNotice ?? salonName);

  /// The gate's last card is gone — declined (S6), or refused as expired or
  /// withdrawn (S3). The sign-out this calls for is decided on an EMPTY
  /// list, so GET /me/provider is asked once first (§2.4): a card can be
  /// gone because it was accepted — on the web, on another device, or by a
  /// first « Rejoindre » whose answer was lost — and then the person enters
  /// that salon instead of being told her access was withdrawn. True =
  /// entered a salon; false = signed out with the banner (or the session had
  /// already ended).
  Future<bool> leaveEmptiedRejoin() async {
    if (_provider == null || !_rejoinPending) return false;
    // Taken before anything is nulled (C1).
    final notice = _rejoinNotice ?? salonName;
    final cameBack = await _membershipCameBack();
    if (_provider == null || !_rejoinPending) return false;
    if (cameBack) {
      _landInJoinedSalon(staff: isStaff);
      return true;
    }
    await _signOutRevoked(notice);
    return false;
  }

  /// The gate's session died under it: a refresh the server refused clears
  /// the stored session, and every answer on the gate then fails the same
  /// way (`unauthorized`). It ends as an expired session ends — the
  /// sign-in, WITHOUT the « accès retiré » banner: no access was withdrawn
  /// this time, and signing in again brings the gate back if it still holds.
  ///
  /// Only when the STORED session is really gone. RefreshingHttpClient
  /// answers the original 401 too when the refresh POST got no answer, and
  /// then it keeps the session on purpose: that is a bad network, not a dead
  /// session, and signing out would throw a valid session away. True = signed
  /// out; false = the session still stands (the screen says « Pas de
  /// connexion. Réessayez. »).
  Future<bool> endExpiredRejoin() async {
    if (_provider == null || !_rejoinPending) return true;
    if (await _authService.getCurrentProvider() != null) return false;
    await logout();
    _router.go('/pro/login');
    return true;
  }

  /// « Rejoindre » on the gate (S2). [accept] is the accept call (the team
  /// store's, which drops the card on a refusal); while it runs and while the
  /// app takes the joined salon's shape, the membership checks stand down —
  /// a not_a_member answered before the accept must not sign out the person
  /// who just joined (C2). [onAccepted] fires between the two: the screen's
  /// full-screen loader. Null = refused; the gate stays.
  ///
  /// The session can end while the accept is out — the server answers with
  /// the token the request was sent under, so the join still stands. Then
  /// the member comes back but nothing navigates: a signed-out session is
  /// never routed into a salon (review findings 2, 9, 15). Not null in that
  /// case: null reads as a refusal, and a gate with no card left would start
  /// a second sign-out.
  Future<TeamMember?> acceptRejoin(
    Future<TeamMember?> Function() accept, {
    VoidCallback? onAccepted,
  }) async {
    if (!_rejoinPending || _accepting) return null;
    _accepting = true;
    try {
      final joined = await accept();
      if (joined == null) return null;
      if (_provider == null || !_rejoinPending) return joined;
      onAccepted?.call();
      await completeRejoin(joinedRole: joined.role);
      return joined;
    } finally {
      _accepting = false;
    }
  }

  /// An invitation accepted from inside a salon — Profil → Invitations, the
  /// « Accueil » and « Journée » card: the account belongs to one more salon,
  /// so « Mes salons » reloads. Before, only the rejoin gate's way out did,
  /// and the switcher missed the joined salon until its next load
  /// (docs/design/pro-app-batch7.md §2.6, B7.6).
  Future<TeamMember?> acceptInvitation(
    Future<TeamMember?> Function() accept,
  ) async {
    final joined = await accept();
    if (joined != null) {
      // A load already out keeps its place; this one runs after it.
      if (_loadingSalons) {
        _salonsAgain = true;
      } else {
        unawaited(loadMySalons());
      }
    }
    return joined;
  }

  /// Leaves the gate into the joined salon: a refresh started before the
  /// accept is let land (its not_a_member is ignored), a fresh one gives the
  /// new shape, and the router goes to that salon's shell — the staff shell
  /// or the dashboard; [joinedRole] decides when the refresh failed. The
  /// gate is lifted only then, after the `go`, so a notification tap held
  /// meanwhile replays above the new shell rather than above the gate, whose
  /// `go` would drop it (S10). No per-salon reset here: the entry did it, and
  /// a reset now would empty the cards under a gate still on screen (C2).
  ///
  /// Only from a live gate, and again once the answers are back: a session
  /// that ended meanwhile (a sign-out) stays where its sign-out sent it.
  Future<void> completeRejoin({TeamRole? joinedRole}) async {
    if (_provider == null || !_rejoinPending) return;
    final inFlight = _membershipRefresh;
    if (inFlight != null) await inFlight;
    await refreshMembership();
    if (_provider == null || !_rejoinPending) return;
    final staff = _membership == null ? joinedRole == TeamRole.staff : isStaff;
    _landInJoinedSalon(staff: staff);
  }

  /// Off the gate into the salon the session now belongs to: lifted first
  /// without a notify, the router in the salon's shell, THEN the notify — a
  /// held notification tap replays above the shell, not above the gate (S10).
  void _landInJoinedSalon({required bool staff}) {
    _clearRejoin();
    unawaited(loadMySalons());
    _router.go(staff ? '/pro/staff' : '/pro/dashboard');
    notifyListeners();
  }

  void _clearRejoin() {
    _rejoinPending = false;
    _rejoinInvitations = const [];
    _rejoinNotice = null;
    _rejoinLostSalon = null;
  }

  /// [router] — where the session navigates on its own (a sign-out, the
  /// gate); the app's [ProRouter.router] unless a test passes its own.
  ProAuthProvider({GoRouter? router}) : _routerOverride = router {
    // The global 403 seam (access §5.3): forbidden responses anywhere in the
    // pro surfaces trigger ONE membership probe — revoked members sign out.
    ProAccessGuard.onForbidden = checkMembershipAlive;
    ready = loadCurrentProvider();
  }

  final GoRouter? _routerOverride;
  GoRouter get _router => _routerOverride ?? ProRouter.router;

  /// The constructor's session load — restore, then the live membership
  /// refresh. **What the Pro splash awaits**, rather than starting a load of
  /// its own: `main_pro.dart` builds this provider and then awaits the version
  /// gate (up to 1.5 s) before `runApp`, so a fast load has usually finished
  /// before the splash exists, and a second call would run it all again
  /// (docs/design/pro-open-animation.md §5).
  ///
  /// Never completes with an error: the load catches its own failures.
  late final Future<void> ready;

  final Completer<void> _restored = Completer<void>();

  /// Completes once the stored session, the cached membership and the salon
  /// selection have been read — local storage only, BEFORE the live refresh.
  /// From here [isAuthenticated] and [isStaff] answer from the stored session,
  /// which is what the splash routes on when the network is too slow to wait
  /// for (pro-open-animation.md §2.3). Once, for the constructor's load.
  Future<void> get restored => _restored.future;

  /// [restored], synchronously: before it, « signed out » only means « not
  /// read yet », and `ProSalonGate` waits rather than let a page build.
  bool get sessionRestored => _restored.isCompleted;

  void _markRestored() {
    if (!_restored.isCompleted) _restored.complete();
  }

  Future<void>? _loading;

  /// Restores the stored session, then refreshes the membership live — for
  /// an explicit reload; the cold start is [ready]. Concurrent callers share
  /// the load in flight: a second, parallel load would fire duplicate
  /// authenticated requests, exactly when the access token tends to be
  /// expired (docs/design/session-refresh.md).
  Future<void> loadCurrentProvider() =>
      _loading ??= _loadCurrentProvider().whenComplete(() {
        _loading = null;
      });

  Future<void> _loadCurrentProvider() async {
    _isLoading = true;
    notifyListeners();

    try {
      _provider = await _authService.getCurrentProvider();
      _error = null;
      if (_provider != null) {
        // Instant shaping from the cached membership + the R6 selection,
        // then a live refresh (which also catches an offline revocation —
        // R4b — and validates the selection, falling back on a 403).
        _membership = await _authService.getCachedProviderMembership();
        // The salon's clock with it — so a refresh that fails below still
        // leaves the salon known (pro-app-salon-not-loaded.md §3.1).
        _market = await _authService.getCachedProviderSalonMarket();
        // And what « Profil » shows of it, for an offline card (B8.3).
        _keptFacts = await _authService.getCachedProviderSalonFacts();
        _selectedSalonId = await _authService.getSelectedProviderSalon();
        _markRestored();
        // The stored shape is read: the first frame may take it now, before
        // the refresh below — the salon's clock included.
        notifyListeners();
        _syncPush();
        await refreshMembership();
        unawaited(loadMySalons());
      }
    } catch (e) {
      _error = kGenericErrorMessage;
    } finally {
      // Signed out, or the restore itself failed: there is nothing more the
      // stored session can say, so it counts as restored.
      _markRestored();
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---- Pro auth overhaul (docs/design/pro-auth-social.md) -------------------

  /// devCode from the last email-OTP request (dev backends only).
  String? _emailDevCode;
  String? get emailDevCode => _emailDevCode;

  /// Machine code of the last auth failure (e.g. `provider_not_found` → the
  /// login screen offers « Créer un compte »).
  String? _errorCode;
  String? get errorCode => _errorCode;

  // ---- Team access R3: the login invitation bridge --------------------------

  /// Pending invitations surfaced by the last login attempt (the 202
  /// bridge) + the identity proof to accept/decline them. Memory only —
  /// never persisted (short-lived credential).
  List<TeamInvitation> _pendingInvitations = const [];
  InvitationProof? _invitationProof;

  List<TeamInvitation> get pendingInvitations => _pendingInvitations;
  bool get hasPendingInvitations => _pendingInvitations.isNotEmpty;

  /// Login handling for the three bridged sign-ins: signed in → true;
  /// invitations → false with [pendingInvitations] set (the screen shows
  /// the « Invitations » step); failure → false with error/errorCode.
  /// Signed in but revoked with nothing pending → false with neither: the
  /// refresh ended the session and left [consumeRevokedNotice] (S11).
  Future<bool> _bridgedLogin(Future<ProviderLoginResult> Function() run) async {
    _isLoading = true;
    _error = null;
    _errorCode = null;
    _pendingInvitations = const [];
    _invitationProof = null;
    notifyListeners();
    try {
      final result = await run();
      if (result.signedIn) {
        _provider = result.provider;
        _syncPush();
        await refreshMembership();
        unawaited(loadMySalons());
        return _provider != null;
      }
      if (result.hasInvitations) {
        _pendingInvitations = result.invitations;
        _invitationProof = result.proof;
        return false;
      }
      _errorCode = result.code;
      _error = _errorCode == 'cancelled'
          ? null
          : (result.error?.isNotEmpty ?? false
                ? result.error
                : 'Connexion impossible.');
      return false;
    } catch (e) {
      _error = kGenericErrorMessage;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// « Rejoindre » from the login step — accepts under the retained proof;
  /// success = authenticated (the session was persisted service-side).
  Future<bool> acceptPendingInvitation(String invitationId) async {
    final proof = _invitationProof;
    if (proof == null) return false;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      final response = await _authService.acceptProviderInvitation(
        invitationId,
        proof,
      );
      if (response.success && response.data != null) {
        _provider = response.data;
        _pendingInvitations = const [];
        _invitationProof = null;
        _syncPush();
        await refreshMembership();
        unawaited(loadMySalons());
        return _provider != null;
      }
      _error = response.error ?? 'Invitation impossible à accepter.';
      _errorCode = response.code;
      return false;
    } catch (e) {
      _error = kGenericErrorMessage;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// « Refuser » from the login step — removes the card in place; an empty
  /// list falls back to today's « Créer un compte » messaging.
  Future<bool> declinePendingInvitation(String invitationId) async {
    final proof = _invitationProof;
    if (proof == null) return false;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      final response = await _authService.declineProviderInvitation(
        invitationId,
        proof,
      );
      if (!response.success) {
        _error = response.error ?? 'Refus impossible.';
        _errorCode = response.code;
        return false;
      }
      _pendingInvitations = _pendingInvitations
          .where((i) => i.id != invitationId)
          .toList(growable: false);
      if (_pendingInvitations.isEmpty) {
        _invitationProof = null;
        _errorCode = 'provider_not_found';
        _error = kNoProAccountMessage;
      }
      return true;
    } catch (e) {
      _error = kGenericErrorMessage;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Back/« Changer d'e-mail » from the invitations step.
  void clearPendingInvitations() {
    _pendingInvitations = const [];
    _invitationProof = null;
    _error = null;
    _errorCode = null;
    notifyListeners();
  }

  Future<bool> signInWithGoogle() =>
      _bridgedLogin(_authService.signInProviderWithGoogle);

  Future<bool> signInWithApple() =>
      _bridgedLogin(_authService.signInProviderWithApple);

  Future<bool> requestEmailOtp(String email) async {
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      final response = await _authService.requestProviderEmailOtp(email);
      if (response.success) {
        _emailDevCode = (response.data?.isNotEmpty ?? false)
            ? response.data
            : null;
        return true;
      }
      _error = response.error ?? 'Envoi du code impossible.';
      _errorCode = response.code;
      return false;
    } catch (e) {
      _error = kGenericErrorMessage;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyEmailOtp(String email, String code) =>
      _bridgedLogin(() => _authService.verifyProviderEmailOtp(email, code));

  /// Best-effort: register this device under the provider session if push
  /// permission is already granted. Never throws into the auth flow.
  void _syncPush() {
    try {
      unawaited(serviceLocator.proPushRegistration.registerIfGranted());
    } catch (_) {
      /* best-effort */
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Unregister this device first — the call needs the live provider session.
      try {
        await serviceLocator.proPushRegistration.unregister();
      } catch (_) {
        /* best-effort */
      }
      await _authService.logoutProvider();
      _provider = null;
      _membership = null;
      _activeSalon = null;
      _market = null;
      _keptFacts = null;
      _selectedSalonId = null;
      _salons = const [];
      _salonsAgain = false;
      _clearRejoin();
      _error = null;
    } catch (e) {
      _error = kGenericErrorMessage;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
