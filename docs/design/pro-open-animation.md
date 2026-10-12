# The Pro open animation — « MyWeli Pro », then the app

| | |
|---|---|
| **Status** | **Built** (2026-10-11; review fixes 2026-10-12) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-12 |
| **PRD ref / phase** | Launch polish — branding P5 (Pro flavour) · V1 |
| **ROADMAP entry** | [2026-10-11-pro-open-animation](../roadmap/entries/2026-10-11-pro-open-animation.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Governs** | `pro_splash_screen.dart` · `myweli_loader_mixed_pro.json` · `ProAuthProvider.ready`/`.restored` · `landed_push_handler.dart` · `ProRouter.launchPaths` |

## 1. Goal & scope

The Pro app opened on a bare `#FAFAFA` screen for a fixed 2 s, then started the
session load — so a fast network still waited 2 s, and a slow one waited 2 s
*plus* the load. Now `/pro/splash` plays the brand's open animation opening on
**« MyWeli Pro »** (the consumer splash's `loader_v2` *mixed* cut, extended with
the word « Pro »), and routes as soon as the animation AND the session allow.

**In scope:** the asset, the screen, its gates, reduced motion, the broken-asset
fallback, the session-load hand-off, a notification that cold-starts the app.
**Out of scope:** the consumer splash (§11), the native launch screen (shared,
already `#FAFAFA` + black mark), the Pro login lockup (§11).

## 2. UX & flows

### 2.1 The composition (the timeline is the asset's markers)
560 × 380, 25 fps, frames 0–142. Shape layers only: `redraw` plus nine glyphs
`M W L_y L_e L_l L_i L_P L_r L_o`. Three markers, which the screen reads instead
of hard-coding frames — a designer's replacement only has to keep them:

| Marker | Frames | Time | What it is |
|---|---|---|---|
| `intro` | 0–74 | 2.96 s | « MyWeli Pro » draws, holds, M/W morph into the mark — plays once |
| `wordmark` | 12–38 | 1.04 s | the hold where every letter is at 100 % (≥ 1 s, pinned) |
| `loop` | 74–142 | 2.72 s | the mark redraw only — repeats while the session is pending |

It is the consumer `myweli_loader_mixed.json` with **18 frames inserted** for the
wordmark hold; the mark end-state and the `redraw` layer are byte-identical
after re-timing (pinned). M/W stay at 100 % until frame 72, where `redraw` is
already in — the consumer file's blank hand-off frame is not reproduced (§11).

### 2.2 Two gates, side by side
The screen routes when **both** the intro has had its time and the session is
known — never one chained behind the other. Signed in → `/pro/dashboard`
(`/pro/staff` for a Collaborateur); signed out → `/pro/login`. Session first →
it waits for the intro end (2.96 s). Intro first → the `loop` segment repeats
(the mark, never the wordmark again) until the session lands.

### 2.3 A bounded wait
The session load is two stages: **restore** (secure storage: the stored
session, the cached membership, the R6 salon selection — `auth.restored`) and
the **live refresh** (`GET /me/provider` on an `http.Client` with no timeout).
Once the intro is over and the restore is done, the refresh gets
**`ProSplashScreen.sessionDeadline` = 1.5 s**; past it the screen routes on the
stored session and the refresh carries on in the background.

*Why 1.5 s:* the refresh starts in `ProAuthProvider`'s constructor, before
`runApp` — so at the deadline it has had the whole intro (2.96 s), the time to
the first frame, and 1.5 s more: ≥ 4.5 s for one request (plus a token refresh).
A healthy 3G round trip is well under that; past it the network is the problem
(captive portal, dead link), and waiting longer only stalls the user. It is the
version gate's bound for the same reason (`ClientVersionGate.deadline`,
client-version-gate.md §7). It is a bound, not a delay: a refresh that lands
inside the window routes at once.

*What routing early costs:* the first screen is shaped by the **cached**
membership. A later refresh reshapes it in place (`notifyListeners`), and a
revoked member is still signed out by it (`_signOutRevoked` → `/pro/login`);
every call is re-authorized server-side (T38), and a 403 probes the membership
(`ProAccessGuard`). Not handled: a role change between owner-shaped and staff
shells while the app was closed lands on the old shell until the next start.
*The restore is not bounded* — local I/O, and without it there is no right route.

