# Admin console: images from R2 are drawn by the browser

| | |
|---|---|
| **Module** | admin (console) — [MODULES.md](../MODULES.md) |
| **BACKLOG** | B0.21 |
| **Status** | **Proposed 2026-11-12, built the same day** on `fix/admin-remote-images`, stacked on #775 (`fix/admin-kyc-queue`). « Actualiser » on a failed image added the same day on the owner's yes (§4). Not merged, not deployed. The merge is the owner's yes. |
| **Last updated** | 2026-11-12 |
| **Found** | 2026-11-12: a CORS probe found `cdn.myweli.com` refusing `https://admin.myweli.com`; this spec follows it to the KYC and deposit documents |
| **PRD ref / phase** | FR-WEB-AD-001 (KYC approval queue), the dispute view · V1 |
| **ROADMAP entry** | [2026-11-12-admin-remote-images.md](../roadmap/entries/2026-11-12-admin-remote-images.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Related** | [admin-kyc-queue-submitted.md](admin-kyc-queue-submitted.md) (#775, the PDF tile) · [salon-go-live-approval.md](salon-go-live-approval.md) §4.4 (B0.18's salon photos) · [web-pro-kyc.md](web-pro-kyc.md) · `infra/cloudflare/r2-manifest.json` |

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
- **Why it works with the tap and the zoom** (SDK, `_web_image_web.dart`): the
  framework gives its `<img>` `pointer-events: none`, so the
  `GestureDetector` around it still gets the tap; `RenderWebImage` applies
  `BoxFit`; a platform view takes the clip and the transform, so the rounded
  tile and `InteractiveViewer` behave as before (§8.2).
- `TimedCachedImage` stays everywhere else (SYSTEM.md §11.1); the console is
  the one exception (§11.2).

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

## 5. Security

- Nothing new is exposed: the same 5-minute signed links, to the same
  authenticated admin. The `<img>` request is `no-cors`, without an `Origin`
  header (observed, §8.2), and the page cannot read the bytes back.
- The request carries a `Referer` of the console's origin (the browser's
  default `strict-origin-when-cross-origin`). Nothing secret is in that origin.
- CSP: the console's bundle declares none (`mobile/web/index.html`, no
  `_headers` file), so `img-src` does not restrict R2. The live console sits
  behind Cloudflare Access and its own headers were not read: UNVERIFIED.

## 6. Performance

Each image becomes a platform view, which Flutter calls suboptimal. The
console shows at most four documents per KYC file and one proof per dispute.
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
- `test/infra/admin_remote_images_guard_test.dart`: walks the import graph
  from `lib/main_admin.dart`, comments stripped, and fails if any reachable
  file other than `AdminRemoteImage` draws a network image
  (`TimedCachedImage`, cached_network_image, `Image.network`, `NetworkImage`,
  `SvgPicture.network`), or if the widget loses `prefer` or gains a header.
  A walk that reaches fewer than 50 files, or misses the KYC and dispute
  screens, fails. **Blind to:** an image a package draws from a URL we pass,
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

## 9. Rollout

Merge after #775, which this is stacked on, then `deploy-admin.yml` (manual,
the owner's go). No backend change, no cloud change.

## 10. Not verified, and seen but left out

- **A real signed link on admin.myweli.com.** Production holds no KYC
  document; the mechanism is proven against a server that refuses CORS the
  same way (§8.2), not against R2 itself.
- **WebKit and Gecko**: not run.
- **B0.18's salon photos** come from `cdn.myweli.com`, which refuses the
  console's origin too (the 2026-11-12 finding): they should use
  `AdminRemoteImage`, and the guard will say so once they are imported.
  `salon-go-live-approval.md` §4.4 is left for that slice to update.
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
