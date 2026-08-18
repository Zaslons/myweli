# Client version gate — design spec

| | |
|---|---|
| **Status** | Approved · backend slice building |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-08-18 |
| **PRD ref / phase** | LAUNCH.md §5.3 · V1 (launch gate) |
| **ROADMAP entry** | added when the first slice ships |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails |
| **Related** | [LAUNCH.md](../LAUNCH.md) §1.4 §5.3 · [SYSTEM.md](SYSTEM.md) §11 §13 §17 · [mobile-store-submission.md](mobile-store-submission.md) |

## 1. Goal & scope

**You cannot roll back an app release.** A bad version sits on people's phones
until they choose to update, and some never will (LAUNCH.md §1.4). A minimum
supported version is the only lever that reaches a phone we cannot otherwise
reach — and it is the one gate that is **cheaper before the first release than
ever again**: a v1.0 shipped without the check can never be told to update, so
the floor would only ever apply from v1.1 onward. No build has been published,
so this is the last moment it is free.

**In scope**, as three slices:

1. **Backend** — schema, repository, verdict service, the public endpoint, and an
   audited admin control.
2. **Mobile** — the gate in `main()` for both flavours, the blocking screen, the
   dismissible nudge, and the prerequisites (real version reporting, the Android
   `<queries>` fix).
3. **Admin console** — a screen to read and set the floors.

**Out of scope:** maintenance mode / kill switch (same channel, genuinely
different decision — it blocks *everyone* including the current build); a general
remote-config service; staged or per-user floors (one integer per app × platform,
or the floor becomes a targeting system); `X-App-Version` on every request.

## 2. What exists today

Nothing. Verified 2026-08-18:

| | |
|---|---|
| Client version sent to the API | **never** — no interceptor, no shared client; 16 `Api*Service` classes each build their own `http.Client` |
| App's own version | `AppConstants.appVersion` — a hand-typed `'1.0.0'`, pinned to nothing, no build number |
| `package_info_plus` | in the tree **transitively** via `sentry_flutter`; imported by no Dart file |
| Boot network calls | **zero**. Splash burns a hard-coded 3800 ms, then goes to `/home` |
| Android `<queries>` | `PROCESS_TEXT` only — **no `https`, no `market`** (`ROADMAP.md:200` recorded this TODO and it was never done) |

## 3. The constraints that force the design

- **C1 — the iOS update URL is unknowable today.** Play's listing key *is* the
  `applicationId`; iOS needs the numeric `adamId`, minted only when the App Store
  Connect record exists. **So the URL must be served by the backend**, or v1.1
  ships an iPhone button that opens nothing.
- **C2 — only one shape in this codebase is genuinely inescapable.**
  `misconfiguredBuildScreen()` (`main.dart:38-42`) `runApp`s and **returns**,
  before DI and before the router exists. Anything route-based loses to push
  cold-start replay, which does `AppRouter.router.push` and would stack a real
  screen on top of the gate.
- **C3 — a gate that hard-blocks on a flaky network is worse than no gate.** The
  house rule is already written (`refreshing_http_client.dart:102`): distinguish
  *"the server said no"* from *"I could not reach the server."*
- **C4 — the lever's value is its latency**, which is why the floor lives in the
  database (owner decision) rather than in an env var. An env var change is a
  revision rollout — single-digit minutes at best, and **blocked outright by a
  rollback traffic pin**, i.e. exactly during the incident you would want it.

## 4. The endpoint

```
GET /client-version?app=com.myweli.app&platform=android&build=7&version=1.0.0
→ 200 { "status": "ok" | "update_available" | "update_required",
        "updateUrl": "https://play.google.com/store/apps/details?id=…" }
```

Unauthenticated — the check runs before login. Non-GET → 405.
**`Cache-Control: no-store`**: the `/localities` precedent (`max-age=3600`) would
insert up to an hour between the decision and its effect, which defeats the point.

**The server decides; the client only renders.** Not "serve the floor and let the
client compare" — the comparison logic and the update URL are precisely the two
things you cannot patch on a client you are trying to block. Keeping both server
side means the whole policy is changeable in one place, and a v1.0 client that
only knows how to render a verdict never becomes the bug.

**Build numbers, not semver.** `pubspec`'s `+N` feeds `versionCode`,
`CFBundleVersion` and `FLUTTER_BUILD_NUMBER`, so it is one monotonic integer with
a total order and no parsing traps. `version` is carried for logs only.

**Fail open on the server too.** Unknown `app`/`platform`, missing or unparseable
`build` → `200 {"status":"ok"}`, deliberately not 400: a future flavour or a
malformed client must never be indistinguishable from an outage.

**And a platform with no `updateUrl` never blocks, whatever the floor says** —
you cannot block users you have nowhere to send. That is a unit test, not a
comment, and it is what makes shipping the mechanism before the iOS listing
exists safe.

## 5. Data model

Migration `0032_client_version_floors`:

```sql
CREATE TABLE IF NOT EXISTS client_version_floors (
  app_id            text NOT NULL,
  platform          text NOT NULL,
  minimum_build     int  NOT NULL DEFAULT 0,   -- 0 = no floor
  recommended_build int  NOT NULL DEFAULT 0,   -- 0 = no nudge
  update_url        text,                       -- NULL ⇒ never block
  updated_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (app_id, platform)
)
```