### 2.4 Reduced motion (SYSTEM.md §9.1)
Same boot, no movement. During the intro the screen holds the **wordmark** still
(the middle of the `wordmark` hold) for the intro's full 2.96 s — a content
hold, not motion, so it is not collapsed. If the session is still pending at the
intro end, the still becomes the **end frame** (the finished mark, where every
pass of the loop comes to rest) and a **« Chargement… »** caption appears below
it — `BrandLoader`'s string, style (`bodySmall`, `textSecondary`) and gap
(`spacingS`), in a `Semantics(liveRegion: true)` so it is announced as it
appears — a frozen logo and a broken screen look identical. Turning the flag on
mid-loop holds the end frame, never the wordmark. The caption hangs below the
mark without moving it off the native splash's centre; one line at 200 % text.

### 2.5 Broken asset
A bundled asset that fails to decode is a broken build, but must not strand the
user: the still brand mark (`myweli_mark_black.svg`, as `BrandLoader` holds it —
never typed text) stands in, the intro gate opens at once, and the session is the
only gate left. While it is pending the still says « Chargement… » too.

### 2.6 A notification that cold-starts the app
`getInitialMessage` delivers the tap before `runApp`; the handler buffers it
(push-notifications-app.md §10.4). The replay used to fire on **sign-in** — which
happens during the splash — pushing the page above `/pro/splash`; the splash's
`context.go` then replaced the whole page stack, the booking with it. Found by
reading in review; reproduced by mutation (§8, M12). The sign-in screen had the
same shape: the session notifies before `ProLoginScreen._finish` goes.

**Fix:** `landedPushHandler` replays only when signed in **and** the router has
**landed** — mounted, and its top location not in `ProRouter.launchPaths`
(`/pro/splash`, `/pro/login`, `/pro/register`, the screens that hand over with a
`go`). It listens to the session and to the router delegate, so the `go` itself
triggers the replay (in a microtask — never inside the router's own
notification). The booking opens above the dashboard; « retour » lands there.
Nothing can strand the user: the splash routes on its own (§2.3), and a tap that
never replays leaves them where the splash put them. `navigate` issues the push
without awaiting it — a push completes on *pop*, and `FcmMessageBridge.init`
awaits the launch tap's handling, which `main_pro.dart` awaits before `runApp`.

### 2.7 Copy & semantics
« MyWeli Pro » (an image node over the animation); « Chargement… » (live
region) only while a still is waiting.

## 3. API & contract — none (the refresh is the existing `GET /me/provider`)

## 4. The asset — the « Pro » glyphs and the name
- **The name is the owner's choice: « MyWeli Pro »** — the name the app ships
  under (`APP_DISPLAY_NAME = "MyWeli Pro"`, Android `app_name`, `MaterialApp.title`,
  the store listing). The brand book calls the professional side **« MyWeli
  Business »** (`docs/brand/MyWeli_Brandbook.pdf` p. 6). The book is not edited;
  the deviation is recorded in [branding-integration.md](branding-integration.md) §2.
- **The kit has no « Pro ».** Its wordmark/lockup SVGs spell « MyWeli » only. The
  brand book sets y·e·l·i in **Poppins Medium** (p. 15), so « Pro » was drawn from
  Poppins Medium outlines — the font is under the SIL Open Font License 1.1,
  which restricts redistributing the font, not artwork made with it. The file
  carries **outlines only**: no font, no text layer, no `chars` (pinned).
- **What the test pins is the fit, not the provenance:** P and r on the `l`
  baseline, P's cap height = M's, r's x-height = e's, P's stem = l's stem (±0.3 —
  the Medium weight), « Pro » fading exactly like the lowercase, a real word
  space (> 2 × the letter gap), the whole word re-centred on the canvas. The
  outlines were not re-derived from the font file in CI (none is in the repo).

