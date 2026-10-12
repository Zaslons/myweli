# The Pro open animation — « MyWeli Pro », then the app

| | |
|---|---|
| **Status** | **Built** (2026-10-11; review fixes 2026-10-12; the full spin, both apps, 2026-10-12 — §2.2, §2.8) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-12 |
| **PRD ref / phase** | Launch polish — branding P5 (Pro flavour) · V1 |
| **ROADMAP entry** | [2026-10-11-pro-open-animation](../roadmap/entries/2026-10-11-pro-open-animation.md) · [2026-10-12-splash-full-spin](../roadmap/entries/2026-10-12-splash-full-spin.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Governs** | `pro_splash_screen.dart` · `splash_screen.dart` (§2.8) · `open_animation_player.dart` · `myweli_loader_mixed_pro.json` · `myweli_loader_mixed.json` (§2.8) · `ProAuthProvider.ready`/`.restored` · `landed_push_handler.dart` · `ProRouter.launchPaths` |

## 1. Goal & scope

The Pro app opened on a bare `#FAFAFA` screen for a fixed 2 s, then started the
session load — so a fast network still waited 2 s, and a slow one waited 2 s
*plus* the load. Now `/pro/splash` plays the brand's open animation opening on
**« MyWeli Pro »** (the consumer splash's `loader_v2` *mixed* cut, extended with
the word « Pro »), and routes as soon as the animation AND the session allow.

**In scope:** the asset, the screen, its gates, reduced motion, the broken-asset
fallback, the session-load hand-off, a notification that cold-starts the app.
**Out of scope:** the native launch screen (shared, already `#FAFAFA` + black
mark), the Pro login lockup (§11).

**The full spin (owner, Pro build 560, 2026-10-12).** « The animation plays but
closes too fast, we can't see the end » — decision: **« we should see at least
one spin of the logo », in both apps.** Measured, not guessed: the Pro screen
routed at the `intro` marker (2.96 s) once the session was ready, so the spin
(the mark erasing and redrawing, frames 74→142) was never seen; the consumer
screen held a fixed 3800 ms against a 4.96 s file and left at frame ≤ 95 — on a
mostly erased mark. Both now play the **whole file once** and rest on the
finished mark before leaving (§2.2, §2.8). The consumer splash is therefore in
scope from this change on.

## 2. UX & flows

### 2.1 The composition (the timeline is the asset's markers)
560 × 380, 25 fps, frames 0–142. Shape layers only: `redraw` plus nine glyphs
`M W L_y L_e L_l L_i L_P L_r L_o`. Three markers, which the screen reads instead
of hard-coding frames — a designer's replacement only has to keep them:

| Marker | Frames | Time | What it is |
|---|---|---|---|
| `intro` | 0–74 | 2.96 s | « MyWeli Pro » draws, holds, M/W morph into the mark |
| `wordmark` | 12–38 | 1.04 s | the hold where every letter is at 100 % (≥ 1 s, pinned) |
| `loop` | 74–142 | 2.72 s | **the spin**: the mark erases (74→104, trim start) and redraws (104→142, trim end) |

Frame 142 — the end frame — is **the finished mark**, the same picture as 72–74,
so a spin can start again from 74 without a jump. The whole file is **142 frames,
5.68 s** (lottie plays `op − 0.01`: 5.6796 s).

It is the consumer `myweli_loader_mixed.json` with **18 frames inserted** for the
wordmark hold; the mark end-state and the `redraw` layer are byte-identical
after re-timing (pinned). M/W stay at 100 % until frame 72, where `redraw` is
already in — no blank hand-off frame (the consumer file had one; fixed, §2.8).

### 2.2 The first pass, then the gate — and the clock is the ticker
**A pass** plays from a start frame to the **end frame** (the finished mark) and
then **rests** there for **`OpenAnimationPlayer.rest` = 500 ms**: the finished
mark held still long enough to be seen. A screen may leave only when a pass is
over — so **the user always leaves on the finished mark**.

1. **The first pass is the whole file** — wordmark → morph → spin (erase +
   redraw) → end frame, 0→142 — plus the rest. **The gate opens only then:
   6.18 s after the first frame** (5.68 + 0.5). It replaces the old gate at the
   `intro` marker (2.96 s), which cut the spin off.
2. **At the gate, the session decides.** Signed in → `/pro/dashboard`
   (`/pro/staff` for a Collaborateur); signed out → `/pro/login`.
   - **Settled** (`auth.ready` done): the controller is already **stopped on
     the end frame** (value 1.0) — nothing restarts — and the screen routes.
   - **Pending**: the screen keeps **spinning** — each spin is a pass from the
     `loop` marker's start to the end frame, plus its rest; never the wordmark
     again — and routes **at the end of the first spin after which it may
     leave** (§2.3). Never mid-spin: always on the finished mark.

**The clock is the controller, not the wall.** With motion on, a pass is over
when the ticker has *drawn* its end frame (`animateTo(1)` completing on a
frame), and the rest is counted from that frame. The old screen ran a `Timer`
beside the animation; a wall-clock timer keeps running when frames do not — a
slow first frame on a cold start, a janky low-end Android, an app sent to the
background mid-splash — and then routes on a mark the user never saw drawn. The
ticker cannot get ahead of what is on screen, because it *is* what is on screen;
starting it from the first frame that shows the composition is the ticker's own
behaviour (it starts on the next frame after `animateTo`). The controller is
`AnimationBehavior.preserve`: it is the gate's clock, so the framework's 5 %
scale under the OS flag must never reach it (§9.1, "a content timer must not be
collapsed") — though under that flag nothing animates anyway (§2.4).

The rest is a content hold, not motion (SYSTEM.md §9: how long a still is
*looked at*); it keeps its literal with a `// ds-ignore` and its reason, as the
session deadline does. One constant, shared by both apps (§2.8).

### 2.3 A bounded wait — counted from the gate, decided at a pass end
The session load is two stages: **restore** (secure storage: the stored
session, the cached membership, the R6 salon selection — `auth.restored`) and
the **live refresh** (`GET /me/provider` on an `http.Client` with no timeout).
Once the gate is open and the restore is done, the refresh gets
**`ProSplashScreen.sessionDeadline` = 1.5 s**; past it the screen may route on
the stored session and the refresh carries on in the background. **"May"**:
it leaves at the next pass end (§2.2), so a pending session costs **exactly one
more spin** (2.72 s + 0.5 s rest = 3.22 s) — the 1.5 s deadline is shorter than
a spin, so it only decides whether the screen leaves at the first spin's end or
keeps spinning for the stored session. A refresh that lands mid-spin routes at
that spin's end, never mid-spin.

*Why 1.5 s still:* the refresh starts in `ProAuthProvider`'s constructor, before
`runApp` — so by the gate it has had the whole first pass (5.68 s), the rest,
the time to the first frame, and then 1.5 s more. A healthy 3G round trip is
well under that; past it the network is the problem (captive portal, dead
link), and waiting longer only stalls the user. It is the version gate's bound
for the same reason (`ClientVersionGate.deadline`, client-version-gate.md §7).

*What routing early costs:* the first screen is shaped by the **cached**
membership. A later refresh reshapes it in place (`notifyListeners`), and a
revoked member is still signed out by it (`_signOutRevoked` → `/pro/login`);
every call is re-authorized server-side (T38), and a 403 probes the membership
(`ProAccessGuard`). Not handled: a role change between owner-shaped and staff
shells while the app was closed lands on the old shell until the next start.
*The restore is not bounded* — local I/O, and without it there is no right route:
while it is missing the screen keeps spinning.

### 2.4 Reduced motion (SYSTEM.md §9.1) — the same boot, held still
Same boot, no movement: **the same pass ends, the same gate, the same length**.
Nothing ticks, so the passes are held on timers (the first one started from the
frame that first shows the still — never from the decode). During the `intro`
portion the screen holds the **wordmark** still (the middle of the `wordmark`
hold, 2.96 s); for the rest of the first pass and its rest it holds the **end
frame** (the finished mark, 2.72 s + 0.5 s) — the gate opens at 6.18 s, as with
motion. A pending session's spins are held as end-frame stills of the same
length, so a reduced-motion user leaves at the same moment as everyone else.
The holds are content time, not motion, so they are not collapsed.

**« Chargement… » only while pending after the gate** — `BrandLoader`'s string,
style (`bodySmall`, `textSecondary`) and gap (`spacingS`), in a
`Semantics(liveRegion: true)` so it is announced as it appears — a frozen logo
and a broken screen look identical. Never during the first pass: nothing is
waiting yet. The caption hangs below the mark without moving it off the native
splash's centre; one line at 200 % text.

**The flag flipped mid-pass.** On: the picture freezes on the still for where
the pass is (the wordmark inside the intro, the end frame after it) and the
frames it had left are held — the boot keeps its length. Off: the pass carries
on as motion from the still on screen (from the end frame, that is the pass's
end). During a rest nothing changes — it is the finished mark in both modes.

### 2.5 Broken asset — unchanged
A bundled asset that fails to decode is a broken build, but must not strand the
user: the still brand mark (`myweli_mark_black.svg`, as `BrandLoader` holds it —
never typed text) stands in, **the gate opens at once**, and the session is the
only gate left — with no pass to end on, the screen leaves as soon as the
session allows (§2.3's rule without the spin). While it is pending the still
says « Chargement… » too.

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
region) only while a still is waiting after the gate. The consumer splash says
« MyWeli » the same way (§2.8).

### 2.8 The consumer splash — the same rule (branding-integration.md P4)
`/splash` (`SplashScreen`) plays `myweli_loader_mixed.json` through the same
`OpenAnimationPlayer`: **the whole file once** — « MyWeli » draws, holds, M/W
morph into the mark, the mark spins (erase 56→86, redraw 86→124) — then **the
rest** on the end frame, **stopped there** (no `repeat`), then `go('/home')`.
124 frames: **4.96 s + 0.5 s = 5.46 s** after the first frame. No session to wait
for (browsing needs no sign-in), so no loop, no deadline, no caption.

| Marker | Frames | Time | What it is |
|---|---|---|---|
| `intro` | 0–56 | 2.24 s | « MyWeli » draws, holds, M/W morph into the mark |
| `wordmark` | 12–20 | 0.32 s | the hold where every letter is at 100 % — **added** by this change (metadata only: no frame of the picture moves), so reduced motion has a wordmark still to hold |
| `loop` | 56–124 | 2.72 s | the spin — played once here, inside the first pass |

- **No wall-clock hold.** The fixed 3800 ms `Future.delayed` is gone — it left at
  frame ≤ 95, on a mostly erased mark, and ran on regardless of frames.
- **Reduced motion:** the « MyWeli » wordmark still for the `intro` portion
  (2.24 s), then the finished-mark still for the rest of the file and the rest
  (3.22 s) — the same 5.46 s. It used to hold the end frame for 3800 ms
  (`AlwaysStoppedAnimation(1)`): right frame, wrong length, and no wordmark.
- **Broken asset:** it had no `errorBuilder` — a failed decode rendered nothing
  for 3.8 s. Now the still brand mark (`myweli_mark_black.svg`, as the Pro
  screen) stands in and the screen leaves after **one rest** (0.5 s): a short,
  bounded hold, so a broken build never strands the user and never shows a
  one-frame flash either.
- **Semantics:** « MyWeli », an image node over the animation (it had none).
- **The blank hand-off frame, fixed in the file.** M/W dropped to 0 over frames
  53→54 while `redraw` came in at 54; lottie draws index 54 at 53.996 (`op −
  0.01`), where `redraw` is not yet in and M/W are at ~0 % — one empty 40 ms
  frame mid-morph. M/W now hold 100 % to **54** and drop over 54→55, exactly as
  the Pro file holds them to 72 with `redraw` in at 72: one frame where both
  draw the same finished mark. Pinned by keyframe AND by rendering the hand-off
  frames as lottie draws them (`open_animation_asset_test`).
  `myweli_loader_mixed_white.json` carries the same defect but is **not used**
  (reserved for dark mode, branding-integration.md §2) — left untouched (§11).

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

## 5. Architecture — one clock, one session load
**`OpenAnimationPlayer`** (`lib/screens/splash/open_animation_player.dart`)
owns the `AnimationController` and plays passes (§2.2): `play(composition,
from:)` completes after the end frame *and* the rest. It reads the markers
(`intro`, `wordmark`, `loop` — names shared by both files), holds the
reduced-motion stills on timers (§2.4), and switches between the two mid-pass
when the flag flips. Both splash screens use it; neither keeps a timer of its own
for the animation. The Pro screen adds the session gate (§2.3) and the caption.

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
**The boot is longer on purpose** (owner decision, §1): the Pro app leaves at
**6.18 s** after the first frame at the earliest (was 2.96 s; before this spec a
fixed 2 s *then* the whole load); worst case with a hanging network **9.40 s**
(the gate + one spin, was 2.96 + 1.5 s). The consumer app leaves at **5.46 s**
(was 3.8 s). The session load still runs underneath from before `runApp`, so a
slow network costs at most one extra spin. ROADMAP Part 6's cold-start budget
(p95 < 3.5 s) is time to the first frame, which this does not move — but the
time to the first *usable* screen is now ≥ 5.46 s on every open; recorded as an
owner trade-off (§11). Vector JSON, one decode; the ticker runs only while a
pass plays (stopped on the end frame during every rest).

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

**The full spin (2026-10-12).** New: `splash_screen_test` (the consumer
screen), `open_animation_asset_test` (the consumer file's markers and keyframes,
and **both files rendered frame by frame** with `LottieDrawable` — the ink
counted on every frame from the wordmark to the spin, and the end frame
byte-compared with the spin's first frame); the shared timeline moved to
`test/support/open_timeline.dart` (`OpenTimeline.pro()` / `.consumer()`,
`pumpFirstFrame`). Every Pro test that pumped `timeline.intro` now plays the
first pass and its rest. Goldens `pro_splash_wordmark` / `pro_splash_end` still
match the committed PNGs (run locally with `MYWELI_GOLDEN_LOCAL=1`, compared,
not regenerated); the end-frame golden now reaches the end frame by playing the
pass instead of setting the controller. Each guard was committed, then broken,
then restored with `git checkout` and the tree checked clean:

| # | Broke | Went red |
|---|---|---|
| M17 | the Pro gate back at the `intro` marker (build 560) | session first → the spin plays…; the ticker clock; spins from `loop`; lands mid-spin; refresh hangs; stored session waited |
| M18 | `rest` = 0 | Pro session first (the 400 ms floor); consumer whole file — red on the written floor, not on the constant read back |
| M19 | a wall-clock `Timer` ends the pass, beside the ticker | exactly the two « the clock is the ticker » tests (Pro, consumer) |
| M20 | the pass end restarts the animation (the old `repeat`) | 13 tests: Pro session first (stopped, no frame scheduled), consumer whole file, and every test that waits past a pass end |
| M21 | pending: leave as soon as the session allows, mid-spin | lands mid-spin; refresh hangs |
| M22 | pending: the spin replays from frame 0 (the wordmark) | spins from `loop`; lands mid-spin; refresh hangs |
| M23 | no session deadline | refresh hangs; stored session waited for |
| M24 | a settled session still spins once at the gate | the 3 routing decisions, no second load ×2, session first, the ticker clock |
| M25 | reduced motion: the still's timer starts at the decode, not the first frame | « the still is timed from the frame that SHOWS it » — **survived twice first**: a pump before the delay made it the first frame (no gap), then an onstage-only finder missed the page built offstage one frame earlier. Both fixed; then red |
| M26 | reduced motion: the wordmark held for the whole pass (no switch to the mark) | consumer « SHOWS the brand »; Pro « no caption during the first pass » (end frame past the intro) |
| M27 | reduced motion: a flip mid-pass restarts the hold from the top | turned on mid-pass (boot length); turned on mid-spin |
| M28 | reduced motion: the holds collapse to 0 | 6 motion tests (consumer + Pro boot length, stills, first-frame timing) |
| M29 | consumer: a broken asset never leaves | consumer broken asset |
| M30 | consumer: a broken asset leaves at once | consumer broken asset (« held for a rest, not flashed ») |
| M31 | consumer: no « MyWeli » label | a screen reader hears « MyWeli » |
| M32 | the file's M/W back to 100 → 0 over 53→54 | the keyframe pin AND the render: « frame 54 … 0 of the finished mark's 2283 ink pixels » |
| M33 | the file loses its `wordmark` marker | markers; the hold; decode; the hand-off render; consumer « SHOWS the brand » |
| M34 | caption whenever reduced (not only pending past the gate) | no caption during the first pass |

Re-run on the retimed tests: **M12** (replay on sign-in alone) — all 3 cold-start
sequences red again; **M7** (no caption) — 4 motion tests + broken asset red.

## 9. Rollout & 10. Definition of done
No flag; ships with both apps. Done: analyze 0, format, the tests above,
goldens unchanged, spec indexed and cross-linked, roadmap entries
(2026-10-11-pro-open-animation, 2026-10-12-splash-full-spin), branding P4/P5.
**Not done here — device verification:** the native splash → animation hand-off,
a cold-start tap on a booking notification, airplane mode (the deadline),
VoiceOver/TalkBack with Reduce Motion on — and, for the full spin, that the
spin and the rest read well on a real phone in both apps (the timing is pinned
in fake time; nothing here has watched it on a screen).

## 11. Follow-ups (not in this part)
- **The consumer app has the same cold-start defect, by reading (not reproduced):**
  `main.dart` replays on sign-in while `/splash` plays its first pass (5.46 s), then `go`s to
  `/home`. `landedPushHandler` is generic — wire it there with its launch paths.
- ~~**The consumer asset's blank frame.**~~ Fixed 2026-10-12 (§2.8).
  **`myweli_loader_mixed_white.json` still has it** (M/W 100 % → 0 over 53→54,
  `redraw` in at 54) — unused today; fix it the same way (hold M/W to 54) the
  day dark mode wires it, and extend `open_animation_asset_test`'s hand-off
  render to it.
- **The boot length** (§7): every open now costs ≥ 5.46 s (consumer) / 6.18 s
  (Pro) before the first usable screen, by the owner's decision. If that proves
  too long in use, the lever is the file (a shorter wordmark hold or spin), not
  the screen — the screen only promises to show the file through once.
- **The Pro login lockup.** `ProLoginScreen` shows the « MyWeli » vertical
  lockup; a « MyWeli Pro » lockup needs these glyphs as an SVG (a brand asset).
- **A role flip while the app was closed** (§2.3) lands on the old shell after a
  deadline route; re-routing on a shell change is not built.
