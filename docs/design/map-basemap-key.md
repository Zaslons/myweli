# The CARTO basemap needs a key — every map, app and web

| | |
|---|---|
| **Status** | Built 2026-10-11 on `fix/carto-basemaps-key` — **inert until the owner creates the keys** (§9). Release builds are refused until `CARTO_BASEMAPS_KEY` exists in Secret Manager, deliberately. |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-11 |
| **PRD ref / phase** | FR-DISC (map discovery), pro salon profile (pin map) · V1 |
| **ROADMAP entry** | [2026-10-11-carto-basemaps-key](../roadmap/entries/2026-10-11-carto-basemaps-key.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-web-guardrails · myweli-verification-guardrails |
| **Decision** | Owner: use a free CARTO key, stored in Secret Manager as `CARTO_BASEMAPS_KEY` (project `myweli`). §3.3 explains why that becomes **two** keys. |

## 1. Goal & scope

**The defect (reported by the owner: « the map doesn't load, it shows api key
required »).** Both app maps — the consumer « Carte » (`MapScreen`) and the
pro « Profil du salon » pin map — draw raster tiles from
`https://{s}.basemaps.cartocdn.com/light_all/…` with no key. **Since
2026-09-25 CARTO serves no raster tile without a usable key**: every such
request gets the same 256 px PNG reading « API KEY REQUIRED ·
carto.com/basemaps/apikey » on a blank background. Measured 2026-10-11
(§3.1): the old URL, the new `rastertiles/` URL, the `@2x` URL and a bogus
`?key=` all return that one image — byte-identical, `etag "wm-da89c20e77c1-light"`,
2 049 bytes. There is no keyless oracle: a typo in the style name gets the
same watermark.

**And the watermark is cached for 30 days.** It is served with
`cache-control: public, max-age=2592000, immutable`, and flutter_map's
built-in tile cache keys on the URL and honours that header. Every device
that opened a map since 2026-09-25 holds watermark tiles for the old URL.
That does not matter for this fix (the URL changes), but it would matter
**every time a keyed URL is refused later** — see §2.2 and §5.3.

**In scope**
- One shared CARTO layer for both app maps, keyed by a compile-time define,
  sending the restriction headers CARTO checks (§3.2).
- `tool/release_build.sh` reads the key from Secret Manager, refuses to build
  without it, and **probes CARTO with the exact URL and headers the app will
  send** before building (§5.4).
- The web: the key on the GL style and on every CARTO request MapLibre makes,
  when `NEXT_PUBLIC_CARTO_BASEMAPS_KEY` is set (§5.5). Vector still loads
  keyless today; CARTO says that may end.
- The post-key verification procedure for whoever holds the keys (§10).

**Out of scope**
- Moving the app to vector tiles (CARTO recommends it; flutter_map would need
  a vector plugin — a renderer change, not a key fix).
- Replacing CARTO (MapTiler etc.). Noted in [web-discovery-map.md](web-discovery-map.md) §3 as the path if volume grows.
- Builds already installed (TestFlight build 555 and earlier): they carry the
  keyless URL forever. **Prevention is not cleanup** — they show the
  watermark until replaced by a build made after this change.

## 2. UX & states

No new screen, no new copy. The visible change is the basemap itself: streets
and labels instead of the watermark.

### 2.1 What a user sees, per state

| State | Cause | What renders |
|---|---|---|
| **Basemap** | key present, CARTO accepts the headers | CARTO `light_all` tiles, `@2x` on dense screens, markers, attribution |
| **Watermark** | no key compiled in (`flutter run`, `flutter test`, CI builds) | « API KEY REQUIRED » tiles — **deliberately**. A plausible-looking fallback would hide the misconfiguration; this one names its own cause |
| **Refused** | key present but CARTO refuses the restriction headers → **HTTP 403** (CARTO FAQ: « a restricted key always returns 403 ») | no tiles: the map background, the markers and the attribution. flutter_map does not cache non-200 responses |
| **Unusable key** | revoked, mistyped, not yet activated | the watermark (a bogus key gets it with HTTP 200 — measured) — **and it is not persisted** (§5.3), so the map recovers on the next open once the key is fixed |
| **Resolving** | the first frame, while the app id is read from the OS | no tile layer for that frame; the map background shows (§5.2) |
| **Offline** | no network | tiles already in the device cache, otherwise the background — unchanged from before |
| **Quota exhausted** | > 1 M requests in a calendar month on the free commercial tier | **unknown** — CARTO does not document it (§11) |

The markers, the user dot, « Utiliser ma position », tap-to-place and the
attribution do not depend on the tiles in any state.

### 2.2 Why the watermark must never be cached

A watermark arrives as `200` with a 30-day `immutable` lifetime. If it were
stored, every phone that opened the map while a key was unusable — not yet
activated, mistyped in the secret, refused for quota — would keep showing it
**for 30 days after the fix**, under the very URL the fix makes good again.
So the app's tile cache drops any response whose `etag` starts with `wm-`
(§5.3), and ignores any such entry it already holds.

## 3. Contract — what CARTO serves, measured

### 3.1 Measured on 2026-10-11 (read-only probes, no key)

| Request | Result |
|---|---|
| `https://a.basemaps.cartocdn.com/light_all/11/1003/989.png` (the URL every shipped build uses) | 200 · `image/png` · 2 049 B · `etag "wm-da89c20e77c1-light"` · `max-age=2592000, immutable` |
| `https://basemaps.cartocdn.com/rastertiles/light_all/11/1003/989.png` | identical |
| `…/989@2x.png?key=bogus` | identical — 256 × 256, same SHA-1 as the 1× watermark |
| `https://basemaps.cartocdn.com/gl/positron-gl-style/style.json` | 200, 106 878 B |
| the same with `?key=bogus123` | **byte-identical** — the key is NOT propagated into the style's own URLs |
| style's `sprite` / `glyphs` / source | `tiles.basemaps.cartocdn.com/gl/positron-gl-style/sprite` · `tiles.basemaps.cartocdn.com/fonts/{fontstack}/{range}.pbf` · `tiles.basemaps.cartocdn.com/vector/carto.streets/v1/tiles.json` |
| `tiles.json` → tile URLs | `tiles-{a,b,c,d}.basemaps.cartocdn.com/vectortiles/carto.streets/v1/{z}/{x}/{y}.mvt` |
| one keyless vector tile | 200 · `application/x-protobuf` — vector is still keyless |

### 3.2 What CARTO documents (FAQ, read 2026-10-11, [docs.carto.com/faqs/carto-basemaps](https://docs.carto.com/faqs/carto-basemaps))

- Raster: `https://basemaps.cartocdn.com/rastertiles/<style>/{z}/{x}/{y}.png?key=KEY`.
- GL style: `https://basemaps.cartocdn.com/gl/<style>-gl-style/style.json?key=KEY` (`light_all` ↔ `positron-gl-style`).
- Website restriction: the `Referer` host must match exactly; `www.` and the
  apex are different hosts; `Referrer-Policy: no-referrer` « breaks every
  map »; MapLibre « still works » under `same-origin` because it sends an
  `Origin`; preview deployments need a wildcard **or a separate key**; a key
  that lists `localhost` **cannot also list public sites**.
- Mobile restriction: « the app must send the headers shown in the
  dashboard: `X-Android-Package` and `X-Android-Cert`, or
  `X-Ios-Bundle-Identifier` ».
- **« If you enable several restriction types, a request must pass all of
  them. »**
- A restricted key without the right header « always returns 403 ».
  Dashboard changes apply within seconds.
- Free commercial tier: 1 M tile requests per calendar month, **counted
  across all the keys on the account**.
- **Not documented:** the format of `X-Android-Cert` (SHA-1 or SHA-256,
  case, colons), whether iOS and Android are one restriction type or two, and
  `@2x` on the `rastertiles/` path (the FAQ never mentions retina for raster).

### 3.3 Consequence: two keys, and every app request carries every header

**One key cannot serve the web and the apps.** Restriction types are ANDed,
so a key restricted to `myweli.com` *and* to the apps would refuse every
request: a browser sends no bundle header and a phone sends no `Referer`.
Hence:

| Key | Restrictions | Stored as | Read by |
|---|---|---|---|
| **app key** | mobile apps: iOS `com.myweli.app`, `com.myweli.pro`; Android `com.myweli.app` + its cert, `com.myweli.pro` + its cert | Secret Manager `CARTO_BASEMAPS_KEY` (project `myweli`) | `tool/release_build.sh` → `--dart-define=CARTO_BASEMAPS_KEY` |
| **web key** | websites: `myweli.com`, `www.myweli.com` | Vercel `NEXT_PUBLIC_CARTO_BASEMAPS_KEY` (Production only — §9) | `web/lib/basemap.ts` |

**Every app request carries the iOS AND the Android headers, on both
platforms.** Whether CARTO treats "iOS apps" and "Android apps" as one
restriction type (either matches) or two (both must match) is undocumented.
Sending both sets passes under either reading with one app key; sending only
the running platform's set fails under the second reading unless the owner
makes one key per platform. Our bundle ids equal our package names, so the
set is a function of the app id alone. The headers are claims, not proofs
(§6) — sending the Android pair from an iPhone discloses nothing that is not
already public.

| Header | Value |
|---|---|
| `X-Ios-Bundle-Identifier` | the running app's id (`com.myweli.app` / `com.myweli.pro`) |
| `X-Android-Package` | the same id |
| `X-Android-Cert` | the Play App Signing SHA-1 of that package, **upper-case hex, no colons** — Google's convention for this header, which CARTO's header names copy. **UNVERIFIED for CARTO**; one function to change (`cartoAndroidCertHeaderValue`) |

The SHA-1s are the ones read off the Play-delivered artifacts
(`infra/mobile/signing-manifest.json` → `packages.<id>.playSha1`;
`com.myweli.app` → `b73647c6…156f`, `com.myweli.pro` → `94be494a…c985`),
pinned by a test against that manifest. A debug build signed with the
development keystore sends the same value — it is a constant, not something
the app measures — so a key restricted to the release certs works in debug
too.

## 4. Data model

None. No backend, no API, no migration.

## 5. Architecture

### 5.1 Files

| File | Role |
|---|---|
| `mobile/lib/core/map/carto_basemap.dart` | **Pure Dart, no Flutter import**: tile URL template, restriction headers, cert table + wire format, watermark-etag test, the probe's tile verdict. Pure so `tool/carto_probe.dart` can run it under plain `dart` and every branch is unit-testable (a `flutter test` cannot vary a `String.fromEnvironment`) |
| `mobile/lib/core/config/app_config.dart` | `AppConfig.cartoBasemapsKey` = `String.fromEnvironment('CARTO_BASEMAPS_KEY')`, empty by default |
| `mobile/lib/widgets/common/carto_basemap_layer.dart` | `CartoBasemapLayer` (the tile layer), `CartoAttribution`, `CartoWatermarkRefusingCache` |
| `mobile/lib/screens/map/map_screen.dart`, `mobile/lib/screens/provider/profile/pro_salon_profile_screen.dart` | use the two widgets; no tile URL of their own |
| `mobile/tool/carto_probe.dart` | the release-time live check (§5.4) |
| `tool/release_build.sh` | reads the secret, refuses empty, runs the probe, passes the define |
| `web/lib/basemap.ts` | `cartoStyleUrl(key)`, `cartoTransformRequest(key)` |
| `web/components/map/salon-pin.tsx` | `MAP_STYLE` + `MAP_TRANSFORM_REQUEST` from `NEXT_PUBLIC_CARTO_BASEMAPS_KEY`; all three `<Map>`s pass both |

### 5.2 The app layer

- URL: `https://basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}{r}.png?key=<key>`;
  `{r}` → `@2x` (flutter_map server retina, as before). No `{s}` subdomains —
  CARTO's documented form has none, and HTTP/2 makes sharding pointless. The
  key is query-encoded, so it can never be read as a `{placeholder}`.
- **No key → the same URL without `?key=`**, i.e. the visible watermark
  (§2.1). Not a silent fallback, not a crash.
- The app id comes from `PackageInfo.fromPlatform().packageName` — the bundle
  id on iOS, the package on Android, both what the OS actually installed —
  rather than from the entry point. The plugin caches it after the first call;
  the layer renders nothing until it resolves (one frame). If it throws (no
  platform: widget tests), the layer still renders, with no restriction
  headers — a restricted key then refuses, which is the visible failure.
- `userAgentPackageName` becomes that id. It was the stale
  `com.sadreddine.myweli` on both screens.
- **One `NetworkTileProvider` per layer lifetime.** The old code built a new
  provider (and HTTP client) on every rebuild of `MapScreen`, because a
  `TileLayer` without `tileProvider` constructs a default one in its
  initializer, and only the last one is ever disposed.
- Attribution unchanged: « © OpenStreetMap contributors » · « © CARTO ».

### 5.3 The watermark-refusing cache

`CartoWatermarkRefusingCache` wraps flutter_map's built-in cache (resolved
lazily, exactly as the tile provider would): `putTile` drops metadata whose
`etag` is `wm-…` (strong or weak), `getTile` reports such an entry as absent.
Everything else is delegated. A refused tile (403) was never cached in the
first place.

