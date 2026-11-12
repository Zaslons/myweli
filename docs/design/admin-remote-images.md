# Admin console: images from R2 are drawn by the browser

| | |
|---|---|
| **Module** | admin (console) — [MODULES.md](../MODULES.md) |
| **BACKLOG** | B0.21 |
| **Status** | **Proposed 2026-11-12, built the same day** on `fix/admin-remote-images` (#777), stacked on #775 (`fix/admin-kyc-queue`), then **rebased onto `main` after #775 (`<S775>`)**, where #779 had landed: B0.18's salon photos became the widget's third user (§3, §4.1). « Actualiser » on a failed image added the same day on the owner's yes (§4). Not merged, not deployed. The merge is the owner's yes. |
| **Last updated** | 2026-11-12 |
| **Found** | 2026-11-12: a CORS probe found `cdn.myweli.com` refusing `https://admin.myweli.com`; this spec follows it to the KYC and deposit documents |
| **PRD ref / phase** | FR-WEB-AD-001 (KYC approval queue), the dispute view · V1 |
| **ROADMAP entry** | [2026-11-12-admin-remote-images.md](../roadmap/entries/2026-11-12-admin-remote-images.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Related** | [admin-kyc-queue-submitted.md](admin-kyc-queue-submitted.md) (#775, the PDF tile) · [salon-go-live-approval.md](salon-go-live-approval.md) §4.4 (B0.18's salon photos, #779, drawn through this widget since the rebase) · [web-pro-kyc.md](web-pro-kyc.md) · `infra/cloudflare/r2-manifest.json` |

How to read it: **observed** means probed or run here on 2026-11-12;
**UNVERIFIED** means not.

## 1. What is wrong

### 1.1 R2 sends the console no CORS header (observed)

A signed link points at R2's S3 endpoint, path-style:
`https://<account>.r2.cloudflarestorage.com/<bucket>/<key>?X-Amz-…`
(`backend/lib/src/storage/storage_service.dart`, `_presignUrl`). A preflight
there, `OPTIONS` with `Access-Control-Request-Method`, on 2026-11-12 (no cloud
setting read or changed; the account id read from Secret Manager):

| Bucket | Origin | GET preflight | PUT preflight (`content-type`) |
|---|---|---|---|
| `myweli-uploads` (public) | `https://myweli.com` | **204**, ACAO `https://myweli.com` | 204 |
| `myweli-uploads` | `https://admin.myweli.com` | 403, no ACAO | — |
| `myweli-kyc-private` | `https://myweli.com` | 403, no ACAO | **204**, methods `PUT` |
| `myweli-kyc-private` | `https://admin.myweli.com` | 403, no ACAO | 403 |
| `myweli-deposits-private` | `https://myweli.com` | 403, no ACAO | **204**, methods `PUT` |
| `myweli-deposits-private` | `https://admin.myweli.com` | 403, no ACAO | 403 |

The first row is the control: the same host and the same probe answer 204
when a rule matches, so the 403s are the rules, not the probe. The private
buckets do carry a rule, **PUT only**, for `myweli.com` and `www.myweli.com`:
the web app uploads KYC and deposit files straight into them
(`web/lib/pro/upload.ts`). No rule allows a GET from any origin, and
`admin.myweli.com` is on no list.

A GET with an `Origin` header proved nothing: R2 adds no ACAO to an error
response, even for the allowed origin on the public bucket. A 200 could not be
fetched as a second control: production lists no public salon, and signing a
private GET would mean reading the R2 secret key, which this did not do.

### 1.2 Why the console needs it (observed in the SDK and the engine)

The console (`lib/main_admin.dart`) is Flutter Web, built by
`deploy-admin.yml` without `--wasm`, so CanvasKit. The KYC tile
(`admin_kyc_detail_screen.dart`) and the dispute's deposit proof
(`AdminEvidenceImage`, `admin_detail_widgets.dart`) drew the signed link with
`TimedCachedImage`, which is cached_network_image 3.4.1. On the web its
default (`ImageRenderMethodForWeb.HtmlImage`) calls `createImageCodecFromUrl`;
CanvasKit loads that through `<img crossorigin="anonymous">`
(`html_image_element_codec.dart:39`) and, when that fails, `fetch`. Both need
ACAO for the page's origin. `TimedCachedImage` also sends a `User-Agent`
header.

### 1.3 What an admin sees (reproduced, §8.2)

The « image not available » icon in place of every KYC photo and every deposit
proof, on the console only. The phone apps fetch without CORS and are not
affected. Production held 0 KYC documents on 2026-11-12 (#775's read-only
count), so nobody has seen it there. How many disputes carry a proof is
UNVERIFIED.

## 2. Options

| | What | Verdict |
|---|---|---|
| **A** | Code only: draw the image as a plain `<img>` (`Image.network(…, webHtmlElementStrategy: WebHtmlElementStrategy.prefer)`). A plain `<img>` loads cross-origin without CORS | **Chosen.** No cloud change. The page cannot read the pixels (an opaque image), and it never needs to |
| B | Add a GET rule for `admin.myweli.com` to three buckets | A cloud change: the owner's yes. It would make the bytes readable by the console's script, which nothing needs, and the manifest and its checker would have to learn about private-bucket rules |
| C | Proxy the bytes through the API | Every document through Cloud Run; the storage design keeps bytes off our server on purpose |
| D | `WebHtmlElementStrategy.fallback` | Tries `fetch` first: every image fails once, logs a CORS error, then loads as A |

## 3. The fix

- **`AdminRemoteImage`** (`lib/screens/admin/widgets/admin_remote_image.dart`):
  `Image.network(url, fit, webHtmlElementStrategy: prefer)`, **no headers**
  (with any header the framework fetches the bytes, §1.2). Off the web the
  strategy is ignored: an ordinary network image.
- The KYC tile's thumbnail and zoom, and `AdminEvidenceImage`'s thumbnail and
  zoom, use it. #775's PDF tile is untouched.
- **B0.18's salon photos** (« Salons à valider »,
  `admin_salon_validation_detail_screen.dart`, #779) use it too since the
  rebase onto `main`. #779 had drawn them with its own
  `Image.network(prefer)`, for the same reason (the public bucket refuses
  `admin.myweli.com`, §1.1). Replayed onto it, the guard found that screen,
  the one offender (observed red); the photos moved to the widget, and the
  guard kept no exception for them: one way to draw a remote image in the
  console. Their tile keeps its own looks through two optional parameters,
  `placeholder` and `errorPlaceholder` (§4.1).
- **Why it works with the tap and the zoom** (SDK, `_web_image_web.dart`): the
  framework gives its `<img>` `pointer-events: none`, so the
  `GestureDetector` around it still gets the tap; `RenderWebImage` applies
  `BoxFit`; a platform view takes the clip and the transform, so the rounded
  tile and `InteractiveViewer` behave as before (§8.2).
- `TimedCachedImage` stays everywhere else (SYSTEM.md §11.1); the console is
  the one exception (§11.2, §19).

## 4. States and copy

| State | What shows |
|---|---|
| Loading | `surface` box, `BrandLoader` (`iconS`, fast), as `TimedCachedImage` did. `frameBuilder` holds it until the first frame, which the framework counts for an `<img>` too |
| Success | The image, `cover` in the tile, `contain` in the zoom |
| Error | `surface` box, `broken_image_outlined` (decorative), **« Image indisponible »** (`bodySmall`, `textSecondary`) and, when the screen can sign new links, **« Actualiser »** (`TextButton`, `textPrimary`). It reloads the record the link came from: the KYC file (#775's `onRefresh`) or the dispute (`depositScreenshotUrl` is signed per read). Never a retry of the same link, which once refused stays refused (SYSTEM.md §12); the web's deposit proof « Réessayer » and #775's PDF tile « Actualiser » do the same. Owner's yes, 2026-11-12 |
| Error, in the zoom | The same; « Actualiser » **closes the zoom first**, then reloads, so the page under it does not keep the dead link |
| Error, at 200 % text | The message and the button outgrow a 220 × 160 tile: they scroll inside it, centred while they fit, so the button stays reachable |
| Error, the tap | The tile's centre is its « Actualiser »; the rest of the tile still opens the zoom, as before |
| No link | Unchanged: the tile's own placeholder |

### 4.1 The third user: B0.18's salon photos

Public objects on `cdn.myweli.com`, the logo first, then each photo, in a
144 dp square clipped at `radiusMedium` (#779's tile, unchanged).

| State | What shows |
|---|---|
| Loading | The tile's own, passed as `placeholder`: `surfaceVariant`, `image_outlined` (`iconL`, `textTertiary`). The same `frameBuilder` holds it, so the web's `<img>` path shows it from the first frame (#779's « a photo on its way » fix, which `loadingBuilder` could not give) |
| Success | The photo, `cover`, named « Photo N du salon » or « Logo du salon » |
| Error | The tile's own, passed as `errorPlaceholder`: `surfaceVariant`, `broken_image_outlined`, « Photo indisponible » to a screen reader. **No « Image indisponible » and no « Actualiser »** |
| The ways out | « Ouvrir « Photo N » dans un nouvel onglet » under each photo (`url_launcher`, a 48 dp target), where the browser loads the link itself and shows why it fails; the app bar's « Rafraîchir », which reads the request again and so brings a replaced photo under its new link, but does not ask for a failed one again (below); on the web, only a reload of the page does |

**« Actualiser » on a salon photo: no.** The button reloads the *source* of
the link, because for a KYC file or a dispute that signs a new one. The
salon photo's source is the request (`AdminSalonValidationDetailProvider.load`),
but its links are public and unsigned: a re-read returns the same URL, the
`NetworkImage` compares equal (url, scale, strategy, headers), and
`Image.didUpdateWidget` does not resolve it again. So the failed photo is not
asked for again: observed in a widget test that counts the requests across a
« Rafraîchir » (and red when the widget is made to re-request, §8.3 A12); the
SDK path read in `widgets/image.dart` and `painting/_network_image_web.dart`.
A button wired to that reload would do nothing visible, a way out that cannot
help (SYSTEM.md §12). What a re-read does fix, a photo the salon replaced,
comes back under a new URL that is asked for at once (same test): that is the
app bar's « Rafraîchir », already there. So `onReload` stays null, and the
widget asserts that an `errorPlaceholder` never comes with one.

**A retry of the same link: a scope choice, not a rule.** Unlike a signed
link, which once refused stays refused, a public link can load on a second
try (a passing CDN failure), so SYSTEM.md §12 would allow a retry here. It is
left out because the review needs only the tab button, which loads the photo
in the browser or shows why it fails. An in-console retry would be
`imageCache.evict(NetworkImage(url, webHtmlElementStrategy:
WebHtmlElementStrategy.prefer))` plus a new key on the tile: the owner's call
if ever wanted, not part of this change.

**On the web, a failed photo stays failed for the life of the page** (read in
the Flutter 3.47.9 SDK, not run in a browser). The web `NetworkImage` never
evicts a key that failed (`painting/_network_image_web.dart`, `_loadAsync`:
no `evict`), and the image cache only moves a pending image on when it
succeeds (`painting/image_cache.dart`, `putIfAbsent`: its listener has no
error callback), so the failed completer stays pending. A later resolve of
the same URL gets that completer back, which replays its stored error
(`painting/image_stream.dart`, `ImageStreamCompleter.addListener`). So
neither « Rafraîchir », nor leaving and reopening the request, nor another
request showing the same photo asks for it again: the tile stays in its
error state until the page is reloaded; the tab button still shows the
photo or why it fails. On the VM, where the widget tests run, a failed key is
evicted (`painting/_network_image_io.dart`), so reopening does ask again
there. Not a change from #779: its own `Image.network(prefer)` behaved the
same.

## 5. Security

- Nothing new is exposed: the same 5-minute signed links, to the same
  authenticated admin. B0.18's salon photos are public objects the console
  already showed (§4.1). The `<img>` request is `no-cors`, without an `Origin`
  header (observed, §8.2), and the page cannot read the bytes back.
- The request carries a `Referer` of the console's origin (the browser's
  default `strict-origin-when-cross-origin`). Nothing secret is in that origin.
- CSP: the console's bundle declares none (`mobile/web/index.html`, no
  `_headers` file), so `img-src` does not restrict R2. The live console sits
  behind Cloudflare Access and its own headers were not read: UNVERIFIED.

## 6. Performance

Each image becomes a platform view, which Flutter calls suboptimal. The
console shows at most four documents per KYC file and one proof per dispute.
A salon request shows its logo and its photos: the gallery is capped at 20
(`ProviderCatalogService._maxGalleryPhotos`), so 21 at most, as #779 already
drew them.
In the harness the request took 5 ms; the seconds before it went on the
app's start in a hidden pane, so no paint time is claimed.

## 7. Tests

- `test/widget/admin_remote_image_test.dart`: the strategy asked for, no
  header; the loader before the first frame; « Image indisponible » in a
  220 × 160 tile at 1× and 2×, no overflow; the deposit proof and its zoom go
  through it; no link, no image.
- `test/widget/admin_kyc_detail_pdf_test.dart` (#775's): the image tile and its
  zoom go through it, `prefer`, no header; a failed image's « Actualiser »
  reads the file again, from the tile and from the zoom, which closes first.
- `test/widget/admin_dispute_detail_evidence_test.dart`: the proof goes
  through it, and « Actualiser » reads the dispute again.
- In `admin_remote_image_test.dart` too: « Actualiser » only when there is a
  reload, reachable and tapped at 1× and 2× in the tile, the tap-target and
  label guidelines, the deposit proof's zoom closing before the reload.
- `test/widget/admin_salon_validation_detail_screen_test.dart` (#779's,
  adapted): the photos are `AdminRemoteImage` (the URLs in order, their names,
  no `onReload`, the rounded clip), each its `<img>` (`prefer`, no header),
  the only images on the page; failed, the tile's placeholder with « Photo
  indisponible », no « Image indisponible », no « Actualiser »; the logo
  first, « Logo du salon », with its tab button (pinned for the first time);
  on its way, the tile's placeholder inside the widget and no brand loader;
  across « Rafraîchir », no link asked for again, and a replaced photo's new
  link asked for once.
- In `admin_remote_image_test.dart` too: `placeholder` and `errorPlaceholder`
  shown, still `prefer` and no header; an `errorPlaceholder` with an
  `onReload` is an assertion error.
- `test/infra/admin_remote_images_guard_test.dart`: walks the import graph
  from `lib/main_admin.dart`, comments stripped, and fails if any reachable
  file other than `AdminRemoteImage` draws a network image
  (`TimedCachedImage`, cached_network_image, `Image.network`, `NetworkImage`,
  `SvgPicture.network`), or if the widget loses `prefer` or gains a header.
  A walk that reaches fewer than 50 files, or misses the KYC, dispute and
  salon request screens, fails. **Blind to:** an image a package draws from a URL we pass,
  and a provider built in a file the console does not import.
- Mutations watched red: §8.3.

## 8. Verified

### 8.1 The probes

§1.1, on 2026-11-12.

### 8.2 In a browser (observed, Chromium in the desktop app's pane)

A release build (`flutter build web --release`, as `deploy-admin.yml`, so
CanvasKit) of a throwaway entrypoint, never committed, served from
`http://localhost:8930`. The images came from `http://127.0.0.1:8931`, which
sends no CORS header, like R2, and from `:8932`, which sends `*`.

| Case | Result | Request log |
|---|---|---|
| A — `TimedCachedImage`, no CORS | « image not available » icon | `cors`/`image` blocked, then `cors`/`empty` (fetch) blocked |
| B — `TimedCachedImage`, CORS (control) | the image | `cors`/`image` |
| C — `AdminRemoteImage`, no CORS | the image | `no-cors`/`image`, no `Origin` |
| D — `AdminRemoteImage`, 403 (an expired link) | « Image indisponible » | `no-cors`/`image` |
| E — `AdminEvidenceImage`, no CORS | the image, rounded corners | `no-cors`/`image` |
| The real `AdminKycDetailScreen` (#775) | PDF tile, photo, « Image indisponible » for the 403 | as C and D |
| Tap a thumbnail | the zoom opens, image `contain` | |
| Mouse wheel in the zoom | zooms in, clipped to the dialog | |
| The thumbnail under the dialog | dimmed by the barrier, like the page | |

B is what makes A mean CORS: same widget, same bytes, only the header differs.

**Zoom after the link expires.** The zoom makes a new `<img>` with the same
URL. In one run the browser requested it again (my server sent no caching
header); in another, with the URL then answering 403, it drew the image from
its own cache with no request. Which one R2's headers give is UNVERIFIED; at
worst the zoom of a file left open more than 5 minutes shows no image, and
reloading the file fixes it.

### 8.3 Mutations

Each applied to committed code (`480efb21`), asserted to have changed the
file, run, and restored from git with a clean-tree check:

| Mutation | Expected | Went red |
|---|---|---|
| M1 `prefer` → `never` | red | the widget test, the deposit proof's, #775's image tile, the guard's widget check |
| M2 a `User-Agent` header added | red | the same four |
| M3 the deposit proof's thumbnail back to `TimedCachedImage` | red | the deposit-proof test, the import walk |
| M4 only the KYC zoom back to `TimedCachedImage` | red | #775's image tile (its zoom half), the import walk |
| M5 `errorBuilder` removed | red | all five widget tests (the 400 becomes an uncaught image error) |
| M6 the loader never shown | red | the loader test |
| M7 the walk skips relative imports | red | « the walk reaches the console »; the offenders check stays green on the empty walk, which is why the reach check exists |
| M8 a `NetworkImage` in `brand_loader.dart`, a shared widget outside `screens/admin/` | red | the import walk |
| M8c the same, in a comment only (control) | **green** | — |

And for « Actualiser », on `724d651d`:

| Mutation | Expected | Went red |
|---|---|---|
| R1 the button never shown | red | the first try did not compile (no result); **R1b** (`&& 1 < 0`): the reload tests in all three files |
| R2 a button even with nothing to call | red | the two « no reload, no button » tests |
| R3 the scroll removed | red | the 2× reload test only (1× still fits: the pair discriminates) |
| R4 the KYC zoom reloads without closing | red | the KYC reload test |
| R5 the deposit proof's zoom reloads without closing | red | the zoom test |
| R6 the KYC thumbnail without its reload | red | the KYC reload test |
| R7 the dispute view without its reload | red | the dispute test |

And for the salon photos, on the committed adaptation after the rebase (the
salon request's test, the widget test and the guard run each time; the tree
checked clean after each restore):

| Mutation | Expected | Went red |
|---|---|---|
| A1 the photos back to #779's own `Image.network(prefer)` | red | the guard's offenders check, the photos test, the logo test, the on-its-way test |
| A2 no `placeholder` (the brand loader instead) | red | the on-its-way test |
| A3 no `errorPlaceholder` (« Image indisponible » instead) | red | the photos test; the golden's scene renders differently on the Mac (§8.4) |
| A4 the widget ignores `placeholder` | red | the widget's placeholder test, the on-its-way test |
| A5 the widget ignores `errorPlaceholder` | red | the widget's placeholder test, the photos test |
| A6 square corners | red | the photos test |
| A7 no name passed | red | the photos test, the logo test |
| A8 the logo last | red | the logo test |
| A9 the assertion removed | red | the assertion test |
| A10 the salon photos given « Actualiser » (the request's reload) | red | the photos test |
| A11 a `User-Agent` header on the widget | red | the guard's widget check, both widget tests that read the provider, the photos test |
| A12 a new `Image` on every build (a failed link asked for again on each re-read) | red | the « Rafraîchir » count test: the premise of §4.1 is held. Its red relies on the VM evicting a failed key; on the web the same mutation would ask for nothing again (§4.1, read in the SDK) |

### 8.4 The golden's scene (observed on the Mac, not the baseline)

`admin_validation_detail.png` draws a request whose three photos fail
(`flutter test` answers 400). Its scene, and the same with the photos on
their way and a logo, were rendered by an uncommitted probe before and after
the adaptation, on the Mac: **byte-identical** both times. Control: A3
changes the render. The committed baseline is Linux's and was not run here:
expected unchanged, UNVERIFIED until CI.

## 9. Rollout

Rebased onto `main` after #775 (`<S775>`); the merge is the owner's yes.
Then `deploy-admin.yml` (manual, the owner's go): with #779 and #775 on
`main`, that is B0.18's step 2, one console deploy for the three. No backend
change, no cloud change.

## 10. Not verified, and seen but left out

- **A real signed link on admin.myweli.com.** Production holds no KYC
  document; the mechanism is proven against a server that refuses CORS the
  same way (§8.2), not against R2 itself.
- **WebKit and Gecko**: not run.
- **B0.18's salon photos** come from `cdn.myweli.com`, which refuses the
  console's origin too (the 2026-11-12 finding). The guard said so once
  #779's screen was imported (the rebase), and they now use
  `AdminRemoteImage` (§4.1); `salon-go-live-approval.md` §4.4 says so. **Not
  run in a browser**, through the widget or before it (#779's own roadmap
  entry lists its `<img>` photos as unverified there); the mechanism is the
  one §8.2 observed. The web's path for « Rafraîchir » not re-requesting a
  failed public link is read in the SDK, not run. So is the rest of that
  path (§4.1): on the web a failed photo stays failed for the life of the
  page, since the web `NetworkImage` never evicts a failed key, so neither
  « Rafraîchir » nor reopening the request asks for it again; the tab
  button shows it, a reload of the page asks again.
- **The manifest cannot see the private buckets' PUT rule** the web's KYC and
  deposit uploads depend on (§1.1): `r2-manifest.json` checks CORS on the
  public bucket only. Its comment is corrected here; a check is a follow-up.
- **The image tiles are not reachable by keyboard or screen reader**: a
  `GestureDetector` with no `Semantics` (SYSTEM.md §13.4), before this change
  and after it.
- **A failed image still opens the zoom** from the tile's edge, to the same
  failure and its « Actualiser », as `TimedCachedImage` opened it to its icon.
- **« Actualiser » was not run in a browser.** The error state it sits in was
  (§8.2, case D); the button is plain Flutter, held by the widget tests.
- **A missing object fails again after « Actualiser »**: the `<img>` does not
  say why it failed, so an expired link and a deleted file look alike. The
  new link fixes the first; the second keeps saying « Image indisponible ».