Four rows seeded at `0/0` — consumer and pro × android and iOS. **Seeded with no
floor**, so shipping the mechanism changes nobody's behaviour on day one; the
policy is a separate, deliberate act.

`update_url` is seeded for Android (derivable from the `applicationId`) and left
NULL for iOS until the App Store Connect record exists.

## 6. Security & authz

- The public endpoint is unauthenticated and takes **no** user data. It reveals
  the current floors, which is not sensitive — a client below the floor learns it
  is below the floor, which is the entire purpose.
- The admin control is `/admin/*`, so the existing middleware gates it
  (`role != 'admin'` → 403); every write is audited as `client_floor.set`.
- **Threat-model delta (BACKEND.md §7), T63:** a raised floor is a denial of
  service to every user below it. The mitigations are that it is admin-only and
  audited, that `update_url == NULL` refuses to block, and that the client fails
  open on everything except a well-formed `update_required`.

## 7. Where the check runs (mobile slice)

Kicked off at the top of `main()`, **not awaited**, so it runs concurrently with
init the app already pays for; awaited immediately before `runApp`. Added wall
clock is therefore `max(0, deadline − elapsed_init)` — usually zero.

The verdict is known **before the first frame**, so the block is decided before
the router exists, before DI-owned providers mount, and before push replay has a
router to push onto (C2). No splash change, no router change, no new escape
surface — the `misconfiguredBuildScreen()` shape exactly.

**A dedicated 1500 ms deadline.** Not `AppConstants.apiTimeout` — that is 30 s and
is referenced by nothing (dead code; its cleanup is a separate slice).

**Fail open on everything**: timeout, socket error, DNS failure, 4xx, 5xx,
unparseable JSON, missing field, **unrecognised `status`**. Only a well-formed
200 carrying `update_required` blocks. The unrecognised-status rule is the other
half of the order-sensitivity argument: v1.0's parser must treat a verdict it does
not know as `ok`, so a later server can add verdicts without breaking the oldest
clients it is trying to manage.

Stated plainly because it is the design's cost: **a device offline at every
launch is never blocked.** That is the correct trade — the backend must stay
backward-compatible with old clients anyway, so serving one is survivable;
bricking a working app on a flaky Abidjan network is not.

## 8. UX

### 8.1 Blocking screen — `update_required`

Replaces the application at `runApp`; `main()` returns. No route is ever created,
so there is nothing to pop to and no deep-link target.

Reuses **`EmptyState`**, which reads `AppColors`/`AppTextStyles` statically rather
than through `Theme.of(context)` — the property that lets it render under a
DI-less, theme-less root, the same one `build_config_guard` relies on. **No
`AppBar`** (inside a route it paints a back button, and omitting it sidesteps §21
row 79 by construction).

| Slot | Consumer | Pro |
|---|---|---|
| Icon | `Icons.system_update_outlined` @ `iconXL` | same |
| Title | « Mise à jour requise » | same |
| Body | « Cette version de MyWeli n'est plus prise en charge. Installez la dernière version pour continuer à prendre vos rendez-vous. » | « … pour continuer à gérer votre salon. » |
| Action | « Mettre à jour » | same |

**Deliberately not offered:** no dismiss, no « Plus tard », no back affordance, no
retry — SYSTEM.md §12: *the way out is a retry only when retrying can succeed*.
The only way out is the store.

**No `updateUrl`** → the identical screen with **no button**. A dead button is
worse than none. Unreachable in production thanks to §4's server-side guard, but
the client must still render it correctly.

### 8.2 Nudge — `update_available`

Dismissible, shown once per recommended build, inside the normal app. Not a
screen: a banner on the home surface, following `push_blocked_banner.dart`'s
idiom — state the fact, name the action taken outside the app.

Dismissal persists per `recommended_build` in `shared_preferences` (not secure
storage — it is not sensitive), so raising the recommendation shows it again while
re-launching does not nag.

## 9. Testing

- **Backend:** verdict unit tests (below/equal/above floor; unknown app; unknown
  platform; missing build; **NULL `updateUrl` never blocks**); route tests
  (200 shapes, 405, `no-store` header); admin route tests (audited, 403 without
  admin, 404 on unknown app×platform).
- **Mobile:** verdict-parsing unit tests including every fail-open path;
  widget tests for both surfaces with an injected URL-opener seam; `a11y/
  vertical_fit_test.dart` (the only test that sees a *vertical* overflow) and
  `layout_test.dart`; goldens `_w360` and `_w360_x2` via `./tool/update_goldens.sh`
  **on Linux only** — a Mac run skips silently and a Mac-authored baseline fails
  CI forever.

## 10. Rollout

Backend first, seeded at `0/0` so nothing changes for anyone. Mobile next. The
admin console last — until it exists the floors are set by SQL, which is
acceptable because the value being set is `0`.

## 11. Open questions

1. **iOS `updateUrl`** stays NULL until the App Store Connect record exists. The
   server-side "no URL ⇒ never block" rule means this is safe rather than
   pending, but it must be filled before an iOS floor can ever be raised.
2. **The Android `<queries>` fix is unverified on a device.** Whether
   `launchUrl(externalApplication)` currently fails without it is UNVERIFIED — no
   device run. The manifest entry lands in the mobile slice regardless.