## 5. Architecture — one session load
`ProAuthProvider`'s constructor starts the load and keeps it as **`ready`**
(`late final`); `restored` completes once the stored session is read. The splash
**awaits `ready`/`restored` and never calls `loadCurrentProvider()`**: `main_pro`
builds the provider, then awaits the version gate (up to 1.5 s) before `runApp`,
so a fast load is often over before the splash exists — and a second call would
re-read the session and re-fire `GET /me/provider` + `/me/salons` at cold start,
exactly when the access token tends to be expired
([session-refresh.md](session-refresh.md)). `loadCurrentProvider()` stays for
explicit reloads and de-duplicates concurrent callers. Neither future errors:
the load catches its own failures, and the splash swallows errors anyway.

## 6. Security — no new surface
Same deep-link allowlist (`kProRoutePrefixes`) and R6 salon switch before the
replay; routing on the cached membership is UI shaping only (§2.3).

## 7. Performance
Earliest route 2.96 s after the first frame (was a fixed 2 s *then* the whole
load); worst case with a hanging network 2.96 + 1.5 s. Vector JSON, one decode.

## 8. Testing — and the mutations watched red
Asset contract (`pro_open_animation_asset_test`), screen (`pro_splash_screen_test`),
provider (`pro_auth_load_test`), reduced motion (`motion_test` §9 Pro group),
deep link (`pro_cold_start_deep_link_test`), goldens `pro_splash_wordmark` /
`pro_splash_end` (unchanged: both still match the committed PNGs, run locally
with `MYWELI_GOLDEN_LOCAL=1`). Each guard was committed, then broken:

| # | Broke | Went red |
|---|---|---|
| M1 | splash calls `loadCurrentProvider()` instead of `ready` | 3 splash tests (one load ×2, deadline) |
| M2 | `ready` re-runs the load | `ready IS the constructor's load` |
| M3 | `restored` only after the live refresh | `restored lands … before the live refresh` |
| M4 | no deadline (`await ready`) | refresh hangs → deadline; stored session waited |
| M5 | deadline = 0 | refresh hangs → deadline; refresh inside the window |
| M6 | route without awaiting the restore | stored session waited for; intro-first loop |
| M7 | no caption | 4 motion tests + broken asset |
| M8 | caption not a live region | past the intro: … « Chargement… » |
| M9 | caption in a Column (moves the mark) | the caption leaves the mark in place |
| M10 | still stays the wordmark after the intro | past the intro; turned on mid-loop |
| M11 | caption during the intro | no caption during the intro |
| M12 | replay on sign-in alone (the old gate) | all 3 cold-start sequences; end state: the booking is gone |
| M13 | `/pro/login` not a launch path | signed out: waits through the login |
| M14 | `navigate` awaits the push | a tap's handling never waits for a pop |
| M15 | an unmounted router counts as landed | a tap before `runApp` on a restored session |
| M16 | broken asset never flags itself | broken asset says « Chargement… » |

## 9. Rollout & 10. Definition of done
No flag; ships with the Pro app. Done: analyze 0, format, the tests above,
goldens unchanged, spec indexed and cross-linked, roadmap entry, branding P5.
**Not done here — device verification:** the native splash → animation hand-off,
a cold-start tap on a booking notification, airplane mode (the deadline),
VoiceOver/TalkBack with Reduce Motion on.

## 11. Follow-ups (not in this part)
- **The consumer app has the same cold-start defect, by reading (not reproduced):**
  `main.dart` replays on sign-in while `/splash` holds 3.8 s, then `go`s to
  `/home`. `landedPushHandler` is generic — wire it there with its launch paths.
- **The consumer asset's blank frame.** `myweli_loader_mixed.json` drops M/W to
  0 over frames 53→54 while `redraw` comes in at 54; lottie renders index 54 a
  hair early, so one 40 ms frame is empty. The Pro file holds M/W to 72 with
  `redraw` in at 72; the consumer file is untouched.
- **The Pro login lockup.** `ProLoginScreen` shows the « MyWeli » vertical
  lockup; a « MyWeli Pro » lockup needs these glyphs as an SVG (a brand asset).
- **A role flip while the app was closed** (§2.3) lands on the old shell after a
  deadline route; re-routing on a shell change is not built.
