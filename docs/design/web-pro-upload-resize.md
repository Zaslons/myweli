# Web Pro uploads — shrink each photo as the app does, before it is sent (decision 107)

| | |
|---|---|
| **Status** | **Built 2026-11-09** on `feat/web-pro-upload-resize` (from `main` 62547f91); **merged 2026-11-10** (`cbb50830`, #751), live: `myweli.com` serves the build of `9558c8ee`, which contains it, and the JS served to `/pro/medias`, `/pro/catalogue` and `/pro/profil` carries its error sentences (read 2026-11-12); no real upload tried, which needs a Pro session — approved the same day (the owner's four answers, §11, decision 107). The record is §13. **Reviewed twice the same day; every real finding fixed (§13.5) except the two toast findings**, which were fixed in `dd5fcd6f` and then moved out of this PR by `a23eda47` — the toast is shared with the consumer pages, and its full-width version collided with #737's « Carte » placement; they are a known residual here and a follow-up after #737 → #741 → #750 (all three merged 2026-11-10; no commit has touched `Toast.tsx` on `main` since #751, read 2026-11-12), on their `Toast.tsx`, with the train's placement guards green and the owner's word on the toast's width (§11 item 13). **Gated and reviewed again after that split (§13.8):** the two toast rows left WEB-SYSTEM §15, where they made the branch conflict with #741 and #750, and the 320 px toast bounds that hold on `main` came back as an e2e. The four answers unchanged; four new items for the owner (§11, items 10–13). The stored photos were counted the same day (§11, answer 3). |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-09 |
| **Module** | pro salon profile / portfolio — the web Pro area (`/pro/medias`, `/pro/catalogue`, `/pro/profil`) |
| **PRD ref / phase** | FR-PRO-MEDIA-001 (« client-side compression ») · NFR-DATA-001 (« Mobile-data thrift: compress uploads ») · PRD §« Expensive, intermittent data » · V1 |
| **ROADMAP entry** | [2026-11-09-web-pro-upload-resize.md](../roadmap/entries/2026-11-09-web-pro-upload-resize.md) |
| **BACKLOG** | Decision 107 lives in `docs/BACKLOG.md` on #741's branch (decisions 87–107 are on open branches); its « built » line is added there, not here. |
| **Governs** | `web/lib/image/compress.ts` (new) · `web/lib/pro/upload.ts` · `web/lib/pro/upload-hooks.ts` (new, the review) · `web/lib/upload-telemetry.ts` · `web/components/pro/MediasClient.tsx` · `web/components/pro/CatalogueClient.tsx` · `web/components/pro/ProfilClient.tsx` · their tests · `web/tests/e2e/pro-upload.spec.ts` · `web/tests/e2e/_jpeg.mjs` · `web/tests/e2e/stub-api.mjs`. **Not** the shared `web/components/Toast.tsx` / `web/lib/useToast.ts`: changed by `dd5fcd6f`, back to `main`'s since `a23eda47` (§11 item 13) |
| **App twin** | `mobile/lib/widgets/provider/image_picker_sheet.dart` (step 1) + `mobile/lib/services/api/api_image_upload_service.dart` (step 2) |
| **Contract** | **None.** `POST /uploads/sign`, the claim-time size check and every route stay as they are. |
| **Skills checked** | myweli-web-guardrails + myweli-verification-guardrails (invoked 2026-11-09). Design system read: WEB-SYSTEM §6, §7, §10; SYSTEM §15, §17. |
| **Read with** | [pro-image-upload-pipeline.md](pro-image-upload-pipeline.md) · [salon-logo.md](salon-logo.md) · [salon-cover-photo.md](salon-cover-photo.md) · [gallery-set-cover.md](gallery-set-cover.md) · [backend-upload-size-verification.md](backend-upload-size-verification.md) · [backend-r2-presigned-put.md](backend-r2-presigned-put.md) · [web-pro-network-failure.md](web-pro-network-failure.md) · [app-failure-messages.md](app-failure-messages.md) |

Evidence labels used throughout: **OBSERVED** = read in code at `origin/main` 62547f91, or measured
on 2026-11-09; **INFERRED** = follows from what was observed but was not itself run;
**UNVERIFIED** = not checked at all. The measurements of §5.3, §7 and §12 were taken while the spec
was drafted, in Playwright's Chromium 149.0.7827.55 (headless, `channel: 'chromium'`) on an Apple
M3 Pro, with a harness that sketched the rule (not this build's code); the build's own record is §13.

---

## 1. Goal & scope

### 1.1 What is wrong today (OBSERVED in code)

`web/lib/pro/upload.ts` signs `contentType: file.type` and PUTs **the picked `File` itself**
(`body: file`) to storage. The app never sends the original: it shrinks, re-encodes and strips
every photo first. Four Pro surfaces call the web helper:

| Surface | Call | Purpose | Input `accept` |
|---|---|---|---|
| Médias → « Photos » (photo 1 **is the salon cover**, `imageUrls[0]`) | `uploadGalleryImage` (`MediasClient.tsx:233`) | `gallery` | `image/*` |
| Médias → « Avant / Après » (two uploads per pair) | `uploadGalleryImage` (`MediasClient.tsx:349`) | `gallery` | `image/*` |
| Catalogue → Employés → photo of a staff member | `uploadGalleryImage` (`CatalogueClient.tsx:610`) | `gallery` | `image/jpeg,image/png,image/webp` |
| Profil → logo | `uploadLogoImage` (`ProfilClient.tsx:213`) | `logo` | `image/jpeg,image/png,image/webp` |

There is no separate cover upload on the web: the cover is the first gallery photo (« La première
sert de couverture. », `MediasClient.tsx`). KYC documents use `uploadKycDocument` (out of scope,
§1.3).

What that costs, in order of harm:

1. **A photo over 5 MiB is uploaded, then refused, with no reason given.** R2 ignores the signed
   size on a presigned PUT (`upload_signing_service.dart`: the cap is « ADVISORY »), so the PUT
   succeeds; at save, `UploadVerificationService.verify` finds `size > 5 * 1024 * 1024`, deletes
   the object and answers `upload_too_large`; the web shows « Échec de l’envoi » (Médias) — the
   whole upload spent for nothing. A 48 MP photo fixture is 8,993,268 bytes. (Path OBSERVED in
   code; not run end to end against a backend.)
2. **Mobile data.** A 12 MP fixture is 4,822,780 bytes as picked and 446,301 bytes after the rule
   (−91 %, OBSERVED). At Lighthouse's slow-4G uplink (750 kbit/s) that is ~51 s against ~4.8 s
   (INFERRED, arithmetic).
3. **Every app viewer pays for it too.** The pipeline serves « the single optimized file as-is »
   (pro-image-upload-pipeline.md §1); the website's public pages go through `next/image`, but the
   apps download the stored object itself (INFERRED from the spec and the app's
   `TimedCachedImage`; not measured on a device).
4. **Location and device data go public.** A camera JPEG carries EXIF (GPS, make/model, time); the
   web stores it unchanged in the **public** bucket (INFERRED: nothing in the path rewrites the
   bytes). Whether `cdn.myweli.com` strips metadata on delivery is **UNVERIFIED** — and the raw
   object would keep it either way.
5. **Formats the server refuses get a generic failure.** Médias accepts `image/*`, so a HEIC, AVIF,
   GIF or BMP can be picked; the sign refuses any type outside `image/jpeg|png|webp` with
   `invalid_input` and the person reads « Échec de l’envoi » (OBSERVED in code).

salon-logo.md §7 named the gap: « web sends the raw file (native type) ».

### 1.2 Goal

**A photo uploaded from the website is the file the app would have uploaded**: the same size rule,
JPEG at quality 80, the camera's orientation baked into the pixels, no metadata — produced in the
browser before anything is signed or sent. The person sees no new step; uploads get faster; the
5 MiB refusal stops happening; HEIC/AVIF/GIF/BMP start working wherever the browser can read them.

### 1.3 Scope — the owner's answer 2 (2026-11-09): « Pro photos only »

**In scope** — the four Pro photo surfaces in §1.1 (gallery + cover, before/after, staff photo,
logo); a shared, injectable preparation module; two new failure sentences (a third added by the
review fixes, §2.6); telemetry for the new
stage; tests; the doc corrections in §9.3.

**Out of scope, with reasons**

- **Consumer uploads** — review photos (`web/lib/account/review-photos.ts`) and deposit proofs
  (`web/lib/booking/deposit.ts`) have the same gap (the app compresses both: `purpose: 'review'`
  through `ApiImageUploadService`, deposits through `api_appointment_service.dart`'s identical
  1600/80 compressor). **Follow-up, not built here:** each adopts `compressForUpload` with one call
  before its sign, and signs `image/jpeg` (§5.1 keeps the module free of Pro imports for that).
- **KYC documents** (`uploadKycDocument`): identity papers and PDFs, a private bucket, and the app
  does **not** apply this rule to them (it uses `file_picker` with `compressionQuality: 30`,
  `pro_kyc_screen.dart`). The same 5 MiB trap exists there; it is a separate owner decision.
  `uploadKycDocument` is unchanged and still PUTs the `File` it was given.
- A cropper, filters, server-side variants, a HEIC decoder (§5.4), changing the `accept`
  attributes, a progress percentage or a cancel button (§2.5).
- Photos already stored (§11, answer 3).

### 1.4 Fit with the architecture

Client-only, inside the Pro area. It mirrors the app's seam: the app injects an `ImageCompressor`
(`typedef ImageCompressor = Future<Uint8List?> Function(String source)`) so the network flow is
testable without the native compressor; the web upload helpers take a `compress` dependency with
the browser implementation as the default, and the preparation module itself takes `probe` /
`decode` / `encode` seams. No BFF, backend, contract, CSP or `next.config.mjs` change (the CSP
already allows what this needs, §6.5).

---

## 2. UX & flows

### 2.1 Entry points

Unchanged: the four inputs in §1.1. Nothing new to click.

### 2.2 Happy path

1. The person picks a photo (as today).
2. **Prepare** (new, invisible): read the header → check it → ask the browser at what size it
   shows the picture → check, once, that its canvas gives back what is drawn → decode at the target
   size → draw on white → encode JPEG 0.80. About 0.1–0.2 s on a laptop (103–208 ms, 8–48 MP, §7);
   the busy state shows meanwhile (« Téléversement… » on Médias' pickers — « Avant » / « Après »
   too since the review —, the button spinner in Catalogue/Profil).
3. Sign with `contentType: 'image/jpeg'` and the same purpose as today.
4. PUT the **prepared bytes** (not the `File`) with exactly the signed headers.
5. The photo appears / the logo or staff photo is staged, as today.

Order is the app's: **compress, then sign** (`api_image_upload_service.dart`). A file that cannot
be read therefore never spends a signature — which matters for the logo, signed at 10 per hour
(`identity_limits.dart`, `signLogo: 10`), and keeps the gallery's 60 per hour for real photos.

### 2.3 All states

| State | What the person sees | Change? |
|---|---|---|
| Loading (preparing + sending) | Médias → Photos: the add label reads « Téléversement… » and the input is disabled; Médias → Avant / Après: the picker on its way reads « Téléversement… », **both** pickers and « Ajouter la paire » wait (**new**, the review: nothing showed before; the app shows « Envoi… » and holds its add button); Catalogue/Profil: `Button isLoading` (spinner, `aria-busy`, disabled). When it ends, the control gets the focus back (§2.7) | Avant / Après: new |
| Success | The photo appears in the grid / the pair can be added / the thumbnail shows | No change |
| Error — the image cannot be read | **New sentence** `UNREADABLE` (§2.6) on the surface's existing channel | New |
| Error — the image is too large to prepare | **New sentence** `TOO_LARGE` (§2.6) | New |
| Error — the browser alters what a canvas gives back (anti-fingerprinting) | **New sentence** `BLOCKED` (§2.6; the review's F4) | New |
| Error — sign / PUT / network / preparation crash | The surface's existing sentence (« Échec de l’envoi », « Échec de l’envoi de la photo. », « Échec de l’envoi du logo. ») | No change |
| Empty | n/a — the surfaces' empty states are untouched | No change |

Channels: Médias → the `Toast` (`role="status"`, `aria-live="polite"`, error kind 6 s), for
« Photos » and « Avant / Après » alike; Catalogue → **its own** `<p role="alert">` directly under
the photo button (since the review: it shared the form's alert, placed after the hours block
— `CatalogueClient.tsx:670` on `main` — and at 320 px with doubled text only « Cette image n’a »
showed above the fold); Profil → `<p role="alert">` under the logo block.

### 2.4 Edge cases

- **Sideways camera JPEG (EXIF orientation 6/8).** Comes out upright: OBSERVED in the draft on a
  4032×3024 stored / orientation 6 fixture → 1600×2133, the markers in place.
- **Unusual EXIF layouts** (two Exif segments, an Orientation stored as a LONG, a PNG `eXIf`, an
  Exif segment after the frame header, an AVIF `irot`). The browser decodes, so **the browser's
  reading of the displayed size sizes the target** (`<img>` once loaded, header only) — never ours
  alone. Before the review the target came from our reading and the decoder was forced to both
  sides: where the two differed, the photo was squeezed into the other orientation's frame
  (OBSERVED by the review on four layouts; fixed and pinned in real Chromium, §13.5).
- **Panorama** 12000×3000 → 2400×600; **16:9** 4000×2250 → 2400×1350; **small** 600×800 → 600×800
  (never enlarged, still re-encoded so its metadata goes) — all OBSERVED in the draft.
- **Transparent PNG logo.** Drawn on white (the `secondary` token, #FFFFFF) before encoding.
  Without that, a transparent pixel becomes **black** in a canvas JPEG (OBSERVED: corner pixel
  (0,0,0) without the fill, (255,255,255) with it). The web already renders the logo inside a
  `bg-secondary` circle (`Hero.tsx`), so the website looks identical.
- **A logo that grows.** A 13,355-byte flat PNG logo becomes 38,798 bytes of JPEG (OBSERVED). Small
  in absolute terms; accepted for one format end to end and stripped metadata.
- **Animated GIF/WebP** → the first frame (INFERRED: what a canvas draw of an image does).
- **Wide-gamut (Display P3) photos** → converted to sRGB, as the app's iOS compressor does
  (`preferredRange = Standard` in flutter_image_compress's `UIImage+scale.m`, OBSERVED in source).
- **Before + after picked back to back.** Since the review both pickers are disabled while one
  side is on its way; **preparations stay serialized** too (one at a time, a module-level queue)
  — the second waits for the first, whatever started it.
- **Very large sensors (108/200 MP modes).** Refused before decoding above **64 MP** with
  `TOO_LARGE` (§5.6): a renderer killed for memory loses the Profil form's unsaved edits (Médias
  saves each gesture at once). A deliberate, named deviation from the app (§5.2).
- **HEIC on Chrome/Firefox/Android** → `UNREADABLE` (Chromium cannot decode HEIC: OBSERVED,
  `InvalidStateError: The source image could not be decoded.`). HEIC on Safari → works (INFERRED;
  UNVERIFIED here). iPhone Safari usually hands over a JPEG anyway (§5.4).
- **Leaving the page while a photo is prepared or sent** → **nothing is signed, sent or added after
  that.** Médias (the page — switching its tabs does not count), the staff form and Profil hand
  their upload an `AbortSignal` aborted when they unmount; the helper checks it before the
  signature and before the PUT, and the page before adding anything. The first version of this line
  said « nothing was signed or stored » and was **false** (the review's F3, OBSERVED: leaving Médias
  41 ms after picking a photo still signed it, sent it and saved the gallery with it ~3 s later — a
  wrong photo « cancelled » by leaving went public). A PUT already in flight when the page is left
  completes; its object stays under `pending/` and is never claimed.
- **A browser that alters canvas output** (Firefox's `resistFingerprinting`, LibreWolf, Tor,
  Mullvad, Brave's strict mode) → refused with `BLOCKED` before anything is decoded. Once per
  session, four palette swatches go through the real path (canvas → JPEG → decode → read back) and
  must come back within 48 per channel: the small per-pixel noise some browsers add passes, a blank
  or random read-back does not. A pass is kept; a refusal is checked again at the next pick (a
  canvas permission prompt may have been answered). The review's F4: without it the photo would
  have been sent blank or as noise, with no error (INFERRED for those browsers — only Chromium was
  run; the mechanism OBSERVED by simulation, §13.5).
- **Slow network** → the PUT is ~10× smaller; failures keep today's handling and telemetry.

### 2.5 Progress and cancel — decided: neither is added

- **No cancel.** The app has none; preparation is bounded (measured ≤ 0.5 s for 48 MP on a laptop,
  §7) and the send is now ~0.3–0.5 MB. The input is re-usable as soon as the busy state ends.
- **No percentage.** `fetch` exposes no upload progress, and the app's `onProgress` values (0.1 →
  0.4 → 0.9 → 1.0) are step markers, not bytes. A two-step label (« Préparation… » then
  « Envoi… ») was considered and dropped: the preparation step is too short to read on most
  devices, and it would add strings to three surfaces for no decision the person can take.
- `web/components/Button.tsx` is **not touched**: it is in the five store-linked pages' import
  graph (OBSERVED, §9.2).

### 2.6 Copy (French)

Two new sentences — three since the review fixes —, exported as constants from
`web/lib/pro/upload.ts` and pinned by a test:

| Key | Sentence | When |
|---|---|---|
| `UPLOAD_UNREADABLE_MESSAGE` | « Cette image n’a pas pu être lue. Choisissez une image JPEG, PNG ou WebP. » | the browser cannot decode the file (HEIC on Chrome, a corrupt file, a renamed document) |
| `UPLOAD_TOO_LARGE_MESSAGE` | « Cette image est trop grande pour être préparée ici. Choisissez une image plus petite. » | over 64 MP by its header or as the browser shows it, or still over the 5 MiB cap after preparation |
| `UPLOAD_BLOCKED_MESSAGE` | « Votre navigateur empêche de préparer cette image. Essayez avec un autre navigateur. » | the canvas check fails (§2.4). **Proposed copy, added by the review fixes — to confirm by the owner (§11, item 10)** |

Why these and not the generic sentence: SYSTEM §17 keeps two sentences for « it failed » but lets
a refusal with its own words keep them; both are the person's to fix by choosing another image,
which the generic « Une erreur est survenue. Réessayez. » would hide (retrying the same file fails
the same way). « image », not « photo », because the logo uses the same words. Typography per
§17.1: `’`. Vouvoiement. Everything else keeps today's sentence.

**Where the web's words differ from the app's** (named, not mirrored): for a file it cannot read the
app says « Image invalide » (`api_image_upload_service.dart`, when its compressor throws or gives
nothing), and it has **no** « trop grande »: it accepts any size (it subsamples on decode, §5.2
item 3). The web keeps its two longer sentences, because each says what to do next.

### 2.7 Accessibility

- No new control, no new focus stop. WCAG 2.4.11: nothing new overlays anything, except that the
  toast's known residual (the half-width pill, below; §11 item 13) is larger with these sentences.
  Whether a control given the focus back sits under that pill at 320 px with doubled text is
  **UNVERIFIED**: the picture (§13.6) is 390 px at normal text, and no focus e2e runs at 320.
- **The focus comes back to the control when its busy state ends.** The first version of this line
  said « focus stays where it is » and was **false** on three surfaces (the review's MAJOR,
  OBSERVED in Chromium at 390 px): the control is disabled while it works, and a control disabled
  while it holds the focus drops it to `<body>` — Médias' photo input, Catalogue's « Ajouter une
  photo », Profil's « Ajouter un logo » (`main` already did this; preparation lengthened it).
  `useFocusBackAfter` (`lib/pro/upload-hooks.ts`) gives it back when the busy state ends, unless the
  person put the focus somewhere else meanwhile; « Avant » / « Après », disabled while busy since
  the review, use it too. Pinned in Chromium: the loss is checked first, then the return, on all
  four (§13.5).
- Errors arrive on channels that already announce: `role="alert"` (inserted, assertive) in
  Catalogue/Profil; the always-mounted `role="status"` toast region in Médias (WEB-SYSTEM §7).
  **The same sentence twice is very likely not read twice — a known residual of this PR.** Two
  unreadable files picked within 6 s re-render the same text in place: 0 changes in the toast
  region (OBSERVED by the review on `106fb82d`; a screen reader very likely stays silent the second
  time — INFERRED, none was run). It holds on `main` for any repeated toast. `dd5fcd6f` fixed it
  (an id per `show`, the pill keyed on it, so a repeat was a new node in the region); `a23eda47`
  took that change out of this PR again with the rest of the shared toast's: a follow-up
  (§11 item 13), which also registers it in WEB-SYSTEM §15.
- The busy state: `aria-busy` + disabled on the `Button`; Médias' inputs `disabled` while
  uploading, « Avant » / « Après » included since the review.
- 200 % text: the three sentences (72, 85 and 83 characters) wrap inside their `<p>` and the toast
  pill, nothing clipped (the review's reading on `106fb82d`, at 320 px with doubled text). At 320 px
  with normal text an e2e holds the « trop grande » pill whole inside the screen — its four edges
  within the viewport the page reports, its sentence not clipped (the pill's own scroll width and
  height within its box) — with no sideways scroll, and pins its half width (§13.8: 160 × 136 px at
  x=80, y=408). **The toast has half the screen to wrap in — a known residual of this PR.** The
  region is centred by `left-1/2 -translate-x-1/2` with no
  width, so its box is capped near half the screen: at 320 px with Android-style doubled text the
  « trop grande » toast measured 182 px wide and ran from y=88 to y=544 — about 80 % of the 568 px
  screen — for 6 s (OBSERVED by the review on `106fb82d`; 160 px wide with normal text). It holds on
  `main` for any long toast; these longer sentences make it easier to hit. `dd5fcd6f` fixed it (the
  region spanning the screen inside the side gutter, the pill centred and capped at `max-w-xl`);
  `a23eda47` took it out of this PR again, because the shared toast also serves the consumer pages
  and, merged with #737, covered the « Carte » label: a follow-up after #737 → #741 → #750, on their
  `Toast.tsx`, with the train's placement guards green and the owner's word on the width
  (§11 item 13), which also registers it in WEB-SYSTEM §15. The pill as it stands, at 390 px: §13.6.
- 48 px targets: untouched.

### 2.8 Reuse

`putToStorage` and `reportUploadFailure` (`web/lib/upload-telemetry.ts`), the existing `Toast` /
`role="alert"` channels, the `DepositUpload`-style result union (`web/lib/booking/deposit.ts`).
**No new Tailwind class** is needed, so the shared stylesheet must not change (§9.2).

---

## 3. API & contract

No change. The web keeps calling the pro BFF `POST /api/pro/uploads/sign` →
`POST /uploads/sign` with `{ contentType, purpose }` (`purpose ∈ gallery | logo`), and now always
sends `contentType: 'image/jpeg'` — as the app does (`'contentType': 'image/jpeg'` in
`api_image_upload_service.dart`). The response's advisory `maxBytes` (5,242,880) is read as the
last guard before the PUT (§5.6). `docs/api/openapi.yaml`: untouched; `npm run gen:api` must show
no drift.

## 4. Data model

None. Object keys keep their `pending/{purpose}/{salonId}/{random}.{ext}` shape; `ext` is now always
`jpg` for these four surfaces (server-built from the content type).

---

## 5. Architecture & patterns

### 5.1 Modules

```
web/lib/image/compress.ts   (new — shared, no React, no Pro imports)
  UPLOAD_RULE                            { longSide 2400, shortSide 1600, quality 0.8,
                                           maxInputPixels 64_000_000, maxBytes 5 MiB }
  targetSize(width, height)              pure: the app's arithmetic (§5.2)
  parseImageHeader(bytes, complete)      pure: stored size of a JPEG (+ the FIRST Exif's Orientation,
                                         SHORT × 1), PNG (+ an eXIf before IDAT), WebP, GIF, BMP,
                                         AVIF/HEIC (the largest ispe); else null — never decoded
  probeImageHeader(blob)                 reads 256 KiB, up to 4 MiB when the size lies further on
  orientationTransform(o, w, h)          pure: EXIF's eight cases, for the last-resort path
  pixelsMatch(pixels, expected, tol)     pure: the canvas check's comparison (48 per channel)
  megapixelBucket(pixels)                pure: '<12' | '12-24' | '24-50' | '50-64' | '>64' | 'unknown'
  compressForUpload(file, deps?)         → { ok: true, blob, width, height, pixels }
                                         | { ok: false, reason: 'unreadable' | 'too_large' | 'blocked'
                                                          | 'failed', pixels }
  (deps: probe / measure / canvasWorks / decode / encode / maxBytes seams; defaults = the browser
   implementation in §5.3; `measure` and `canvasWorks` added by the review fixes)

web/lib/pro/upload.ts
  uploadGalleryImage(file, { compress = compressForUpload, signal } = {}) → ProUpload
  uploadLogoImage(file,    { compress = compressForUpload, signal } = {}) → ProUpload
  type ProUpload = { ok: true; url: string }
                 | { ok: false; reason: 'unreadable' | 'too_large' | 'blocked' | 'failed' | 'aborted' }
  uploadFailureMessage(reason, fallback) → the sentence for the surface
  UPLOAD_UNREADABLE_MESSAGE, UPLOAD_TOO_LARGE_MESSAGE, UPLOAD_BLOCKED_MESSAGE
  uploadKycDocument — unchanged

web/lib/pro/upload-hooks.ts   (new with the review fixes; React, client only)
  useLeaveSignal()                       → () => AbortSignal, aborted when the component unmounts
  useFocusBackAfter(busy, ref)           gives the focus back to `ref` when `busy` ends, if it was lost
```

`lib/image/` rather than `lib/pro/`: the consumer helpers can adopt it later without importing
from the Pro area. The four call sites map `reason` to copy through `uploadFailureMessage`:
`unreadable` → `UNREADABLE`, `too_large` → `TOO_LARGE`, `failed` → the sentence each surface shows
today. A `null` return before becomes `{ ok: false, reason: 'failed' }`, so every path that showed a
failure still does.

### 5.2 The rule to mirror — the owner's answer 1 (2026-11-09): « The app's exact rule »

Read in the plugin sources pinned by `mobile/pubspec.lock` (OBSERVED): image_picker 1.2.4
(image_picker_android 0.8.13+17 `ImageResizer.java`, image_picker_ios 0.8.13+6
`FLTImagePickerImageUtil.m`) and flutter_image_compress 2.5.1 (flutter_image_compress_common 1.1.1
`BitmapCompressExt.kt`, `UIImage+scale.m`).

**Step 1 — the picker** (`pickImage(maxWidth: 2400, maxHeight: 2400, imageQuality: 90)`): fit
inside 2400×2400 keeping the aspect ratio; the scaled side is `round()`ed; never enlarged.
**Step 2 — the compressor** (`compressWithFile(minWidth: 1600, minHeight: 1600, quality: 80, format:
jpeg)`, defaults `autoCorrectionAngle: true`, `keepExif: false`): `scale = max(1, min(w/1600,
h/1600))`, both sides divided and **truncated** (`toInt()` on Android, `floor()` on iOS); EXIF
orientation applied to the pixels; no metadata written; JPEG quality 80.

Composed, on the **displayed** (orientation-corrected) size, with `long`/`short` its sides:

```
if long  > 2400: short = round(short × 2400 / long); long = 2400
if short > 1600: long = floor(long × 1600 / short);  short = 1600
```

i.e. **the short side at most 1600 and the long side at most 2400, never enlarged.** Worked
(computed, and OBSERVED in the draft on the fixtures marked ✓):

| Picked (displayed) | Result | |
|---|---|---|
| 4032×3024 (12 MP, 4:3) | 2133×1600 | ✓ |
| 3024×4032 | 1600×2133 | ✓ |
| 6048×8064 (48 MP) | 1600×2133 | ✓ |
| 8160×6144 (50 MP) | 2125×1600 | |
| 12000×9000 (108 MP) | refused on the web (§5.6); 2133×1600 in the app | ✓ |
| 4000×2250 (16:9) | 2400×1350 | ✓ |
| 12000×3000 (4:1) | 2400×600 | ✓ |
| 6000×4000 (3:2) | 2400×1600 | |
| 4800×3400 | 2258×1600 (the row where floor and round part) | |
| 3000×3000 | 1600×1600 | |
| 2400×1600 | 2400×1600 (re-encoded only) | ✓ |
| 600×800 | 600×800 (re-encoded only) | ✓ |

**Doc drift corrected with this spec:** pro-image-upload-pipeline.md §5 said « longest edge
~1600px » and salon-logo.md §7 « ≤1600 px »; the code does short side ≤ 1600 **and** long side ≤
2400.

**Where the web knowingly differs from the app** (each named, none visible in normal use):

1. **One resample and one encode** instead of two (the app re-encodes at q90 in the picker, then
   at q80): fewer losses, the same dimensions.
2. **Transparency → white.** The app's JPEG path would turn it black on Android (INFERRED: Android
   `Bitmap.compress(JPEG)` on a premultiplied transparent pixel; **UNVERIFIED on a device** — worth
   a separate check of the app's logo upload).
3. **A 64 MP ceiling** (§5.6). The app accepts any size (it subsamples on decode and retries on
   out-of-memory with a doubled `inSampleSize`); a browser cannot subsample.
4. **The JPEG encoder.** Chromium writes libjpeg's IJG-scaled tables (OBSERVED: the luminance table
   of quality 80) plus a 456-byte sRGB ICC profile (APP2); Android's libjpeg-turbo is the same
   scaling (INFERRED); iOS ImageIO maps 0.8 its own way. Byte sizes will differ by a few percent.
5. **Mirrored orientations (2, 4, 5, 7).** The web applies EXIF's full transform. The app's
   Android compressor rotates by `ExifInterface.getRotationDegrees()` only (`Exif.kt:18` in
   flutter_image_compress_common 1.1.1), which maps 2 → 0°, 4 → 180°, 5 → 270° and 7 → 90° and
   **drops the mirror** (OBSERVED: disassembled from androidx exifinterface 1.4.2 in the local Gradle
   cache). So on those four values the web differs from the Android app in the right direction.
   The iOS compressor: not checked.
6. **Exact arithmetic.** The plugins divide by a floating-point scale (Kotlin `Float` on Android,
   `float` on iOS), so on some sizes they land a pixel short — a short side of 1599 — and where
   step 1 lands on an exact half (12480×9529 → 1832.5) the plugin's `w / h` ratio can round the
   other way. The web computes the exact integers. Measured on 5,998 random sizes against a
   literal transcription of the Android formulas: 185 differ by 1 px and 1 by 2 px; the plugin
   gave a 1599 short side on 187 of them; **every usual camera size (4:3, 3:4, 16:9, 48/50/108 MP)
   matches to the pixel** (OBSERVED, `tests/image-compress.test.ts`).

### 5.3 Where it runs — main thread, no Worker

Measured on four ways of doing it while drafting (§12): **A** decode at full size, then one scaled
draw; **B** read the header, ask the decoder for the target size (`createImageBitmap(file, {
imageOrientation: 'from-image', resizeWidth, resizeHeight, resizeQuality: 'high' })`), draw,
encode; **C** = B in a dedicated Worker; **D** `<img>` + `img.decode()` + `<canvas>.toBlob`.

| | 12 MP | 48 MP | 108 MP | main-thread long tasks (all runs, ×1 and ×4) |
|---|---|---|---|---|
| A — wall time / memory peak Δ | 86 ms / +216 MiB | 250 ms / +437 MiB | 433 ms / +1,068 MiB | 0 |
| **B** | 127 ms / **+122 MiB** | 208 ms / **+266 MiB** | 272 ms / +575 MiB | 0 |
| C (Worker) | 128 ms / +85 MiB | 204 ms / +272 MiB | — | 0 |
| D (`<img>`) | 110 ms / +179 MiB | 243 ms / +317 MiB | 316 ms / +391 MiB | 0 |

(Medians of 3 runs at ×1, 2 at 108 MP. Memory = peak minus baseline RSS of the whole Chromium
process tree, polled every 40 ms. The long-task observer was proven able to fire: a 120 ms busy
loop on the same page registered one 120 ms task.)

**Decision: B on the main thread, D as the fallback, no Worker in v1.**

- B roughly **halves the memory peak** of A (122 vs 216 MiB at 12 MP, 266 vs 437 at 48 MP) for the
  same output — the number that matters on a 2–3 GB Android phone.
- **No main-thread long task was observed in any method**, including with the main thread throttled
  ×4 (INFERRED from that: Chromium decodes and encodes off the main thread). A Worker's only
  measured gain is −37 MiB at 12 MP (none at 48 MP) for a new bundling path, a new file type and a
  new test surface. Revisit if field telemetry (§6.4) shows trouble.
- **Fallback chain** (feature-detected once, cached):
  1. `createImageBitmap` present **and** it applies EXIF orientation **when asked for a size**, the
     way the pipeline calls it — checked once with an embedded 198-byte 16×8 JPEG tagged
     orientation 6, black on the left and white on the right, decoded at 4×8: it must come back 4×8
     **and** black above white (its pixels read back). → path B. If the resize options are refused,
     the same picture is decoded at full size (A). (The review's F7: the first probe, a 2×1 decoded
     at its own size, could not see an engine that drops the orientation only when it scales; one
     simulated that way is now sent down path D, and the photo comes out upright — pinned, §13.5.)
  2. Otherwise `<img>` + `decode()` (D), which follows CSS `image-orientation: from-image`.
  3. If that does not orient either (very old engines), rotate on the canvas with the probe's own
     orientation value (`orientationTransform`, EXIF's eight cases).
- **The displayed size is the browser's** (the review's F1): `<img>`'s `naturalWidth`/`Height` once
  it has loaded — `load` needs the header only (measured in Chromium 149: 1 ms to `load` against
  45 ms to `decode()` for a 48 MP JPEG, 17 ms to `load` a 43 MB 64 MP PNG), so no full decode
  happens before the ceiling (INFERRED from those times). Used wherever `<img>` orients the probe;
  on the last-resort path the header's own reading is used, and the rotation follows that same
  reading, so the two agree by construction. The target is computed from it and only then the
  decoder is asked for both sides.
- **A canvas check, once** (the review's F4, §2.4): four palette swatches through canvas → JPEG →
  decode → read back, within 48 per channel; else `blocked`.
- Always `drawImage(source, 0, 0, w, h)` into a canvas of exactly the target size — so an engine
  that ignores `resizeWidth/resizeHeight` still produces the right file (INFERRED for Safari and
  Firefox; **UNVERIFIED** — neither was run). The same draw makes an engine that applied the size
  before the rotation (a bitmap of the target's sides swapped) come out with the right geometry: a
  quarter turn and two axis scalings that end on the target's sides compose to the correct
  mapping, at the cost of a second resample (reasoned; the review's F7 « stretch » claim is
  refuted on that ground, §13.5).
- The output must be a JPEG: a canvas that cannot write one falls back to PNG, and those bytes are
  refused (`failed`), never sent as `image/jpeg` (the review's F8).
- Encode with `OffscreenCanvas.convertToBlob` where present, else `HTMLCanvasElement.toBlob`.
- **Never allocate a canvas at the source size** — only the target (≤ 3.84 MP, far under iOS
  Safari's canvas-area limit).
- Release every `ImageBitmap` with `close()` in a `finally`; revoke every object URL; set every
  canvas to 0×0 once encoded and drop the fallback `<img>`'s source; the queue keeps the order,
  never the last file (the review's F5).

### 5.4 Formats

| Picked | Chromium (OBSERVED) | Safari | Result |
|---|---|---|---|
| JPEG, PNG, WebP | decodes | decodes (INFERRED) | JPEG |
| GIF, BMP, AVIF | decodes (GIF OBSERVED by the e2e; GIF, BMP and AVIF by the review) | GIF/BMP yes, AVIF 16+ (INFERRED) | JPEG — formats the server refuses today now work; their size is read first (GIF screen, BMP header, the largest AVIF `ispe`) so the ceiling applies (the review's F2) |
| HEIC / HEIF | **cannot decode** (`InvalidStateError`) | decodes (INFERRED, Safari 17+) | `UNREADABLE` on Chrome/Firefox/Android; JPEG on Safari; its size is read from `ispe` |
| TIFF, SVG, PDF, anything else | not decoded | not decoded | `UNREADABLE` **before decoding** since the review (F6): a file whose size cannot be read is never handed to the decoder — a renamed document of any size used to be. TIFF on Safari, which Safari could decode, is refused with the rest |

**HEIC from iPhones**: iOS Safari converts a HEIC to JPEG when the input's `accept` does not list
HEIC (INFERRED from WebKit's documented behaviour; **UNVERIFIED** here) — two of the four surfaces
(Catalogue, Profil) list `image/jpeg,image/png,image/webp`; Médias' inputs (« Photos » and
« Avant / Après ») list `image/*` (corrected by the review: this line said « three of our four
inputs »). Either way the file is then
decoded and shrunk. The real gap is **a HEIC carried to a computer and picked in Chrome**; the
sentence tells the person what to pick instead. A WASM HEIC decoder (~1.5 MB) is not worth it
before telemetry (§6.4) shows HEIC arriving.

The `accept` attributes are **not changed**: widening them would invite files Chrome cannot read,
narrowing Médias would remove GIF/BMP/AVIF that now work.

**Orientation: the browser's reading wins.** The draft read JPEG EXIF only and sized the target
from it; the review measured four layouts where Chromium read otherwise and the photo came out
squeezed (a PNG `eXIf` before the image data; two Exif segments, either order; a LONG-typed
Orientation). The displayed size now comes from the browser (§5.3), and our reader is aligned to
Chromium for the last-resort path (first Exif wins, SHORT × 1 only, PNG `eXIf` before IDAT). Where
Chromium ignores the tag (a PNG `eXIf` after the image data, a WebP `EXIF`) both agree. A layout no
reader of ours sees — an Exif segment after the frame header, which Chromium applies — is the e2e's
proof that the browser's reading is the one used (§13.5). An AVIF/HEIC whose `meta` box lies past
the first 4 MiB (after its image data) cannot be sized and is refused as unreadable — a named
residual (§11, item 12).

### 5.5 EXIF orientation and metadata

- **Orientation** is applied to the pixels, then dropped with everything else (the app's
  `autoCorrectionAngle: true`).
- **Metadata is stripped by construction**: a canvas encode writes only what the encoder writes.
  OBSERVED in the draft on every output: segments `APP0` (JFIF) + `APP2` (a 456-byte sRGB profile)
  only — no `APP1`/`Exif`, no GPS bytes; the input carried Orientation, Make, Model and a GPS IFD.
- **Always re-encode**, even a file already inside the rule: that is the privacy guarantee, and
  the app does the same (`compressWithFile` always encodes).
- The guarantee covers uploads made through MyWeli's web and apps. A hand-rolled client can still
  store metadata: the server does not inspect bytes (§6).

### 5.6 Size limits and quality

| Limit | Value | Where it is held |
|---|---|---|
| Output long / short side | ≤ 2400 / ≤ 1600 px | `targetSize` (§5.2) |
| JPEG quality | 0.80 | `UPLOAD_RULE.quality` (the app's `quality: 80`) |
| Output bytes, before signing | ≤ 5 MiB, else not signed → `TOO_LARGE` | `compressForUpload` (`UPLOAD_RULE.maxBytes`) |
| Output bytes, after signing | ≤ the sign response's `maxBytes` when present, else not sent → `TOO_LARGE` | `upload.ts` (the number is the server's; the claim-time check is authoritative) |
| Input pixels | ≤ 64 MP (64,000,000) by the header **and** by the browser's own size, else `TOO_LARGE` before decoding; a picture whose size cannot be read is not decoded (`UNREADABLE`) | `compressForUpload` — a phone-memory guard (every format since the review's F2/F6) |
| Input bytes | **no limit** (a 9 MB 48 MP JPEG is the case this fixes) | — |

The output guards should never fire on a photo: the worst case measured — full-band random noise
already at 2400×1600 — encodes to **2,437,880 bytes**, under half the cap (OBSERVED in the draft).
They stay as backstops because the cap is the server's, not ours.

The 64 MP threshold is INFERRED, not measured on a phone: 48 MP costs +266 MiB and 108 MP +575 MiB
in desktop Chromium (path B); 48 MP iPhone shots and 50 MP Android full-resolution shots must pass.
To revisit with a real low-end device (§11, build questions). The draft's residual — GIF, BMP,
AVIF and HEIC decoded without that check (a 72 MP GIF and AVIF were decoded whole, OBSERVED by the
review) — is closed: their sizes are read, and the browser's size is checked as well (a GIF frame
drawn larger than its logical screen).

---

## 6. Security & authz

### 6.1 Nothing about authority moves

The server stays the authority on everything it holds today, unchanged: the content-type allowlist
at sign, the server-built key and purpose namespace, the per-identity sign limits (gallery 60/h,
logo 10/h), the origin allowlist and **the 5 MiB claim-time check** (T61), all as in
`upload_signing_service.dart`, `upload_verification_service.dart` and
`provider_catalog_service.dart`. Client-side shrinking is a bandwidth, cost and privacy measure for
honest clients — **not** a control: a modified client can still upload any ≤ 5 MiB JPEG/PNG/WebP.
Threat-model delta: **none** (no new surface, no new trust boundary).

### 6.2 Server-side checks — none added now

Considered and not proposed for this slice: a claim-time header check of dimensions, or
server-side re-encoding/stripping on promotion. Both need image parsing in the Dart backend, would
also act on app uploads, and buy nothing an honest client does not already do. Logged as a
hardening idea, not a dependency.

### 6.3 Privacy

The real gain: GPS coordinates, device make/model and capture times no longer reach a public bucket
from the website. Photos already stored: §11, answer 3.

### 6.4 Telemetry

`reportUploadFailure` gains a `'prepare'` stage, reported for `unreadable`, `too_large`, `blocked`
and a preparation `failed` — at Sentry level **`warning`**, not `error` (the review's F9: every HEIC
picked in Chrome lands here; the person was told what to do and nothing of ours broke; `sign`,
`put` and `response` stay `error`). A page left mid-upload (`aborted`) reports nothing. Three tags: `upload_prepare_reason`, `upload_input_type` (the picked
file's `type`, kept only when it is MIME-shaped, else `unknown`) and `upload_megapixels` (a coarse
band: `<12`, `12-24`, `24-50`, `50-64`, `>64`, `unknown`) — **never the file name** (user content),
never bytes or dimensions to the pixel. Purpose: learn whether HEIC actually arrives before buying a
decoder. The existing `sign` / `put` / `response` reports are unchanged. `lib/sentry-scrub.ts` still
applies.

### 6.5 CSP and secrets

No change needed (OBSERVED in `next.config.mjs` `cspDirectives`): `createImageBitmap` on a `File`
and canvas encoding make no request; `img-src` already allows `blob:` and `data:` (the `<img>`
fallback uses a `blob:` URL); no Worker is added. No secret is involved.

---

## 7. Performance

### 7.1 Budgets

| Budget | Value | Status |
|---|---|---|
| Preparation, laptop, ≤ 48 MP | ≤ 300 ms | OBSERVED in the draft: 103–208 ms (B, M3 Pro) |
| Preparation, low-end Android (Tecno/Infinix class), ≤ 50 MP | ≤ 2 s | **INFERRED** ≈ 0.9 s at 12 MP, ≈ 1.5 s at 48 MP (B × ~7, the single-core gap between an M3 Pro and a Helio G85-class SoC); **UNVERIFIED on a device** |
| Main-thread long tasks from preparation | none > 50 ms | OBSERVED in the draft: 0 in Chromium (×1 and ×4) |
| Memory peak Δ, 48 MP, desktop Chromium | ≤ 300 MiB | OBSERVED in the draft: +266 MiB (B) |
| Output bytes | typically 0.3–0.5 MB; never > 5 MiB | OBSERVED in the draft: 306–449 KB on photos; 2.44 MB worst case |
| Public-page JS | **0 bytes** | the module is imported only by `lib/pro/upload.ts` (walker, §9.2) |

**About the ×4 CPU throttle:** Chrome's DevTools throttle slows the main thread only. Path C (the
Worker) moved from 128 to 135 ms at 12 MP when throttled ×4, while B went 127 → 328 ms
(OBSERVED). So ×4 is **not** a stand-in for a cheap phone where every thread is slow — hence the
INFERRED low-end row above and the device check in §8.4.

### 7.2 Quality

- **Real-photo-like fixtures**: every path lands within 0.6–0.7 dB of a Lanczos downscale encoded
  the same way (12 MP: 37.04–37.06 dB against 37.59; 48 MP: 37.90–37.92 against 38.63; luma PSNR,
  OBSERVED). On these grainy fixtures the metric barely separates a good filter from
  nearest-neighbour (36.5–36.9 dB), so it does **not** by itself prove the filter.
- **Zone plate** (the aliasing target, 4032×3024 → 2133×1600): Chromium's `'high'` smoothing,
  A/B/D alike, 21.4 dB against Lanczos; smoothing off, 12.9 dB (= PIL nearest, 12.9 dB, the
  metric's control). So Chromium's filter removes most aliasing but is **not** Lanczos-grade
  (Lanczos + q80 = 34.0 dB). No better option exists in the browser without a WASM resampler; the
  app's own path is no better: on Android, image_picker decodes with a power-of-two `inSampleSize`
  and then scales with `filter = false` (nearest), before the compressor's bilinear pass —
  OBSERVED in `ImageResizer.java` and `BitmapCompressExt.kt`.

### 7.3 The cover — what this means for decision 106

New web uploads will be at most 2400 px wide (landscape) or 1600 px (portrait), as app uploads
already are. `next/image` never enlarges, so a cover candidate wider than the stored photo is served
at the photo's width: decision 106's « finest grain » trade-off (3840w on sideways phones) then
only concerns photos stored larger than 2400 px — old web uploads (INFERRED). A portrait cover is
cropped to 3:2 from a 1600 px-wide source: soft on a 2× laptop screen at full width, exactly as an
app-uploaded portrait is today. Parity, named.

---

## 8. Testing plan

### 8.1 Unit (Vitest, jsdom — no canvas there, so the browser work sits behind the seams)

- `tests/image-compress.test.ts`
  - `UPLOAD_RULE` pinned (2400 / 1600 / 0.8 / 64,000,000 / 5,242,880).
  - `targetSize`: the table of §5.2 plus the edges 2401×100, 1601×1601, 1×1, 2400×1600,
    1600×2400, 20000×1; and a **property test** over 6,000 seeded random sizes (1–20000 per side)
    plus every size from 1590 to 2410 against 1600 and 2400: never enlarged, caps kept,
    orientation kept, maximal, proportions within the two roundings — and against a literal
    transcription of the two Android plugin formulas (`calculateTargetSize` with `Math.round`, then
    `calcScale` in `Float` with truncation): within 2 px everywhere, equal on the camera sizes.
  - `parseImageHeader` on hand-built bytes: JPEG SOF0 and SOF2; APP1 Exif in both byte orders with
    orientation 1/3/6/8; an APP1 that is XMP; an orientation out of range; a cut JPEG (`more` while
    reading, `null` when complete); PNG IHDR; WebP VP8, VP8L, VP8X; GIF, PDF, garbage, empty →
    `null`. `probeImageHeader` finds a frame header behind 325 KB of APP segments (the second read).
  - `orientationTransform`: for each of the eight orientations, where the stored top-left and
    top-right corners land, from EXIF's own definition.
  - `megapixelBucket` boundaries.
  - `compressForUpload` with fake probe/decode/encode: decode asked for the oriented target;
    no header → full decode then sized; > 64 MP by header → `too_large` **without decoding**;
    exactly 64 MP decoded; decode throws → `unreadable`; encode `null` or throws → `failed` and the
    bitmap still released; output > 5 MiB → `too_large`, exactly 5 MiB → ok; a throwing probe is
    no header; **one at a time** (a second picture's probe waits for the first decode).
- `tests/pro-upload-prepare.test.ts` — `upload.ts` with an injected `compress`: the sign body says
  `{ contentType: 'image/jpeg', purpose }` for a picked PNG; the PUT body **is the prepared blob,
  not the `File`**, with exactly the signed headers; `unreadable` / `too_large` / `failed` → no
  request at all and one `prepare` report with the MIME type and band and **no file name**; a
  non-MIME `type` → `unknown`; the sign's `maxBytes` refuses a larger blob before the PUT; the two
  sentences pinned; KYC still signs the picked type and PUTs the `File`.
- `tests/pro-upload-messages.test.tsx` — the callers: Médias photos (three reasons) and
  Avant / Après on the toast; Catalogue's staff photo and Profil's logo (three reasons each) on
  their `role="alert"`; a successful logo stages without an alert.
- `tests/upload-telemetry.test.ts` — the `prepare` tags; the other stages carry none;
  `uploadInputType`.
- Updated for the new return shape: `pro-upload-network.test.ts` (`{ ok: false, reason: 'failed' }`
  for gallery/logo, `null` for KYC), `pro-medias.test.ts`, `pro-profile.test.ts`,
  `pro-medias-like-app.test.tsx`.

### 8.2 End to end (Playwright, real Chromium decoding)

- **Fixtures are drawn by the test, procedurally — no committed image, no face, nothing
  downloaded:** an `OffscreenCanvas` draws a gradient, stripes and two coloured squares and
  encodes it; the test splices a hand-built APP1 (Orientation 6, Make, and a GPS IFD) into the
  JPEG (`tests/e2e/_jpeg.mjs`, cross-checked with Pillow while building).
- `stub-api.mjs`: the gallery/logo sign answers with an upload URL per object
  (`/r2-upload/<key>`), signs only JPEG/PNG/WebP and pins the content type that was **asked for**
  (as `upload_signing_service.dart` does); `/r2-upload/<key>` **records** the PUT — content type,
  byte length, JPEG frame size, whether Exif or the fixture's camera/GPS markers are present, the
  luminance table, the bytes — and a test-only `GET /__stub/uploads?key=` returns it. Keyed, so two
  spec files uploading at once cannot read each other's record.
- `tests/e2e/pro-upload.spec.ts` (every non-local request aborted, popups closed; Médias' gallery
  save answered in the browser so the shared stub's seed is untouched):
  1. Médias: the 4032×3024 orientation-6 JPEG with GPS → signed `image/jpeg`, stored as
     1600×2133 JPEG, quality-80 table, no Exif / Make / GPS, red top-left and blue top-right; the
     same reader sees all of it on the input (the control).
  2. The same with `createImageBitmap` removed → the `<img>` path gives the same file.
  3. Médias: random bytes named `.heic` → `UNREADABLE` on the toast, **no sign request**.
  4. Avant / Après: a header-only 12000×9000 JPEG → `TOO_LARGE`, no sign (a decoder would have said
     « pas pu être lue »); then a 3000×2000 JPEG → 2400×1600.
  5. Profil: a transparent 1200×1200 PNG logo → signed `image/jpeg` under `logo`, stored 1200×1200
     (never enlarged), white corners, the ring intact; the control reads alpha 0 on the input.
  6. Catalogue: an unreadable « PNG » → `UNREADABLE` on the alert, no sign; a 600×800 PNG → a
     600×800 JPEG.
- `pro.spec.ts`: the staff photo and Médias uploads that sent `Buffer.from('fake-…-bytes')` now send
  the 1×1 GIF of `tests/e2e/_pixel.ts` (fake bytes are refused as unreadable now). The KYC test
  keeps its fake bytes — KYC is not prepared, and that difference is itself a check.
- **Ports are machine-wide**: before any run, check the owners of 3000/8787; if busy, run the
  targeted specs through an untracked config on other ports (never committed).

### 8.3 Guards planned — each to be watched red on a copy of the committed tree

| Mutation | Expected red |
|---|---|
| No resize (pass-through: `targetSize` returns its input) | unit table + property; e2e dimensions |
| Orientation ignored (the header's quarter turn not applied to the size) | unit `orientedSize`; e2e dimensions / corners |
| Orientation ignored by the decoder (`imageOrientation: 'none'`) | e2e corners (if the engine honours `'none'`) |
| EXIF kept (the original APP1 copied into the output, as image_picker's `copyExif` does) | e2e Exif / Make / GPS |
| Quality changed in the encoder (0.80 → 0.92) | e2e luminance table |
| `UPLOAD_RULE.quality` changed | unit pin |
| Long-side cap removed | unit table |
| Enlargement allowed (a small picture scaled up to 1600) | unit table + property; e2e logo 1200×1200 |
| Step 2 rounds instead of truncating | unit table (4800×3400) |
| Transparency not flattened (no white fill) | e2e logo corners |
| 64 MP ceiling removed | unit; e2e « trop grande » |
| `maxBytes` guard removed (compress) / sign `maxBytes` guard removed (upload) | unit, each its own test |
| Not serialized | unit « one at a time » |
| Telemetry leaks the file name | unit |
| Sign content type left as the original (`file.type`) | unit; e2e logo signed/stored as PNG |
| The `File` PUT instead of the prepared blob | unit; e2e |

### 8.3b Added by the review fixes

The guards each review finding gained, and the mutations that turned them red, are in §13.5: the
parser cases (GIF, BMP, AVIF/HEIC, first Exif, SHORT only, PNG `eXIf` before/after IDAT); the flow
cases (the browser's reading wins, no header → nothing decoded, the browser's size over the
ceiling, `blocked`, a non-JPEG output, aborted before the sign / before the PUT); every reason on
every surface, the error kind, the busy states, the focus, the alert's place; and in Chromium the
odd EXIF layouts, an engine that drops the orientation when it scales, GIF / BMP / AVIF over
64 MP, leaving Médias mid-upload, a blanked canvas, the focus on four surfaces, and a comparison of
every upload with its input place by place. The toast's repeat (unit) and the toast at 320 px
(e2e) were guarded too, and left with the toast change in `a23eda47` (§11 item 13); the 320 px
e2e came back without its full-width bound — the pill whole inside the screen (its four edges),
its sentence unclipped, no sideways scroll, and the half width pinned as the residual (§13.8).

### 8.4 Manual, before calling it done (UNVERIFIED today)

A low-end Android phone (Tecno/Infinix class, Chrome) with 12 MP and 50 MP shots — time and no tab
kill; an iPhone (Safari) picking a HEIC from Photos; macOS Safari picking a `.heic` from Finder;
Firefox desktop; a transparent PNG logo on each.

---

## 9. Rollout & scope discipline

### 9.1 Branch and PR — the owner's answer 4 (2026-11-09): « Own PR from main »

A new branch **from `main`** (`feat/web-pro-upload-resize`), its own PR, independent of #737, #741,
#750 and #738, merged on the owner's word — possibly before Apple's decision, since none of the five
store-linked pages' files change (§9.2). No feature flag: it is client-only and a revert is the
rollback. #737, #741 and #750 also edit `stub-api.mjs`, the design index and `WEB-SYSTEM.md`, and
#741 and #750 `pro.spec.ts` (OBSERVED: `git diff --name-only origin/main...<tip>`). What
`git merge-tree --write-tree` shows against each open PR's tip after a `git fetch` (2026-11-09,
OBSERVED; each pair on its own — the train's order was not replayed):

- **Before §13.8's fixes** (at `aa9b9814`, the gate): clean with #737 (`83ce6ae9`) and #738
  (`fe929194`); with #741 (`8e05eea5`) and #750 (`b79d0828`), **one conflict, in docs only** —
  WEB-SYSTEM §15, where this branch's register rows 39 and 40 (the two toast findings) sat on the
  lines right after row 38, which #741 and #750 both rewrite. Nothing in code: `Toast.tsx` no
  longer conflicts with any of them since `a23eda47`.
- **Since** (§13.8's record commit): the two rows left this PR — the follow-up registers them on
  top of the train (§11 item 13) — and `merge-tree` is clean with all four, run on that commit
  after it was made (§13.8). Its only change to `WEB-SYSTEM.md` is §5's focus bullet (§9.3).

### 9.2 The five store-linked pages (Apple)

None of `lib/pro/upload.ts`, `lib/upload-telemetry.ts`, `MediasClient`, `CatalogueClient`,
`ProfilClient` was in the five pages' closure when the spec was drafted (OBSERVED with the b114
walker's rules); `components/Button.tsx` **is** in it, so the build must not touch it (§2.5). A new
`lib/image/compress.ts` imported only by `upload.ts` stays outside by construction — to be re-run on
the built branch with its control (the Médias/Profil/Catalogue closure must reach the new module),
plus the built stylesheet compared with `main`'s (Tailwind scans `lib/**`, so a word in the new
file could emit a class). Recorded in §13.

### 9.3 Docs in the same PR

This spec (status → Built in the record commit); the design index row;
`pro-image-upload-pipeline.md` §5 and `salon-logo.md` §7 corrected to the real rule (§5.2);
`web-pro-network-failure.md` §5 says what a failed Pro photo upload returns now and names the
`prepare` stage; a roadmap entry. `docs/BACKLOG.md` is **not** edited here (decision 107 lives on
#741). WEB.md and WEB-SYSTEM.md state no upload rule (OBSERVED: no match for an upload size,
`uploads/sign` or `compress` in either), so neither gains one; WEB-SYSTEM §5 gains one bullet,
the focus given back after a busy state (§2.7, added by the review fixes). WEB-SYSTEM §15 gains no
row: the two toast residuals are registered there by the follow-up (§11 item 13, §13.8).

## 10. Definition of done

- [x] `tsc` + lint clean (`--max-warnings=0` on touched files); unit + targeted e2e green (§13.2).
- [x] Every mutation in §8.3 watched red on a copy of the committed tree, the unmutated copy green
      (§13.3) — except `imageOrientation: 'none'`, which changes nothing in Chromium 149 and is
      recorded as **no result**; the decoder-blind mutation stands in for it.
- [x] Five pages: walker + control re-run; stylesheet and scripts compared with `main` (§13.2).
- [x] No new Tailwind class or arbitrary value; `Button.tsx` untouched; `gen:api` shows no drift.
- [ ] Manual checks in §8.4 — **not done** (no phone, Safari or Firefox was used; §13.4).
- [x] Docs in §9.3; spec status → Built.
- [ ] Feature branch ✓, authored as the owner with no AI attribution ✓; **the PR is not opened**
      (the owner opens or asks for it).

## 11. Decisions (the owner, 2026-11-09 — decision 107)

1. **The rule — « The app's exact rule ».** Short side at most 1600 px, long side at most 2400 px,
   never enlarged, JPEG quality 80, EXIF orientation applied, all metadata removed (GPS included).
   (§5.2; the app: `image_picker_sheet.dart` `maxWidth`/`maxHeight` 2400 at `imageQuality` 90, then
   `api_image_upload_service.dart` `minWidth`/`minHeight` 1600, quality 80, JPEG.)
2. **Which uploads — « Pro photos only ».** Médias (gallery + cover), before/after, staff photos,
   logo. Consumer review photos, deposit proofs and KYC are out; the consumer pair is a follow-up of
   one call each (§1.3).
3. **Photos already stored — the owner's words: "the app is not yet launched and no real salons
   are in it, you can count the photos but keep that in mind".** A read-only count is approved;
   stored photos are test/demo uploads only. A first attempt, on 2026-11-09 around 09:40 UTC, never
   reached the bucket: Secret Manager refused it the R2 secrets while the GCP project's billing was
   disabled (`BILLING_DISABLED` on `secretmanager.googleapis.com`). **The count ran on 2026-11-09
   around 13:43 UTC**, once the owner had restored billing: a script that first read the four R2
   secrets (`R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`) from Secret
   Manager at the versions `infra/gcp/service.yaml` pins (`gcloud secrets versions access`,
   read-only; held in memory, nothing printed), then made only `ListObjectsV2` and ranged `GET`s on
   the public bucket (the first 256 KiB of each object, 2 MiB when the frame header lay further)
   and printed aggregates only — no key, id or secret. What it read (OBSERVED by that script; its
   JSON result is the record, kept outside the repo):

   | | Objects | Format | Bytes | Uploaded (storage time, UTC) | Beyond the app's rule | Exif | GPS |
   |---|---|---|---|---|---|---|---|
   | `gallery/` | 5 | JPEG ×5 | 7,739,452 in all, largest 3,067,857 | 2026-08-26, 21:20:37 → 21:20:55 | **3** | 1 | 0 |
   | `logo/` | 3 | JPEG ×3 | 134,125 in all, largest 69,425 | 2026-08-27 → 2026-10-22 | 0 | 1 | 0 |
   | `pending/` | 0 | — | — | — | — | — | — |

   8 objects in the bucket, all of them in these two groups. « Beyond the rule » = short side over
   1600 or long side over 2400, read from the JPEG frame header; « Exif » = an APP1 `Exif` segment
   before that header; « GPS » = a non-empty GPS IFD inside it — XMP and IPTC were not read (below).
   4 of the 5 gallery photos and 1 of the 3 logos carry at least one sign of not having been
   prepared by the rule (too large, or Exif); these two « sign » counts are lower bounds (below). Production has no
   public salon (`GET /providers` answers a total of 0, BACKLOG decision 51 — reported to this
   record, not re-checked), so these are test or demo uploads (INFERRED). **Not established:** which
   client sent each file; the **XMP** (APP1 `http://ns.adobe.com/xap/1.0/`) and **IPTC** (APP13)
   segments, which the script skipped, so GPS or camera data there is not excluded — the « sign »
   counts are lower bounds (metadata in XMP or IPTC would be a sign too), while the Exif counts are
   exact for what they name, an APP1 `Exif` segment before the frame header; which Exif fields the
   two files with Exif hold besides GPS (a camera make or a date may remain — the script did not
   classify them); whether `cdn.myweli.com` strips metadata on delivery (**UNVERIFIED**). Per the
   owner, **nothing stored is re-encoded before launch**; a purge or re-encode of the test data, if
   wanted, is a separate owner decision. This spec prevents new full-size, metadata-carrying web
   uploads; it does nothing to what is already stored (verification-guardrails §8).
4. **When — « Own PR from main ».** Independent of #737/#741/#750/#738, merged on the owner's word,
   possibly before Apple's decision since none of the five store-linked pages' files change.

For the build, smaller (decided above, open to the owner's override):

5. The **64 MP** ceiling (§5.6) — to confirm on a real low-end phone; raise or drop it if the phone
   copes.
6. A **HEIC decoder** — only if `prepare` telemetry shows HEIC arriving.
7. The **app's transparent logos** may turn black on Android (§5.2 item 2) — a device check of the
   Pro app, separate from this spec.
8. A **server-side** dimension check or re-encode (§6.2) — a hardening idea, not proposed.
9. **Follow-up:** consumer review photos and deposit proofs adopt `compressForUpload` (one call each,
   sign `image/jpeg`); KYC stays a separate decision.

Raised by the two reviews of 2026-11-09 (§13.5) — none changes the four answers above:

10. **The « navigateur » sentence is proposed copy.** « Votre navigateur empêche de préparer cette
    image. Essayez avec un autre navigateur. » (83 characters) is new, written by the review fixes
    for the canvas check (§2.4, §2.6). To confirm or reword before merging.
11. **A wording suggestion for « trop grande », not applied.** The UX review found that « trop grande
    pour être préparée ici » assumes the person knows the photo is « préparée », and suggested
    « …trop grande pour être envoyée depuis le site » (and not to point to the app until it has a
    store link). The sentence was in the approved spec, so it stays until the owner says otherwise.
12. **Residuals of the format fixes, named.** An AVIF/HEIC whose `meta` box lies past the first
    4 MiB cannot be sized and is refused as unreadable; TIFF, which Safari could decode, is refused
    with every other format whose size is not read; an engine where `createImageBitmap` orients but
    `<img>` does not would size the target from our own reading, where the review's F1 squeeze could
    return (no such engine is known; Safari and Firefox were not run).
13. **The two toast findings left this PR; they are a follow-up.** Both are real, and both hold on
    `main` for any long or repeated toast (§2.7): (1) at 320 px with Android-style doubled text,
    Médias' « trop grande » toast is 182 px wide and runs from y=88 to y=544 — about 80 % of the
    568 px screen — for 6 s, nothing clipped, because the region is centred by `left-1/2
    -translate-x-1/2` with no width; (2) a second unreadable file picked within 6 s changes nothing
    in the toast region, so a screen reader very likely stays silent (INFERRED; none was run) — both
    measured by the UX review on `106fb82d`. They were fixed in the shared `Toast` / `useToast` by
    `dd5fcd6f`, then **moved out by `a23eda47`** on 2026-11-09 (not an owner decision; in line with
    answer 2, « Pro photos only »), for three reasons: the toast also serves the consumer pages
    (favourites, search, account — OBSERVED: `FavoriteButton`, `RechercheClient`, `AccountClient`
    import it on `main`); merged with #737 (`feat/web-swiss-cards` `83ce6ae9`), two of #737's
    tests in `web/tests/e2e/site-look.spec.ts`, « at 320/360, level with the toast », failed
    because the full-width toast covered the « Carte » label (OBSERVED by this branch's gate on
    that merge, and again by the gate of `aa9b9814` with `dd5fcd6f`'s classes put back in a copy:
    the label ends at 76.14 px, the toast started at 43.59 px at 320 and at 63.59 px at 360; 390
    green); and #741 (`8e05eea5`) and #750 (`b79d0828`) conflict with it in one block of
    `Toast.tsx`, where they carry `aboveBookingBar` and the toast-sliding code. Where the toast
    sits next to « Carte » is the owner's Carte decisions 99–104.

    **The follow-up** is done after the merge train #737 → #741 → #750, on top of their
    `Toast.tsx`, keeping the train tip's placement guards green: `site-look.spec.ts` « the
    favourite’s message and « Carte » (decision 100) » — 24 tests, all green on the #750 merge in
    the gate of `aa9b9814` — which replaced #737's « level with the toast » tests in #741's
    `88a5c41d` (OBSERVED: « level with the toast » is on 2 lines of that file at `83ce6ae9` and on
    none at `8e05eea5` or `b79d0828`, where the decision-100 block is). #737's two tests are
    history here: the ones `dd5fcd6f`'s classes turned red. **A wider toast needs the owner's
    word:** #737's `web-swiss-cards.md` §2.4 (its row « The toast and « Carte » ») builds on the
    toast being at most half the screen wide at normal text, and its mutation Y-E20, « The toast
    runs the screen’s width, over the word », must be red — so widening it changes what decisions
    91 and 100 accepted. Until then both findings are known residuals of this PR, recorded here and
    in §2.7, and the e2e « at 320 px the « trop grande » toast stays whole on the screen, its
    sentence unclipped, with no sideways scroll » pins the half width (the pill at most 161 px
    wide at 320 px, normal text):
    the line the follow-up flips (§13.8). **They are not in WEB-SYSTEM §15 yet:** `9d721459`
    registered them there as rows 39 and 40, right after row 38, which #741 and #750 rewrite, and
    that made this branch conflict with both (§9.1); §13.8's record commit took them out, and the
    follow-up adds them to §15 on top of the train.

---

## 12. Measurements while drafting (2026-11-09)

Host Apple M3 Pro (12 cores, 18 GiB); Playwright 1.61.1, Chromium 149.0.7827.55, `channel:
'chromium'`, headless; every request not to 127.0.0.1 aborted, popups closed; a fresh browser per
run; fixtures served from 127.0.0.1. A sketch of the rule written to measure — not this build's
code. Fixtures procedural (no faces, nothing from a model, never committed): a generated room
picture (2448×3264) and arithmetic derived from it; a zone plate; random noise; a ring-and-bar logo.

| Fixture | Bytes in | Out | Bytes out | B ×1 / ×4 | A ×1 / ×4 | C ×1 / ×4 | D ×1 / ×4 |
|---|---|---|---|---|---|---|---|
| 12 MP, stored 4032×3024, orientation 6, GPS | 4,822,780 | 1600×2133 | 448,583 (B) | 127 / 328 ms | 86 / 150 | 128 / 135 | 110 / 282 |
| 48 MP, 6048×8064 | 8,993,268 | 1600×2133 | 351,479 | 208 / 440 | 250 / 486 | 204 / 214 | 243 / 660 |
| 8 MP, 2448×3264 | 2,373,939 | 1600×2133 | 342,305 | 103 / 302 | 68 / 122 | 116 / 110 | 91 / 223 |
| 108 MP, 12000×9000 | 9,640,772 | 2133×1600 | 313,742 | 272 / — | 433 / — | — | 316 / — |
| 12 MP landscape, orientation 1, GPS | 3,204,502 | 2133×1600 | 448,670 (A) | | 82 | | |
| 16:9 JPEG / WebP, 4000×2250 | 1,940,905 / 1,562,360 | 2400×1350 | 320,783 / 321,916 (A) | | 67 / 128 | | |
| 4:1, 12000×3000 | 4,301,562 | 2400×600 | 130,655 (A) | | 130 | | |
| 600×800 | 65,265 | 600×800 | 58,159 (A) | | 10 | | |
| noise PNG 2400×1600 | 11,534,944 | 2400×1600 | **2,437,880** (A) | | 73 | | |
| logo PNG 1200×1200, transparent | 13,355 | 1200×1200 | 38,798 white / 25,481 black (no fill) | | 13 | | |
| HEIC (from the 8 MP picture, `sips`) | 1,697,054 | — | **not decodable** in Chromium (A: `InvalidStateError`, D: `EncodingError`) | | | | |

Memory (peak Δ RSS, ×1): see §5.3. Long tasks: 0 in every run; control fired (one 120 ms task).

**UNVERIFIED:** Safari (macOS/iOS) and Firefox behaviour; any real phone (time, memory, tab kills);
iOS Safari's HEIC→JPEG conversion; whether `cdn.myweli.com` strips metadata; how many stored web
uploads exist or carry GPS (counted since, without telling web from app uploads, GPS read in Exif
only: §11, answer 3); the app's black-logo behaviour.

## 13. Record (2026-11-09)

### 13.1 Commits

On `feat/web-pro-upload-resize`, from `origin/main` 62547f91: `0f3f3467` the spec (docs first) ·
`5c30f9b9` the code and tests · `106fb82d` this record. Then the review fixes (§13.5): `1c30d958`
the pipeline · `3ad93153` the Pro surfaces · `dd5fcd6f` the toast · `0e941eb8` the e2e · the spec
and doc corrections · the record of §13.5 · the picture (§13.6). Then the split (§13.7):
`a23eda47` reverts `dd5fcd6f` and the one e2e test that held only with it — the shared toast is
`main`'s again (§11 item 13) · `9d721459` the docs brought to that, with the stored photos' count
(§11, answer 3) · the picture made again against `a23eda47` (§13.6). Then the gate and the review
of `aa9b9814` (§13.8): `85954e53` the 320 px toast bounds back as an e2e · the record of §13.8
(rows 39 and 40 out of WEB-SYSTEM §15, the follow-up's condition, the count's wording). Nothing
pushed.

### 13.2 What ran, on `5c30f9b9` (OBSERVED)

- `tsc --noEmit`: exit 0. ESLint `--max-warnings=0` on every touched file: exit 0.
- Unit (Vitest): the full suite, **199 files, 2,643 tests, green**; the upload files alone
  (the mutation harness's set), 143 green.
- E2E (Playwright 1.61.1, its headless Chromium; an untracked config on ports 3100/8887 — both
  checked free first — with every host but 127.0.0.1/localhost unresolvable in the browser, on top
  of the spec's own abort route; build telemetry off): `pro-upload.spec.ts` 6/6 and `pro.spec.ts`
  41/41 — **47 passed**. The full e2e suite was not run here (`booking.spec.ts` and
  `served-html.spec.ts` hard-wire 8787); CI runs it.
- `npm run gen:api`: `lib/api/schema.ts` regenerated with **no diff** — no contract drift.
- **The five store-linked pages.** The b114 walker (`import`/`export`/`import()`, `@/` and
  relative paths), seeded with the root layout, `not-found`, `error`, `global-error` and the five
  pages: **56 files on `main` and on the branch, the same list** (sha-256 of the list
  `264b5f618d7fc60b…` on both); **no changed file is in it**; `components/Button.tsx` and
  `styles/tokens.ts` are (both untouched). Control: the closure of the Médias, Profil and
  Catalogue pages is 83 files on the branch and **reaches `lib/image/compress.ts`** (82 on `main`,
  where the file does not exist). Then three production builds in **the same directory** —
  `main`, `main` again, the branch: the nine entries' scripts (layout, the five pages, `not-found`,
  `error`, `global-error`) are **byte-identical between `main` and the branch**; the two `main`
  builds differ from each other only in Sentry's per-build debug IDs (the noise floor). The three
  CSS files are byte-identical in all three builds; the Tailwind CLI output too (sha-256
  `357e9a43…` on `main` and on `5c30f9b9`).
- **Found by that comparison, before the record:** the first version of the code commit
  (`97e5c179`, amended into `5c30f9b9` before any push) wrote « failing to shrink a Pro photo »
  and « the canvas transform » in comments. Tailwind scans `lib/**`, comments included, so the
  shared stylesheet gained `.shrink` and `.transform` (+242 bytes) — on every page, the five
  store-linked ones included. Reworded (three more lines emitted classes the stylesheet already
  had: « block », « resize » twice), and `tests/upload-no-css.test.ts` now requires the three
  upload modules to emit **no** Tailwind class, with a control proving the probe sees one.

### 13.3 Guards watched red

Each mutation on a fresh `git archive 5c30f9b9 web` (node_modules cloned, the worktree never
edited); a replacement that did not match exactly once aborted the run, and the mutated file was
checked to differ. Unit = the eight upload test files plus `upload-no-css` (143 tests); e2e =
`pro-upload.spec.ts` (6 tests) on a fresh production build of the mutated copy.
**21 mutations: 20 red, 1 no result; the control green.**

| Mutation | Unit | E2E | What fired |
|---|---|---|---|
| **Control — no edit** | **143 green** | **6 green** | — |
| No resize (`targetSize` returns its input) | 17 red | 3 red | the table, the property test, « decodes AT the target size »; e2e frame size (Médias ×2, Avant/Après) |
| Orientation ignored in the size (no quarter turn) | 2 red | 2 red | `orientedSize`, « decodes AT the target size »; e2e frame 2133×1600 |
| Decoder told `imageOrientation: 'none'` | green | **green — no result** | Chromium 149 still applies EXIF orientation under `'none'`: the edit applied, the behaviour did not change |
| Decoder blind to EXIF (the APP1 renamed before decoding) | green | 2 red | e2e corners: **top-left blue** (0,0,254) where red belongs — the size right, the pixels sideways |
| EXIF kept (the original APP1 copied into the output) | 5 red¹ | 2 red | e2e `exif`, `makeMarker`, `gpsMarker` all true |
| Encoder quality 0.92 (rule untouched) | green | 5 red | e2e luminance table ≠ IJG quality 80 (every upload) |
| `UPLOAD_RULE.quality` 0.92 | 1 red | — | the pin |
| Long-side cap removed | 7 red | — | the table (12000×3000 …), the property test |
| Enlargement allowed | 10 red | 2 red | the table (1×1 …), the property test; e2e logo 1600×1600, staff 1600×2133 |
| Step 2 rounds instead of truncating | 2 red | — | 4800×3400 → 2258×1600, the camera-size equality |
| No white fill | green | 1 red | e2e logo corners not white |
| 64 MP ceiling removed | 1 red | 1 red | « NOTHING is decoded »; e2e « trop grande » never shown (« pas pu être lue » instead) |
| The 5 MiB guard in `compressForUpload` removed | 1 red | — | « still over 5 MiB after preparing » |
| The sign's `maxBytes` guard removed | 1 red | — | « over the signed maxBytes is not sent » |
| Not serialized | 1 red | — | « one at a time » |
| The file name in the report's purpose | 5 red | — | the message pin and `not.toContain` |
| The file name in the event's `extra` (message and tags unchanged) | 4 red | — | `not.toContain('IMG_0042')` itself |
| MIME tag not sanitized | 1 red | — | `uploadInputType` |
| Sign asks for the picked type (`file.type`) | 2 red | 2 red | the sign body; e2e logo and staff photo signed `image/png` |
| The `File` PUT instead of the prepared blob | 3 red | 5 red | the PUT body; e2e frame size / Exif |
| « shrink » back in a comment of `upload-telemetry.ts` | 1 red | — | `upload-no-css` |

¹ For the wrong reason: jsdom's `File` has no `arrayBuffer`, so the mutated code throws and every
fake-backed flow test fails; the e2e is the guard for this one.

### 13.4 Not verified

- Safari (macOS, iOS) and Firefox: decoding, `resizeWidth`/`resizeHeight`, EXIF orientation, HEIC
  on Safari, iOS Safari's HEIC→JPEG hand-over. Any real phone: time, memory, tab kills, the 64 MP
  ceiling (§8.4 — none of it done).
- The last-resort canvas rotation (`orientationTransform` on a decoder that ignores EXIF) never
  ran in an engine that really ignores EXIF; the pipeline review ran it in Chromium with the EXIF
  removed before `<img>` decoded, and all eight orientations came out right (OBSERVED by the
  review, not by this build). The `<img>` path did run, in Chromium, with `createImageBitmap`
  removed.
- The two sentences at 200 % text on a 320 px screen: measured by the UX review (no clipping; the
  toast's half-width wrapping — fixed in `dd5fcd6f`, moved out by `a23eda47`, a known residual:
  §11 item 13). The e2e of §13.8 reads 320 px at normal text only.
- The full e2e suite (CI runs it); the CWV budget (no public page changed).
- The stored photos' count (§11, answer 3) did not run in this build, which used no production or
  cloud access; it ran separately, read-only, later the same day.

### 13.5 The two reviews of 2026-11-09, and the fixes

Two independent reviews of `106fb82d` — the pipeline, and the UX with the tests — found no
BLOCKER, one MAJOR, eleven MINOR and nine NIT. **Each finding was checked before it was fixed**: on
a production build of `106fb82d` running the new e2e specs (« reproduced on `106fb82d` » below), by
a mutation that puts the old behaviour back (§13.5.3), or by reading the code. Commits: `1c30d958`
the pipeline · `3ad93153` the Pro surfaces · `dd5fcd6f` the toast · `0e941eb8` the e2e · then the
docs. **Later the same day `a23eda47` took the toast fix out again** (§11 item 13, §13.7): the two
toast findings are the only real ones this PR leaves open. **None of the owner's four answers
changed**; what needs the owner is §11, items 10–13.

#### 13.5.1 Finding by finding

| Finding | Real? — how it was checked | Done | Commit |
|---|---|---|---|
| **F1** (pipeline, MINOR) the photo squeezed when the browser reads the orientation otherwise | **Real.** Reproduced on `106fb82d`: « two Exif segments, 6 then 1 », which Chromium shows 2000×3000, uploaded 2400×1600 | The browser's own size (`<img>` once loaded, header only) sizes the target; our reader aligned (first Exif, SHORT × 1, PNG `eXIf` before IDAT); five layouts in the e2e, one only the browser reads (§5.4) | `1c30d958` · `0e941eb8` |
| **F2** (pipeline, MINOR) no 64 MP ceiling for GIF, BMP, AVIF, HEIC | **Real.** No size read for them at `106fb82d` (`compress.ts:87–91`, `:117`); on `106fb82d` a 9000×8000 GIF header never got « trop grande » (the review measured a 72 MP GIF and AVIF decoded whole) | Their sizes read (GIF screen, BMP header, the largest `ispe`), and the browser's size checked too | `1c30d958` |
| **F3** (pipeline, MINOR) leaving the page does not cancel; §2.4 false | **Real.** Reproduced on `106fb82d`: Médias left while the photo was prepared (the decode slowed by 1.5 s) — a signature was still asked for | An `AbortSignal` per page, checked before the sign, before the PUT and before adding; §2.4 rewritten | `1c30d958` · `3ad93153` |
| **F4** (pipeline, MINOR) a canvas that is blanked or randomised uploads a blank picture | **Real mechanism**, OBSERVED by simulation on `106fb82d`: every canvas painted white before encoding → the photo uploaded, (255,255,255) at all five places, where the input reads (49,124,91)… **Which real browsers do it: UNVERIFIED** (only Chromium here) | A canvas check once per session (§2.4) and the « navigateur » sentence — **proposed copy, §11 item 10** | `1c30d958` · `3ad93153` |
| **F5** (pipeline, NIT) canvases never released; the queue keeps the last file | **Real** (code) | Canvases set to 0×0, the queue keeps no result, the fallback `<img>` drops its source. **No guard**: not observable from a test | `1c30d958` |
| **F6** (pipeline, NIT) an unknown file of any size handed to the decoder | **Real**: `106fb82d`'s own test « no header (GIF, BMP, AVIF…): decodes in full » asserted it | Unknown → `unreadable`, nothing measured or decoded | `1c30d958` |
| **F7** (pipeline, NIT) the engine check never resizes | **The literal claim is refuted**: an engine that applies the size before the rotation, simulated on `106fb82d` (the bitmap came back 2133×1600 when 1600×2133 was asked), still gave an upright 1600×2133 that matched the input within 1–2 levels at five places — the final draw into the target composes back to the right geometry (§5.3). **A neighbouring case is real**: an engine that drops the orientation when asked for a size — simulated on `106fb82d`, the photo came out sideways (top-left blue) | The check decodes a two-tone probe AT A SIZE and reads its pixels (§5.3) | `1c30d958` · `0e941eb8` |
| **F8** (pipeline, NIT) the output type not checked | **Real** (code) | Anything but `image/jpeg` → `failed` | `1c30d958` |
| **F9** (pipeline, NIT) every HEIC in Chrome an error-level event | **Real** (code: `level: 'error'`). Whether an alert rule would fire: **UNVERIFIED** (no Sentry access) | `prepare` → `warning` | `1c30d958` |
| **F10** (pipeline, NIT) two spec inaccuracies | **Real**: two surfaces list JPEG/PNG/WebP, not « three of four inputs »; Android's `rotationDegrees` drops the mirror (disassembled, §5.2 item 5) | §5.4 and §5.2 corrected | docs |
| Focus (UX, **MAJOR**) §2.7 says the focus stays; it goes to `<body>` | **Real.** Reproduced on `106fb82d`: the Médias photo input focused, the focus on `<body>` while busy and still there after | `useFocusBackAfter` on all four controls; §2.7 and WEB-SYSTEM §5 | `3ad93153` |
| Avant / Après shows nothing while busy (UX, MINOR) | **Real** (code: `FilePick` had no busy state) | « Téléversement… » on the side on its way, both pickers disabled | `3ad93153` |
| Catalogue's message below the fold at 320 px, doubled text (UX, MINOR) | **Real** by code (the shared alert after the hours block); the geometry is the review's (its screenshot), not re-measured | Its own alert under the photo button. Geometry after the fix: **UNVERIFIED** (INFERRED visible: it sits under the button) | `3ad93153` |
| The toast a tall narrow column (UX, MINOR) | **Real.** On `106fb82d` at 320 px the « trop grande » pill measured 160 px wide; with doubled text 182 px wide, y=88 to y=544 of 568 | Fixed by `dd5fcd6f` (full-width region in the gutter, the pill centred, `max-w-xl`), then **moved out by `a23eda47`**: open here, a follow-up after #737 → #741 → #750 (§2.7, §11 item 13) | `dd5fcd6f`, reverted by `a23eda47` |
| A repeated sentence not re-announced (UX, MINOR) | **Real** (the review: 0 changes in the region). A screen reader: **UNVERIFIED** | Fixed by `dd5fcd6f` (the pill keyed on each `show`), then **moved out by `a23eda47`**: open here, the same follow-up (§2.7, §11 item 13) | `dd5fcd6f`, reverted by `a23eda47` |
| Four guards green under their mutation, U2 U4 U7 U8 (UX, MINOR) | **Real** (the review's record) | New guards; the same four mutations now red (§13.5.3) | `3ad93153` |
| The e2e blind to a photo short of its frame, E3 (UX, MINOR) | **Real** (the review's record) | Every upload compared with its input at five places; E3 now red in four tests | `0e941eb8` |
| `pro-image-upload-pipeline.md:70` says multipart POST (UX, NIT) | **Real**: the app PUTs the raw bytes (`api_image_upload_service.dart`, `_client.put`) | Corrected | docs |
| The app's « Image invalide » not named (UX, NIT) | **Real** (`api_image_upload_service.dart:106`, `:109`) | §2.6 | docs |
| « préparée ici » assumes the person knows (UX, NIT) | A wording opinion on approved copy | **Not applied** — §11 item 11 | — |

#### 13.5.2 What ran (OBSERVED)

- `tsc --noEmit` exit 0; ESLint `--max-warnings=0` on the 24 touched web files, exit 0;
  `npm run gen:api` left `lib/api/schema.ts` unchanged. Each intermediate commit on its own
  (`git archive`): `tsc` exit 0 and the targeted unit files green (169, 186, 188 tests).
- Vitest, the full suite: **199 files, 2,682 tests, green**; the targeted ten files, 188.
- Playwright 1.61.1, its Chromium 149, an untracked config on 3100/8887 (both checked free; every
  host but 127.0.0.1/localhost unresolvable, on top of the specs' abort route), a fresh production
  build of the committed code: `pro-upload.spec.ts` 13, `pro.spec.ts` 41, `axe`, `discovery`,
  `tap-targets`, `type-overflow`, `focus` — **205 passed**. `booking.spec.ts` and
  `served-html.spec.ts` (hard-wired to 8787) and the rest of the suite: not run here.
- **The reproduction run**: `106fb82d`'s app with the new specs and two probes: the seven new tests
  red as above, the six original tests (now also comparing each upload with its input) green.
- **The five store-linked pages.** The walker: 56 files, the same list as `main` (sha
  `264b5f618d7fc60b`), none of the 24 changed files in it; `Toast.tsx`, `useToast.ts` and
  `upload-hooks.ts` outside; the control (Médias, Profil, Catalogue) is 84 files and reaches
  `compress.ts`. The Tailwind CLI output is byte-identical to `main`'s (sha `357e9a43…`); every
  class the fixes use already existed. **Production builds**: built back to back in one directory,
  `main` then the branch (`0e941eb8`): the nine entries' 17 script files byte-identical, the CSS
  byte-identical; the three Pro entries differ (the control). **Build noise, found on the way**: in
  an earlier session `main` and the branch differed on four of the nine entries — only the order of
  two chunk ids in a dependency list, a minifier's parameter name, and the Sentry debug id derived
  from them — and `main` rebuilt later from the same source differed from the first `main` on six
  entries in exactly that way. So one comparison across sessions proves nothing either way; the
  back-to-back pair is the evidence. The cause of that noise: **UNVERIFIED**.

#### 13.5.3 Guards watched red

Each mutation on a fresh `git archive 0e941eb8 web` (node_modules cloned; the worktree never
edited); every replacement checked to match exactly once and to change the file. Unit = the ten
targeted files (188 tests); e2e = `pro-upload.spec.ts` (13 tests) on a fresh production build of
the mutated copy. **33 runs: the control green (188 / 13), the 32 mutations each red.**

| Mutation | Unit | E2E | What fired |
|---|---|---|---|
| **Control — no edit** | **188 green** | **13 green** | — |
| F1 the target from our header reading, not the browser's (`prepare`) | 3 red | 1 red | « the browser's reading wins »; e2e « Exif 6 after the frame header » 2400×1600 instead of 1600×2400 |
| F1 the browser's default `measure` returns our reading | green | 1 red | the same e2e row |
| F1 every Exif segment read, the last wins | 1 red | — | « the first one decides » |
| F1 Orientation read whatever its type | 1 red | — | « a LONG, or two values, is ignored » |
| F1 PNG `eXIf` not read | 1 red | — | « eXIf BEFORE the image data » |
| F2 GIF / AVIF-HEIC / BMP size not read (three runs) | 1 / 3 / 1 red | 1 red each | the format's parser test; e2e « trop grande » never shown |
| F2 the ceiling not applied to the browser's size | 1 red | — | « a GIF frame larger than its screen » |
| F6 a file with no header goes on to the decoder | 2 red | — | « nothing is measured or decoded » |
| F4 the canvas check's answer ignored | 1 red | 1 red | « blocked »; e2e: no « navigateur » sentence, a signature |
| F4 the browser's canvas check always passes | green | 1 red | e2e « canvas comes back blank » |
| F4 `pixelsMatch` accepts any colour | 1 red | — | « a blank or random read-back: no match » |
| F7 the engine probe checks its shape only | green | 1 red | e2e: top-left (0,0,254), sideways |
| F8 a non-JPEG output goes out | 1 red | — | « not a JPEG: failed » |
| F9 `prepare` at level `error` | 1 red | — | « a warning; the other stages stay errors » |
| F3 no check after preparing (`upload.ts`) | 1 red | 1 red | e2e: a signature after leaving |
| F3 no check before the PUT | 1 red | 1 red | e2e: a PUT after leaving |
| F3 Médias adds after it was left | 1 red | — | « nothing is saved » (the helper's checks still stop the e2e case) |
| F3 leaving never aborts the signal | 3 red | 1 red | the three « left » unit tests; e2e |
| Focus never given back | 4 red | 1 red | the four surfaces' unit tests; e2e at its first surface |
| Avant / Après: no « Téléversement… » / pickers not disabled (two runs) | 1 red each | — | « while « Avant » is on its way » |
| Catalogue's photo message back in the form's alert | 4 red | — | « right under the photo button » |
| U7 Photos / U8 Catalogue: no busy state (two runs) | 3 / 1 red | — | the busy-state tests |
| U2 Avant / Après: unreadable shows the generic sentence | 1 red | — | the Avant / Après `unreadable` row |
| U4 Photos: the failure toast as `info` | 4 red | — | « as an error » (`bg-error`) |
| The toast centred by `left-1/2` again ² | 1 red | 1 red | the classes; e2e pill 160 px wide |
| The pill not keyed on each `show` ² | 1 red | — | « a NEW node in the region » |
| E3 the photo drawn to 85 % of the frame height | green | 4 red | bottom-left (255,255,255) against the input's (182,195,113) |
| « hidden » in a comment of `upload-hooks.ts` | 1 red | — | `upload-no-css` |

² True of `0e941eb8` only. `a23eda47` reverted the toast change these two mutations undid, and
removed the guards that caught them (the two `toast.test.tsx` tests and the e2e « at 320 px the
« trop grande » toast uses the width of the screen »): on the branch since, each mutation would be
`main`'s toast itself. The other 30 mutations edit none of the reverted files, and none of them had
a removed test as its only red, so they should still turn red (INFERRED from this table; not
re-run on `a23eda47`). The targeted unit set is now 186 tests, and `pro-upload.spec.ts` 12
(§13.7), then 13 (§13.8) — whose new test is green under the first of these two mutations by
design: it pins the half width that mutation puts back.

#### 13.5.4 Not verified

- Every browser but Chromium, and every real phone: whether a given browser alters its canvas
  output (F4), whether `<img>` and `createImageBitmap` agree on the orientation outside Chromium
  (§11 item 12), the Catalogue message at 320 px **with doubled text** after the fixes, a screen
  reader's announcement of a repeated sentence (the toast: §11 item 13).
- Whether `load` decodes nothing in Safari or Firefox (INFERRED from Chromium's times only).
- The cause of the build-to-build noise of §13.5.2.
- The full e2e suite (CI runs it). The stored photos' count (§11, answer 3) did not run in this
  build, which used no production or cloud access; it ran separately later that day.

### 13.6 Picture (2026-11-09)

One sheet, [a Pro photo on Médias, before and after](assets/web-pro-upload-resize.png) (1760×2351,
248 KB, 254 colours, no metadata chunk): `main` (62547f91) against this branch's code at `a23eda47`
— the commit that took the shared toast change out (§13.7) —, each a `next build` of a fresh
`git archive`, served side by side on 127.0.0.1 against one stub — this branch's, which signs only
JPEG, PNG and WebP as `upload_signing_service.dart` does and records what storage receives — in
Playwright's Chromium 149.0.7827.55 at 390×844. Every Node process ran with the lookup refusal of
§13.7 (its control run before each build, the servers and the shoot; the builds' only refused
names, `o1.ingest.sentry.io` ×6 each); the browser with the same three locks, plus the shoot's own
abort route: nothing was aborted and nothing reached the refusing proxy; popups were blocked, and
the Médias save was answered in the browser. Generated images only: the e2e's procedural photo
(`sidewaysPhoto` 4032×3024 with `exifApp1({ orientation: 6 })`, 1,866,380 bytes) and flat grey
placeholders for the seeded gallery. It replaces the sheet made at `efc779f0`, which showed
`dd5fcd6f`'s full-width toast (358 px wide there).

- **A phone photo added to « Photos ».** Before: storage received the picked file byte for byte —
  1,866,380 bytes, 4032×3024 stored (shown 3024×4032 through EXIF), Exif, the camera marker and the
  GPS IFD present, its own quality-92 table. After: 474,529 bytes (−74.6 %), 1600×2133 upright in
  its pixels, no Exif, camera or GPS, the IJG quality-80 table, APP0 and APP2 only. Read by the
  stub's `inspectJpeg`, then again by Pillow (sizes, Exif, camera make, GPS IFD, and the luminance
  table compared with the one Pillow's own encoder writes at quality 80 and 92 — all agree).
- **A file the browser cannot read** (4,096 bytes Chromium cannot decode, named `IMG_0043.heic`,
  `image/heic`). Before: one sign asked for `image/heic`, refused (400, `invalid_input`),
  « Échec de l’envoi », the focus on `<body>`. After: no sign, `UPLOAD_UNREADABLE_MESSAGE`, the focus
  back on « Ajouter une photo ». **The toast is `main`'s on both sides** (the same region and pill
  classes: `left-1/2 -translate-x-1/2`, no `inset-x-0`, no `max-w-xl`), so the 72-character
  sentence wraps in a pill **195 px wide — half the 390 px screen — and 96 px tall**, where
  « Échec de l’envoi » takes 153 × 36 px: §2.7's residual, seen at 390 px with normal text (§11
  item 13).
- Every figure on the sheet is read from the shoot's record and asserted before the sheet is drawn
  — among them that both toasts carry `main`'s classes and that the after pill is half the screen
  wide; a control gave the after toast `dd5fcd6f`'s classes in a copy of the record, and the sheet
  refused to draw. The PNG was opened and each figure checked against the record.

### 13.7 The split (2026-11-09): the shared toast change leaves this PR

Why: §11 item 13. `a23eda47` is `git revert dd5fcd6f` plus the removal of the one test that held
only with it — the e2e « at 320 px the « trop grande » toast uses the width of the screen, not half
of it », which required the pill to be wider than 250 px; its three other bounds held on `main`'s
toast too, and came back in §13.8. After it, `git diff origin/main` on
`web/components/Toast.tsx`, `web/lib/useToast.ts` and `web/tests/toast.test.tsx` is **empty**
(OBSERVED). Every other test that reads the toast stays: they find it by `role="status"` and its
text, or the pill as `[role=status] > div`, as `main`'s toast renders them.

What ran on a fresh `git archive a23eda47` (node_modules cloned; the worktree never edited),
OBSERVED:

- `tsc --noEmit` exit 0. ESLint `--max-warnings=0` on the commit's four files, and on the 20
  lintable web files of the 21 the branch touches (`_jpeg.d.mts` is not linted): exit 0, no
  problem.
- Vitest, the full suite (`TZ=UTC`): **199 files, 2,680 tests, green** (2,682 before, less the two
  toast tests); the targeted ten files of §13.5.3, 186.
- Playwright 1.61.1, its Chromium, an untracked config on 3100/8887 (both checked free), a fresh
  production build: `pro-upload.spec.ts` 12 and `pro.spec.ts` 41 — **53 passed**, none failed or
  flaky.
- **Nothing sent out.** Every Node process (the build, the stub, the Next server, the runner)
  loaded a lookup refusal for any name but loopback, with Next's telemetry off; before each run a
  control in the same environment — a lookup of `example.com`, a promise lookup, a `fetch` — had
  to fail, and did. Refused during the e2e: 6 lookups of `o1.ingest.sentry.io` by one process and
  5 of `cdn.stub` by another (INFERRED: the build's Sentry plugin, then the server's image
  optimizer). Chromium ran with every name but loopback unresolvable, every request not to
  127.0.0.1/localhost handed to a local proxy that drops it and logs it, and new windows blocked —
  its own control first (a local page loads; `example.com` and `example.org` fail and the proxy
  logs both; `window.open('http://example.net/')` opens nothing). Dropped during the run: 15 (14 to
  `cdn.stub`, 1 to `basemaps.cartocdn.com`). That nothing left the machine is INFERRED from those
  locks; no packet capture was made.

### 13.8 The gate and the review of `aa9b9814` (2026-11-09), and the fixes

The gate of `aa9b9814` — the branch after the split — passed every code check, the five
store-linked pages byte-identical to `main`'s, and failed on one docs defect; its review found no
BLOCKER and no MAJOR. **Each finding was checked before it was fixed**, against the open PRs' tips
after a `git fetch` that moved none, or by reading the files; every real one is fixed. Commits:
`85954e53` the e2e · the record commit (this section, rows 39 and 40 out of WEB-SYSTEM §15, and
the docs below). Nothing in `web/` changed but `pro-upload.spec.ts`; `Toast.tsx`, `useToast.ts`
and `toast.test.tsx` stay `main`'s.

| Finding | Real? — how it was checked | Done | Commit |
|---|---|---|---|
| **Gate, MAJOR:** the branch conflicts with #741 and #750 in WEB-SYSTEM §15 | **Real.** `git merge-tree --write-tree` of `aa9b9814` with `8e05eea5` and with `b79d0828`: exit 1, `CONFLICT (content)` in `docs/design/WEB-SYSTEM.md` — rows 39 and 40 sat on the lines right after row 38, which both rewrite (#741's install-banner note); clean with #737 and #738 | Rows 39 and 40 out of §15 (the first of the gate's two options); the two residuals stay recorded in §2.7 and §11 item 13, and the follow-up registers them on top of the train; §9.1 says what `merge-tree` shows, before and since | record |
| **Gate and review, MINOR:** the follow-up's condition names #737's « level with the toast » tests, which #741 replaced; #737's own design assumes the half-width toast | **Real.** « level with the toast » is on 2 lines of `site-look.spec.ts` at `83ce6ae9`, on none at `8e05eea5` or `b79d0828`, which hold « the favourite’s message and « Carte » (decision 100) »; replaced in `88a5c41d`, an ancestor of both. `web-swiss-cards.md` §2.4 (« The toast and « Carte » ») and mutation Y-E20, read at `83ce6ae9` | The condition rewritten wherever it is stated — the status row, §2.7, §11 item 13, the design index row, the roadmap entry: after the train, on their `Toast.tsx`, the decision-100 guards green, the owner's word on the width; #737's two tests kept as history | record |
| **Review, MINOR:** the split removed the whole 320 px e2e, though three of its bounds held on `main` | **Real** (`git show a23eda47`: only `toBeGreaterThan(250)` needed the full-width toast) | The test back in `pro-upload.spec.ts` — `toast.test.tsx` stays `main`'s: left edge ≥ 0, right edge ≤ 320, `scrollWidth` ≤ 320, and the residual pinned, the pill at most 161 px wide: the line the follow-up flips | `85954e53` |
| **Review, MINOR:** register row 40 cites a §7 rule that `9d721459` removed | **Real** at `aa9b9814`; moot once the row left | Row 40 out with row 39; the follow-up writes the rule with the row | record |
| **Review, MINOR:** the French summaries say more about the count than was measured | **Real.** The script read again: GPS only from the Exif GPS IFD, XMP and IPTC skipped; « test » and the providers' total carry labels in §11 answer 3 that the summaries dropped | The design index and the roadmap: « sans doute de test ou de démonstration », « aucune position GPS dans l’Exif (XMP et IPTC non lus) », the providers' total « selon le relevé, non revérifié »; §11 answer 3's « Not established » gains XMP and IPTC (the « sign » counts are lower bounds; this cell first called the Exif counts lower bounds too, corrected after the review of `d604b2d8`, below) | record |
| **Review, NIT:** the status row's present-tense « collides » | **Real**: `main`'s toast clears « Carte »'s word, `dd5fcd6f`'s did not | « its full-width version collided » | record |
| **Review, NIT:** §13.7 says 20 web files; the branch touches 21 | **Real**: `_jpeg.d.mts` is not linted, so 20 lintable | « the 20 lintable web files of the 21 » | record |
| **Review, NIT:** the count's record leaves out Secret Manager | **Real**: the script's `secret()` runs `gcloud secrets versions access` at the pinned versions; the 09:40 attempt's error reads `BILLING_DISABLED` on `secretmanager.googleapis.com` | §11 answer 3 says both | record |
| **Review, NIT:** §2.7's « nothing new overlays anything » beside a residual this PR makes bigger | **Real** (the text). Whether a control given the focus back sits under the pill at 320 px with doubled text: **UNVERIFIED** | Qualified in §2.7; the question stays UNVERIFIED | record |

**What ran on a fresh `git archive 85954e53`** (node_modules cloned; the worktree never edited),
OBSERVED:

- `tsc --noEmit` exit 0; ESLint `--max-warnings=0` on `pro-upload.spec.ts`, exit 0.
- Playwright 1.61.1, its Chromium, an untracked config on 3100/8887 (both checked free), a fresh
  production build: `pro-upload.spec.ts` 13 and `pro.spec.ts` 41 — **54 passed**, none failed or
  flaky. The new test's pill, read on a copy whose pin was set to fail so the box prints: **160 ×
  136 px at x=80, y=408**, `scrollWidth` 320.
- **Watched red**, each on its own fresh archive and build, `pro-upload.spec.ts` (13 tests):
  `whitespace-nowrap` on the pill → the new test red, the 12 others green: the pill 597.34 px wide
  at x=−138.67, off both edges, while `scrollWidth` stayed 320 — a fixed pill adds no scroll, so the
  edge bounds are the guard, not the scroll width; `dd5fcd6f`'s `Toast.tsx` and `useToast.ts` →
  the new test red, the 12 others green: the pill 288 px wide at x=16, inside the screen,
  `scrollWidth` 320, only the pin red (288 > 161) — the line the follow-up flips.
- The locks of §13.7, each with its control first: before every run a Node lookup of
  `example.com`, a promise lookup and a `fetch` failed; the browser guard's own check passed once
  (a local page loads, `example.com` and `example.org` fail and the sink logs both,
  `window.open` gives `null`). Refused during the control run: in Node 11 lookups (5 `cdn.stub`,
  6 `o1.ingest.sentry.io`), at the browser's sink 15 requests (14 `cdn.stub`, 1
  `basemaps.cartocdn.com`). That nothing left the machine is INFERRED from those locks; no packet
  capture was made.

**On this record commit, after it was made**, on a fresh `git archive` of it: `tsc` and ESLint on
the spec, the full Vitest (`TZ=UTC`, the register pin included), a fresh build with the two specs
on 3100/8887, the doc links against `main` with a planted-link control, the backend and mobile
infra tests with one control each, `git merge-tree` with the four open PRs' tips after a
`git fetch`, the paths of `git diff origin/main`, and the authorship of every commit. Their figures
go with the PR, since a record cannot carry its own run; §9.1's « clean with all four » is that
run's.

**Not verified:** the train's order (#737 → #741 → #750 → this branch) was not replayed — each
merge was read on its own; the #737 merge was not run again after the gate of `aa9b9814`; the new
test reads 320 px at normal text only, so doubled text at 320 stays the review's reading on
`106fb82d`; whether a control given the focus back sits under the pill there (§2.7); a screen
reader; Safari, Firefox and real phones.

**After the review of `d604b2d8`** (`f995946b` the e2e, then this docs commit): a pill pushed below
the screen (`-bottom-56` on the region) and one cut to a line
(`w-40 overflow-hidden whitespace-nowrap`) passed the 320 px e2e (OBSERVED on `d604b2d8`: the second
here, the first by the previous run), which now also holds the top and bottom edges against the
viewport the page reports (checked equal to the 320 × 568 it sets) and the pill's own scroll width
and height within its box, the pin kept; on a fresh archive and build of `f995946b` each,
`pro-upload.spec.ts` (13), OBSERVED: the commit 13 green (the pill 160 × 136 px at x=80, y=408, its
own 160 / 160 wide and 136 / 136 high, on a probe copy), `-bottom-56` red at the bottom edge
(y=656, 792 > 568), the cut line red at the pill's own width (597 > 160), `-top-56` red at the top
edge (y=−224), `h-9 overflow-hidden` red at its own height (86 > 36), the 12 others green each
time; and only the « sign » counts are lower bounds, the Exif counts exact for an APP1 `Exif`
segment before the frame header (the count script's `parse` read again) — corrected in §11
answer 3, the roadmap entry and the row above.

**After the review of `e50a5781`** (`b47517c4` the e2e, then this docs commit): the pill's own scroll
width and height count no overflow to the top or the left, so a sentence pushed up out of a short
`overflow-hidden` pill (`h-9 items-end`) passed: five of its six lines hidden, every assertion green
(OBSERVED by the review on `e50a5781`). The test now also holds the sentence's own rectangle (a
`Range` over the pill's contents) inside the pill's box on all four sides, half a pixel allowed for
rounding. On a fresh archive and build of `b47517c4` each, `pro-upload.spec.ts` (13), OBSERVED: the
commit 13 green; the short `items-end` pill red at the text's top (417 < 507.5; its own scroll height
36 / 36, so the old line still passed); a `w-40 justify-end whitespace-nowrap overflow-hidden` pill
red at the text's left (−333.3 < 79.5; its own scroll width 160 / 160); the 12 others green each
time; `tsc` and ESLint `--max-warnings=0` on the spec exit 0; Node refused 6 `o1.ingest.sentry.io`
lookups per build, the browser sink 0 requests. And §11 answer 3's « these two » now names the
« sign » counts.
