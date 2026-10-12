# The CARTO basemap needs a key — every map, app and web

| | |
|---|---|
| **Status** | **Built 2026-10-11** (`fix/carto-basemaps-key`) — **both keys created and verified** with the real values (§10 A, B): the app key is in Secret Manager (`CARTO_BASEMAPS_KEY`), so the next store build carries it; the web key is recorded (`CARTO_BASEMAPS_WEB_KEY`) and **deliberately not in Vercel yet** — the web stays keyless until CARTO requires keys on vector (§7), a day `production-checks.yml` (`basemap`) detects (§9 step 3). Left: §10 C on devices. |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-12 |
| **PRD ref / phase** | Consumer « Carte » · pro salon pin map · web discovery maps · V1 |
| **Module** | `online-booking` (discovery · map) — [MODULES.md](../MODULES.md) §2 |
| **ROADMAP entry** | [2026-10-11-carto-basemaps-key](../roadmap/entries/2026-10-11-carto-basemaps-key.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-web-guardrails · myweli-verification-guardrails |

## 1. Goal & scope

**The defect.** Both app maps — the consumer « Carte » (`MapScreen`) and the
pro « Profil du salon » pin map — drew `https://{s}.basemaps.cartocdn.com/light_all/…`
with no key. **Since 2026-09-25 CARTO answers every keyless or bad-key raster
request with one watermark tile**, « API KEY REQUIRED » (§3.1). Every build up
to TestFlight 555 shows it instead of streets. No keyless oracle exists.

**In scope:** one shared keyed layer for both app maps (`light_all`, retina)
built by a **pure** function, the key from the `CARTO_BASEMAPS_KEY` define via
`AppConfig`; restriction headers per platform and flavour (§3.4); the stale
User-Agent package `com.sadreddine.myweli` replaced; `tool/release_build.sh`
reads the key from Secret Manager and refuses to build without a key-shaped
one; the web style **and every CARTO request** keyed when
`NEXT_PUBLIC_CARTO_BASEMAPS_KEY` is set — left unset by decision (§7), with a
daily probe for the day it must be (§9 step 3); §10.

**Out of scope:** vector tiles in the app (a renderer change); replacing CARTO
([web-discovery-map.md](web-discovery-map.md) §3); installed builds (≤ 555
keep the watermark until updated); a release-time live probe — the first pass
had `mobile/tool/carto_probe.dart`, **dropped**: a third-party network call
inside every store build, guessing at `@2x` widths. §10, run once by hand,
answers the same questions.

## 2. UX & states

No new screen or copy; the basemap is the change. Markers, the user dot,
« Utiliser ma position », tap-to-place and the attribution (« © OpenStreetMap
contributors », « © CARTO ») work in every state.

| State | Cause | What renders |
|---|---|---|
| **Basemap** | key compiled in, headers accepted | `light_all` tiles, `@2x` (512 × 512) **always** — `retinaMode: true` with `{r}` in the template is flutter_map's `RetinaMode.server`, whatever the screen density |
| **Watermark** | no key (`flutter run`, tests, CI builds) | « API KEY REQUIRED » — **deliberately**: the failure names its cause, where a plausible fallback would hide it |
| **Refused** | headers rejected → `403` | no tiles, or CARTO's error body if it decodes as an image (flutter_map 8.3.1 shows it, stores only `200`s) |
| **Unusable key** | revoked, mistyped, not yet active | the watermark (`200`, 30-day `immutable`), **never stored** (§5.3) — stored, it would outlive the fix by 30 days under the very URL the fix makes good |
| **Resolving** | first frame, app id being read | no tile layer for one frame |
| **Offline** | no network | cached tiles, else the background — unchanged |
| **Quota exhausted** | > 1 M requests / month | undocumented (§11) |

## 3. Contract — what CARTO serves

### 3.1 Measured 2026-10-11 (read-only public probes)

| Request | Result |
|---|---|
| `https://a.basemaps.cartocdn.com/light_all/11/1001/993@2x.png` (shipped builds) | `200` · `image/png` · **2 049 B** · `etag "wm-da89c20e77c1-light"` · `max-age=2592000, immutable` |
| `…/rastertiles/light_all/11/1001/993.png`, and its `@2x` with `?key=bogus` | identical: 256 × 256, one SHA-1 |
| `https://basemaps.cartocdn.com/gl/positron-gl-style/style.json` | `200`, 106 878 B — **vector still keyless** |
| the same with `?key=bogus123` | **byte-identical**: the style's own URLs carry no key |
| style → sprite · glyphs · `tiles.json` | all on `tiles.basemaps.cartocdn.com` |
| `tiles.json` → vector tiles | `tiles-{a,b,c,d}.basemaps.cartocdn.com/vectortiles/…/{z}/{x}/{y}.mvt`; one fetched keyless → `200` protobuf |
| that vector tile, `…/carto.streets/v1/12/2002/1987.mvt`, keyless (2026-10-12) | `200` · `application/x-protobuf` · 72 388 B · weak etag, not `wm-` — the answer `production-checks.yml` (`basemap`) expects daily |
| the same with `?key=bogus123`, no `Referer` (2026-10-12) | `200`, same bytes — an **unknown** key is ignored on vector; a real restricted key is enforced (§10 B: no `Referer` → `403`) |

### 3.2 Documented ([FAQ](https://docs.carto.com/faqs/carto-basemaps), read 2026-10-11)

- Raster `https://basemaps.cartocdn.com/rastertiles/<style>/{z}/{x}/{y}.png?key=KEY`;
  GL `https://basemaps.cartocdn.com/gl/<style>-gl-style/style.json?key=KEY`.
- Restrictions: website (`Referer` host; `www.` ≠ apex; `no-referrer` breaks
  every map), iOS (`X-Ios-Bundle-Identifier`), Android (`X-Android-Package` +
  `X-Android-Cert`). **Several types on one key are ANDed**; a restricted key
  without the right header → `403`. A partial or re-cased key counts as none.
- Free commercial tier: 1 M tile requests per calendar month, all keys summed.
- **Undocumented, then measured with the real keys (§10, 2026-10-11):** the
  cert format (any — upper or lower case, with or without colons); iOS and
  Android are ONE restriction type (each passes alone); `@2x` on `rastertiles/`
  works (512 × 512). Still unknown: quota exhaustion.

### 3.3 Two keys, because restrictions are ANDed

| Key | CARTO restrictions | Stored as | Read by |
|---|---|---|---|
| **app** | iOS `com.myweli.app`, `com.myweli.pro` · Android the same two + their certs | Secret Manager `CARTO_BASEMAPS_KEY` (project `myweli`) | `release_build.sh` → define → `AppConfig.cartoBasemapsKey` |
| **web** | websites `myweli.com`, `www.myweli.com` | Secret Manager `CARTO_BASEMAPS_WEB_KEY` (the record) → Vercel `NEXT_PUBLIC_CARTO_BASEMAPS_KEY` (Production only) — **not set until CARTO requires keys on vector** (§7, §9 step 3) | `salon-pin.tsx` → `cartoStyleUrl` + `cartoTransformRequest` |

The first key the owner made carried BOTH restriction types and refused every
request that did not carry a myweli.com `Referer` AND an app header — measured
before splitting it (§10).

### 3.4 The headers each build sends

| Platform | Headers (`cartoRestrictionHeaders`) |
|---|---|
| iOS | `X-Ios-Bundle-Identifier: <app id>` |
| Android | `X-Android-Package: <app id>` · `X-Android-Cert: <its release SHA-1>` |
| other, or no app id | none — a restricted key refuses, visibly |

The app id is what the OS installed (`PackageInfo.packageName`; bundle ids
equal packages here). The certs are the Play App Signing SHA-1s
(`b73647c6…156f`, `94be494a…c985`), pinned to
`infra/mobile/signing-manifest.json` and each flavour's `google-services.json`;
constants, so debug builds send them too, as **upper-case hex without colons**
(Google's convention for its own header of that name) — **verified 2026-10-11**:
CARTO accepts it (and colon-separated, and lower case); a wrong cert or a
missing one → `403`. Per platform is right: iOS and Android each pass alone.

## 4. Data model — none (no backend, API, migration or stored state)

## 5. Architecture

### 5.1 Files

| File | Role |
|---|---|
| `mobile/lib/core/map/carto_basemap.dart` | **Pure Dart** — no Flutter import, no define read (a `flutter test` can vary neither): URL, headers, cert table and wire format, `cartoBasemapRequest` → `{urlTemplate, headers, userAgentPackageName}`, `isCartoWatermarkEtag` |
| `mobile/lib/core/config/app_config.dart` | `cartoBasemapsKey = String.fromEnvironment('CARTO_BASEMAPS_KEY')`, empty by default |
| `mobile/lib/widgets/common/carto_basemap_layer.dart` | `CartoBasemapLayer` (the only `TileLayer` in `lib/`), `cartoPlatformOf`, `CartoAttribution`, `CartoWatermarkRefusingCache` |
| `map_screen.dart` · `pro_salon_profile_screen.dart` (`_LocationField`) · `widgets/providers/salon_location_preview.dart` (the salon page's map, [salon-location-map.md](salon-location-map.md) — `panBuffer: 0`, it never moves) | `CartoBasemapLayer(…)` first, `const CartoAttribution()` last |
| `tool/release_build.sh` | reads the secret, refuses empty / whitespace / not key-shaped (`^[A-Za-z0-9_-]{20,}$`) before compiling, never prints it, passes the define |
| `web/lib/basemap.ts` · `web/components/map/salon-pin.tsx` | pure `cartoStyleUrl(key)` and `cartoTransformRequest(key)`; `MAP_STYLE` and `MAP_TRANSFORM_REQUEST` from the env var, handed to every `<Map>` (`ResultsMap`, `LocationPicker`, `SalonLocationMap`) as `mapStyle` and `transformRequest` |
| `web/.env.example` | every variable an operator sets, this one included (with §7's reason it stays empty); the platform- and build-set ones (`VERCEL_ENV`, `VERCEL_GIT_COMMIT_SHA`, `SENTRY_AUTH_TOKEN`) listed commented |
| `.github/workflows/production-checks.yml` (`basemap`) | daily: one keyless vector tile (§3.1); not a `200` protobuf, or a `wm-` etag → red, naming `NEXT_PUBLIC_CARTO_BASEMAPS_KEY` and §9 step 3, through the tracking issue |

### 5.2 The app layer

URL `https://basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}{r}.png?key=<key>`,
`retinaMode: true`, no `{s}` subdomains (CARTO's documented form has none).
The key is trimmed and query-encoded, never re-cased; **no key → the same URL
without `?key=`**. Platform = `defaultTargetPlatform`; app id = `PackageInfo`
(as in `client_version_gate.dart`) — no tiles for the frame that takes; if it
throws (no platform: widget tests) the layer draws without headers. **One
`NetworkTileProvider` per layer** — a bare `TileLayer` builds a provider and
HTTP client on every rebuild and disposes only the last, as both screens did.

### 5.3 The watermark-refusing cache

`CartoWatermarkRefusingCache` wraps flutter_map's built-in cache: `putTile`
drops a `wm-…` etag (strong or weak), `getTile` treats one as absent, the rest
is delegated. **It never hides the notice** — every watermark served is drawn
(CARTO terms §3.d); it is only not kept.

### 5.4 The release build

Same rule as the Sentry DSN. A build without the define would not fail, warn
or crash — it would ship, every map a watermark — so the script refuses, before
either `flutter build`. And, as for the DSN, it checks the **shape**, not just
presence: letters, digits, `_`, `-`, at least 20 — a placeholder (`TODO`) or a
truncated paste is non-empty and blank-free, and CARTO answers a key it does
not know with the same watermark (§3.1). The refusal never echoes the value.

### 5.5 The web

Two exports, one variable, and together they key **every** request the web
makes to `*.cartocdn.com`:

- `MAP_STYLE` = the style URL with `?key=` when the variable is set, else the
  URL the web always used.
- `MAP_TRANSFORM_REQUEST` = `cartoTransformRequest(key)`, handed to each
  `<Map>` as `transformRequest`: it adds the key to every other CARTO request
  maplibre makes — `tiles.json`, the vector tiles, sprite, glyphs — because the
  style does not key its own URLs (§3.1, §10 B). CARTO hosts only, an existing
  `key` never overwritten.

Without the variable both pass through: keyless, exactly as before. Both reads
stay a literal `process.env.NEXT_PUBLIC_…` (what Next inlines), and
`tests/basemap.test.ts` holds each export to the variable. **In production the
variable is unset by decision** until CARTO requires keys on vector (§7, §9
step 3). CSP unchanged: every §3.1 host is under `https://*.cartocdn.com`
(`connect-src`), and CSP ignores query strings. `Referrer-Policy:
strict-origin-when-cross-origin` (pinned in `tests/e2e/served-html.spec.ts`)
lets a website key see the host.

## 6. Security

- **A basemap key is public by construction** (every binary, every bundle).
  Secret Manager keeps it out of git and shell history; it does not make it
  secret. Restrictions bound casual reuse, not abuse — ids, packages and cert
  SHA-1s are readable from any published app; the shared free quota means
  abuse costs maps, not money.
- Never printed: no `echo` line references `$CARTO_KEY`, and the shape
  refusal is run with a stubbed `gcloud` to prove its output never contains
  the value (both pinned); `--dart-define` shows in `ps` on the build machine,
  as the DSN already does.

## 7. Performance

One `PackageInfo` call and one provider per layer.

**Quota — 1 M requests a month, all keys summed (§3.2).** Phones, for planning
only: ≈ 15–30 tiles per settled view → ≈ 30 000 map opens a month inside 1 M —
**unmeasured**; read the CARTO dashboard after launch.

**The web counts as zero, and is kept there on purpose.** Every salon page
renders a map, and with the variable set every vector tile, glyph, sprite and
`tiles.json` request the web makes is keyed (§5.5) — so it would draw on the
same 1 M as the phones, for tiles CARTO serves free keyless today (a keyless
request belongs to no key, so to no quota of ours). Hence the decision, taken
in review: the web key stays **out of Vercel** until CARTO requires keys on
vector. The code is ready, and the moment is detected by a mechanism, not a
memory: `production-checks.yml` (`basemap`) fetches one keyless vector tile
every morning and goes red — naming `NEXT_PUBLIC_CARTO_BASEMAPS_KEY` and §9
step 3, through the tracking issue — the day the answer is not a `200`
protobuf. From that day the web's share belongs in this budget: read the
dashboard before setting the variable, and the day after (§11.6).

## 8. Testing

| Test | Holds |
|---|---|
| `mobile/test/unit/carto_basemap_test.dart` | URL keyed / keyless / trimmed / encoded · headers per platform and flavour, unknown package, no id · cert format · **cert table = `signing-manifest.json` and ∈ each `google-services.json`** · the request + User-Agent · watermark etag |
| `mobile/test/widget/carto_basemap_layer_test.dart` | the real layer in a real `FlutterMap`: the fetched URL (`@2x`, `?key=`), the provider's headers on Android **and** iOS, no key, no platform, the cache guard, the attribution, `panBuffer` handed through, `MapScreen` through it · **no other `lib/` file builds a `TileLayer` or names `cartocdn`** (comments stripped, positive control) · **every code file with a `FlutterMap(` has as many `CartoBasemapLayer(` and `CartoAttribution()`**, the files found by scan with an exact list (3 since 2026-10-12) — it was a fixed list of two screens, which a third map would have walked past |
| `mobile/test/infra/release_build_test.dart` | secret read · empty → `exit 1` · whitespace → `exit 1` · **not key-shaped → `exit 1`, run for real** (stubbed `gcloud` / `node`: `TODO`, `changeme`, 19 chars, `.`, `==`, `/`, `+` refused before the next step, value never in the output; a well-shaped key goes on) · define passed · **its name = the one `AppConfig` reads** · refusal before both builds · no `echo` leaks the key |
| `web/tests/basemap.test.ts` · `web/tests/csp.test.ts` | `cartoStyleUrl` · `cartoTransformRequest` (keys tiles.json, vector, sprite, glyphs; no other host; never overwrites; pass-through without a key) · **`MAP_STYLE` and `MAP_TRANSFORM_REQUEST` both follow the env var** · no other source names `cartocdn.com` · the three `<Map>`s get both · **the `production-checks` `basemap` job**: present, the keyless URL, no `continue-on-error`, in `report.needs`, and its own script run against a local server (`200` protobuf passes; `wm-` etag strong or weak, PNG, empty, `403`, unreachable fail, naming the variable and §9) · `*.cartocdn.com` stays in `connect-src` |

Every new guard was watched red (commit body, roadmap entry). No golden
renders a map. **No test can see** whether CARTO accepts our headers, the cert
format, `@2x`, or the web `Referer` — that is §10.

## 9. Rollout

*Steps 1–2 done 2026-10-11 (app key `CARTO_BASEMAPS_KEY`, web key recorded
as `CARTO_BASEMAPS_WEB_KEY`); §10 A and B passed. Step 3 waits, by decision
(§7), for CARTO to require keys on vector — `production-checks.yml` says when.*

1. **Owner — two keys** at <https://carto.com/basemaps/apikey/> (commercial):
   **app** with §3.3's mobile restrictions (certs as the dashboard asks —
   `B73647C6B06001AF04D38EE2D0A5AA4722CA156F`, `94BE494A905B2C2ADC66AD5720EDDE124089C985`);
   **web** restricted to `myweli.com`, `www.myweli.com`.
2. **Owner — store the app key** from the clipboard (no shell history; the
   script refuses a key containing whitespace, or not key-shaped, §5.4): `pbpaste | gcloud secrets create CARTO_BASEMAPS_KEY --project=myweli --replication-policy=automatic --data-file=-`
3. **Owner — Vercel, only when CARTO requires keys on vector** — the day the
   `basemap` job of `production-checks.yml` goes red (the tracking issue names
   this step). `NEXT_PUBLIC_CARTO_BASEMAPS_KEY` = the value of Secret Manager
   `CARTO_BASEMAPS_WEB_KEY`, **Production only** (a preview host is not on the
   key → `403`; previews stay keyless and show what CARTO shows a keyless
   map), then **redeploy** — Next inlines the variable at build time, so
   nothing changes until a new build. Then §10 B's last line, on myweli.com.
4. **Lead — §10** (A and B done). Then the next `tool/release_build.sh` and
   §10 C. Before step 2 every store build was refused — deliberately.

## 10. Verification — the lead, once the keys exist

**Pass** = `200`, `image/png`, etag **not** `"wm-…`, size **≠ 2 049 B**,
and 512 × 512 for `@2x`. Each pass has a control that must answer otherwise.

```sh
APP_KEY="$(gcloud secrets versions access latest --secret=CARTO_BASEMAPS_KEY --project=myweli)"
T=https://basemaps.cartocdn.com/rastertiles/light_all/11/1001/993
probe() {  # status, size, etag, pixels — never the URL
  curl -s -o /tmp/c.png -D /tmp/c.h -w '%{http_code} %{size_download} ' "$@"
  grep -i '^etag' /tmp/c.h | tr -d '\r'; file -b /tmp/c.png; }
ios() { probe -A "flutter_map ($1)" -H "X-Ios-Bundle-Identifier: $1" "$T@2x.png?key=$APP_KEY"; }
android() { probe -A "flutter_map ($1)" -H "X-Android-Package: $1" \
  -H "X-Android-Cert: $2" "$T@2x.png?key=$APP_KEY"; }
```

**A. The app key, exactly as each build sends it (§3.4):**
`ios com.myweli.app` · `ios com.myweli.pro` ·
`android com.myweli.app B73647C6B06001AF04D38EE2D0A5AA4722CA156F` ·
`android com.myweli.pro 94BE494A905B2C2ADC66AD5720EDDE124089C985` — all pass.
Controls: `probe "$T.png?key=$APP_KEY"` (no headers) → `403`;
`probe "$T.png"` (keyless) → `200`, `wm-` etag, 2 049 B.
- Android `403`, iOS pass → the cert format: retry colon-separated, then
  lower case; the winner goes into `cartoAndroidCertHeaderValue` + its test.
- Both `403`, but all three headers together pass → CARTO ANDs the platforms:
  send both sets in `cartoRestrictionHeaders`, or one key per platform.
- `@2x` not 512 × 512, or `404` → `retinaMode: false` in `CartoBasemapLayer`.

**B. The web key** (`WEB_KEY` from the dashboard):
`probe -H 'Referer: https://myweli.com/' "$T.png?key=$WEB_KEY"`, same with
`https://www.myweli.com/` → pass; with `https://example.org/` → `403`. Then
`curl -s -H 'Referer: https://myweli.com/' "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json?key=$WEB_KEY" | grep -c 'key='`
— record the count in §11.5 (`0` = the style does not key its own URLs).
~~A raster tile is today's only proof a web key works (vector ignores keys).~~
*Wrong, struck 2026-10-12: the run below got `403` for a keyed vector tile
without `Referer` — CARTO enforces a real key on vector too.*
Last, **after §9 step 3**, `https://myweli.com/recherche`, DevTools → Network →
`cartocdn`: the style and the tiles carry `key=`, nothing is `403`.

**Run 2026-10-11 with the real keys — all pass.** A: iOS `com.myweli.app` /
`com.myweli.pro` and Android both packages with their certs (upper case, lower
case, colons) → `200`, 72 813 B, 512 × 512, etag not `wm-`; controls — no
headers `403`, myweli.com `Referer` only `403`, package without cert `403`,
wrong bundle or cert `403`, keyless `200` watermark. B: web key + myweli.com /
www `Referer` → `200`; no referer, iOS header only, a foreign site → `403`;
the keyed style answers `200` and its sources carry **no** key (count `0`);
keyed `tiles.json`, vector tile and glyphs + `Referer` → `200`, keyed vector
tile without `Referer` → `403` — CARTO enforces a real key's restrictions on
vector requests (an unknown key is ignored, §3.1), so once the web sends its
key it sends it on every request (`cartoTransformRequest`).

**C. On devices**, after the next release build: both apps' maps show
streets and labels, on an iPhone and an Android phone.

## 11. Open questions

1. ~~The `X-Android-Cert` format~~ — any (§10).
2. ~~iOS and Android: one restriction type or two~~ — one (§10).
3. ~~`@2x` on `rastertiles/`~~ — works (§10).
4. Quota exhaustion: refusal, watermark or throttling? If the watermark, §5.3
   already keeps it off devices.
5. ~~**Vector key requirement.**~~ Built: the style does not key its own URLs
   (§10 B), so `cartoTransformRequest` keys every CARTO request each `<Map>`
   makes; CARTO enforces a real key on them today (keyed without `Referer` →
   `403`). The day it requires one, setting the variable (§9 step 3) is the
   whole change — and `production-checks.yml` (`basemap`) is what says so.
6. Do keyed vector requests count against the 1 M? Undocumented; assumed yes,
   which is §7's reason to keep the web keyless. Read the dashboard the day
   after §9 step 3.

## 12. Definition of done

- [x] `flutter analyze` 0 · format clean · full suite green · web typecheck, lint, unit green.
- [x] Every new guard watched red · indexed in [README.md](README.md) · cross-linked from the code · [DEPLOYMENT.md](../DEPLOYMENT.md) lists the secret · roadmap entry.
- [x] Owner: keys created and stored (§9). · [x] Lead: §10 with the real keys (2026-10-11).
- [x] The moment the web key is needed is detected, not remembered: `production-checks.yml` (`basemap`), pinned and run both ways by `web/tests/basemap.test.ts`.
- [ ] Owner: Vercel `NEXT_PUBLIC_CARTO_BASEMAPS_KEY` (§9 step 3) — **deferred by decision** until that job goes red (§7) · [ ] §10 C on devices.