### 5.4 The release-time probe

`release_build.sh` already treats "a build that cannot read what it needs" as
a build that must not happen (the Sentry DSN, the build number). The key gets
the same rule, and one more: **a key CARTO refuses is as bad as no key** —
that is precisely the shipped defect. So before compiling, the script runs

```sh
CARTO_BASEMAPS_KEY=… dart run tool/carto_probe.dart --app-id com.myweli.pro
```

which fetches the Abidjan tile (`11/1001/993`) at 1× and `@2x` with **the
same pure functions the app uses** for the URL and headers, and fails unless
each is `200`, `image/png`, not a `wm-` etag, and 256 / 512 px wide. The key
travels in the environment and is never printed (the URL is shown with
`key=…`). One probe per build covers both platforms, because the header set
does not depend on the platform (§3.3). Cost: 2 of the 1 M monthly requests.

The probe is also how the open questions of §3.2 get answered: the first
release build after the key exists either passes, or says which of the two
URLs failed and how.

### 5.5 The web

- `MAP_STYLE` = `cartoStyleUrl(NEXT_PUBLIC_CARTO_BASEMAPS_KEY)`: the style
  URL with `?key=` when set, the keyless URL otherwise (today's behaviour).
- `MAP_TRANSFORM_REQUEST` = `cartoTransformRequest(key)`: appends `key=` to
  every request whose host is `basemaps.cartocdn.com` or a subdomain of it,
  unless the URL already carries one; `undefined` without a key. **Needed
  because the style does not propagate the key** (§3.1): keying only
  `style.json` would leave sprites, glyphs, `tiles.json` and every vector
  tile keyless the day CARTO extends the requirement. The host test is
  anchored, so the key never reaches another origin (our API included).
- CSP: unchanged and sufficient — every host above is under
  `https://*.cartocdn.com` in `connect-src`, and a query string is not part
  of CSP matching. `web/tests/csp.test.ts` now pins the measured style hosts,
  which no source walk can see.
- `Referrer-Policy: strict-origin-when-cross-origin` (next.config.mjs) is what
  lets a website-restricted key work; `no-referrer` would refuse every
  request. Already pinned by `tests/e2e/served-html.spec.ts`.

## 6. Security

- **A basemap key is public by construction**: it is compiled into every app
  binary and inlined into the web bundle. Secret Manager keeps it out of git
  and out of shell history; it does not make it secret.
- **The restrictions bound casual reuse, not determined abuse.** Bundle ids
  and package names are public; the signing-cert SHA-1 is readable from any
  APK. Anyone can replay our headers. What the restrictions buy is that a key
  scraped from a page or a binary does not work in someone else's site or app
  without deliberate effort — and the quota is shared across all our keys
  (§3.2), so that effort would cost us maps, not money (free tier: no billing
  method attached — UNVERIFIED, owner to confirm when creating the account).
- Never printed: the script's progress lines name the key, never its value
  (a test pins that no `echo` line references it); the probe redacts it.
  `--dart-define=…` is visible in `ps` on the build machine, as the Sentry DSN
  already is.
- The web transform only ever adds the key to CARTO hosts (anchored match,
  tested against a look-alike host).

## 7. Performance

- One platform-channel call per layer (`PackageInfo`, cached by the plugin
  after the first). One frame without tiles on first open.
- One `NetworkTileProvider` per layer instead of one per rebuild (§5.2).
- No subdomain sharding: a single HTTP/2 connection.
- Quota arithmetic, for planning only: a phone-sized viewport needs roughly
  15–30 tiles per settled view, more while panning — on the order of 30 000
  map opens a month inside the free 1 M. Request counts per open are
  UNMEASURED; read the dashboard after launch.

## 8. Testing

| Test | Holds |
|---|---|
| `test/unit/carto_basemap_test.dart` | URL with/without key, trimming, encoding · header set per app id, unknown id (no cert), no id (nothing) · cert wire format · **the cert table equals `signing-manifest.json`'s `playSha1`** · watermark-etag detection (strong, weak, real) · the probe verdict (403, watermark, non-PNG, wrong retina width, good) |
| `test/widget/carto_basemap_layer_test.dart` | the real layer in a real `FlutterMap`: the URL flutter_map would fetch for a tile (`@2x`, `?key=`), every restriction header and the User-Agent on the provider, no-key → keyless URL, the cache guard drops/hides watermark entries and delegates the rest, both screens draw through the shared layer and **no file under `lib/` builds its own `TileLayer` or names `cartocdn`** |
| `test/infra/release_build_test.dart` | reads `CARTO_BASEMAPS_KEY` from Secret Manager · refuses an empty value · passes the define as a variable · **the define's name is the one `AppConfig` reads** · runs the probe with the flavour's app id · no `echo` line references the key |
| `web/tests/basemap.test.ts` | style URL with/without key · transform: none without key, keys every CARTO host, keeps an existing query, never duplicates, never touches other hosts or a look-alike · `MAP_STYLE` follows the env var · every `<Map mapStyle={MAP_STYLE}>` also passes `transformRequest` |
| `web/tests/csp.test.ts` | the measured style hosts (§3.1) are covered |

Every new guard was watched red; the mutations are listed in the commit and
the roadmap entry. **What no test here can see** (§10): whether CARTO accepts
the headers, the cert format, `@2x`, the web `Referer`. That is the probe's
job at release time and the lead's job once, by hand, when the keys exist.

## 9. Rollout

1. **Owner — create two keys** at <https://carto.com/basemaps/apikey/>
   (commercial use):
   - **app key** — mobile-app restrictions: iOS `com.myweli.app`,
     `com.myweli.pro`; Android `com.myweli.app` with SHA-1
     `B73647C6B06001AF04D38EE2D0A5AA4722CA156F`, `com.myweli.pro` with
     `94BE494A905B2C2ADC66AD5720EDDE124089C985` (enter them in this form —
     upper case, no colons — §3.3);
   - **web key** — website restrictions: `myweli.com`, `www.myweli.com`.
2. **Owner — store the app key** (nothing printed, nothing in history):
   `pbpaste | gcloud secrets create CARTO_BASEMAPS_KEY --project myweli --replication-policy=automatic --data-file=-`
3. **Owner — set the web key in Vercel**: `NEXT_PUBLIC_CARTO_BASEMAPS_KEY`,
   **Production environment only**. Preview hosts are not in the key's
   website list and a restricted key answers them 403 — leave previews
   keyless (vector still loads) or add `*.<project>.vercel.app` to the key.
   Redeploy production (a `NEXT_PUBLIC_*` is inlined at build time).
4. **Lead — run §10** with the real keys.
5. **Next release build** (`tool/release_build.sh`) bakes the key in and
   probes CARTO first. **Until step 2 is done, every release build is
   refused** — deliberately: the alternative is shipping the defect again.
6. Testers on build ≤ 555 keep seeing the watermark until they install a
   newer build.

## 10. Verification procedure — run once the keys exist

Every check has a control that must produce a *different* answer; a check
whose control passes too has measured nothing.

```sh
APP_KEY="$(gcloud secrets versions access latest --secret=CARTO_BASEMAPS_KEY --project=myweli)"
T=https://basemaps.cartocdn.com/rastertiles/light_all/11/1001/993
h() { curl -s -o /tmp/tile.png -D - "$@" | grep -iE '^HTTP|^etag|^content-(type|length)'; file /tmp/tile.png; }
```

**A. The app key, with exactly what the app sends** (the probe does the same
from the app's own code — `cd mobile && CARTO_BASEMAPS_KEY="$APP_KEY" dart run tool/carto_probe.dart --app-id com.myweli.app`, then `--app-id com.myweli.pro`):

```sh
for ID in com.myweli.app com.myweli.pro; do
  CERT=$([ $ID = com.myweli.app ] && echo B73647C6B06001AF04D38EE2D0A5AA4722CA156F || echo 94BE494A905B2C2ADC66AD5720EDDE124089C985)
  for R in "" "@2x"; do
    h -H "X-Ios-Bundle-Identifier: $ID" -H "X-Android-Package: $ID" -H "X-Android-Cert: $CERT" \
      -A "flutter_map ($ID)" "$T$R.png?key=$APP_KEY"
  done
done
```
Pass: `HTTP/2 200`, `content-type: image/png`, an etag **not** starting with
`"wm-`, a size other than 2 049 B; `file` says 256 × 256 for 1× and
**512 × 512 for `@2x`** (else CARTO ignores `@2x` on this path → set
`retinaMode: false` in `CartoBasemapLayer`).

**Controls** (each must FAIL, or the pass above proves nothing):
- no headers: `h "$T.png?key=$APP_KEY"` → **403**;
- keyless: `h "$T.png"` → 200 with the `wm-` etag;
- **learn the semantics** (informs §3.3, not required to ship):
  iOS header only → 200 means iOS alone satisfies the key, 403 means the
  restriction types are ANDed; Android pair only → same reading;
- **the cert format**: if the full set returns 403 while iOS-only returns
  200, the cert is the problem — retry with the colon form
  `B7:36:47:…` and the lower-case form; whichever passes goes into
  `cartoAndroidCertHeaderValue` (one line) and the dashboard entry.

**B. The web key**

```sh
WEB_KEY=…   # from the CARTO dashboard / Vercel
h -H 'Referer: https://myweli.com/' "$T.png?key=$WEB_KEY"          # → 200, not wm-
h -H 'Referer: https://www.myweli.com/' "$T.png?key=$WEB_KEY"      # → 200, not wm-
h -H 'Referer: https://example.org/' "$T.png?key=$WEB_KEY"         # control → 403
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' -H 'Referer: https://myweli.com/' \
  "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json?key=$WEB_KEY"   # → 200 106878-ish
```
The raster tile is the only way to prove a web key valid today: vector
ignores keys. Then load `https://myweli.com/recherche`, open DevTools →
Network, filter `cartocdn`: every request carries `key=`, none is 403.

**C. On a device**, after the next release build: the consumer « Carte » and
the pro « Profil du salon » map show streets and labels, on an iPhone and on
an Android phone. Clearing the app's cache is not needed (the URL changed).

## 11. Open questions

1. **`X-Android-Cert` format** — upper-case hex without colons is a guess
   (§3.3). The probe answers it at the first release build; §10 A says how to
   adjust.
2. **iOS and Android: one restriction type or two?** Irrelevant to shipping
   (every request carries both), but worth recording once measured (§10 A).
3. **`@2x` on `rastertiles/`** — undocumented; the probe checks the width.
4. **Quota exhaustion** — refusal, watermark, or throttling? Undocumented.
   If it is the watermark, §5.3 already keeps it off the devices.
5. **Vector key requirement** — when CARTO extends it, the web already sends
   the key everywhere (§5.5); nothing to do but verify.
6. **Does CARTO count `style.json`, sprites and glyphs as "tile requests"?**
   Read the dashboard after launch.

## 12. Definition of done

- [x] `flutter analyze` 0 · format clean · touched suites + full suite green.
- [x] web typecheck · lint · unit tests green.
- [x] Every new guard watched red (mutations in the commit body).
- [x] Spec indexed in [README.md](README.md); cross-linked from the code.
- [x] Roadmap entry.
- [ ] Owner: keys created and stored (§9) — **not done by this change**.
- [ ] Lead: §10 run with the real keys.
