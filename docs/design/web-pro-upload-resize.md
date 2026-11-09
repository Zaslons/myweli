# Web Pro uploads — shrink each photo as the app does, before it is sent (decision 107)

| | |
|---|---|
| **Status** | **Built 2026-11-09** on `feat/web-pro-upload-resize` (from `main` 62547f91), **not merged** — approved the same day (the owner's four answers, §11, decision 107). The record is §13. |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-09 |
| **Module** | pro salon profile / portfolio — the web Pro area (`/pro/medias`, `/pro/catalogue`, `/pro/profil`) |
| **PRD ref / phase** | FR-PRO-MEDIA-001 (« client-side compression ») · NFR-DATA-001 (« Mobile-data thrift: compress uploads ») · PRD §« Expensive, intermittent data » · V1 |
| **ROADMAP entry** | [2026-11-09-web-pro-upload-resize.md](../roadmap/entries/2026-11-09-web-pro-upload-resize.md) |
| **BACKLOG** | Decision 107 lives in `docs/BACKLOG.md` on #741's branch (decisions 87–107 are on open branches); its « built » line is added there, not here. |
| **Governs** | `web/lib/image/compress.ts` (new) · `web/lib/pro/upload.ts` · `web/lib/upload-telemetry.ts` · `web/components/pro/MediasClient.tsx` · `web/components/pro/CatalogueClient.tsx` · `web/components/pro/ProfilClient.tsx` · their tests · `web/tests/e2e/pro-upload.spec.ts` · `web/tests/e2e/_jpeg.mjs` · `web/tests/e2e/stub-api.mjs` |
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

- No new control, no new focus stop. WCAG 2.4.11: nothing new overlays anything.
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
  **The same sentence twice is read twice** since the review: `useToast` gives every `show` an id
  and `Toast` keys the pill on it, so a repeat is a new node in the region (two unreadable files
  picked within 6 s re-rendered the same text in place — 0 changes in the region, OBSERVED by the
  review; INFERRED silent for a screen reader, none was run).
- The busy state: `aria-busy` + disabled on the `Button`; Médias' inputs `disabled` while
  uploading, « Avant » / « Après » included since the review.
- 200 % text: the three sentences (72, 85 and 83 characters) wrap inside their `<p>` and the toast
  pill. **The toast used to have half the screen to wrap in** — centred by `left-1/2
  -translate-x-1/2`, it measured 182 px wide and 456 px tall at 320 px with Android-style doubled
  text (OBSERVED by the review). It now spans the screen inside the side gutter (`inset-x-0 px-m`,
  the pill centred and capped at `max-w-xl`; every class already existed, so the shared stylesheet
  is unchanged); at 320 px with normal text the « trop grande » pill is wider than 250 px (pinned,
  §13.5). Doubled text at 320 px after the fix: **UNVERIFIED** (no screenshot taken).
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
every surface, the error kind, the busy states, the focus, the alert's place, the toast's repeat;
and in Chromium the odd EXIF layouts, an engine that drops the orientation when it scales, GIF /
BMP / AVIF over 64 MP, leaving Médias mid-upload, a blanked canvas, the focus on four surfaces, the
toast at 320 px, and a comparison of every upload with its input place by place.

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
rollback. #741 and #737 also edit `pro.spec.ts` and `stub-api.mjs`, in hunks far from the upload
code; a clean merge is expected (INFERRED until both exist).

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
`uploads/sign` or `compress` in either), so neither changes.

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
   stored photos are test/demo uploads only. The count was attempted on 2026-11-09 around 09:40 UTC
   and could not run: Secret Manager refused because the GCP billing account behind project
   `myweli` is closed (the production API has answered 503 since some time after 2026-11-08
   12:27 UTC). (Reported to this build; not re-checked by it — no production access was used.)
   **The count runs once billing is restored.** Since no real salon exists, **nothing stored needs
   re-encoding before launch**; a purge or re-encode of the test data, if wanted, is a separate
   owner decision. This spec prevents new full-size, metadata-carrying web uploads; it does nothing
   to what is already stored (verification-guardrails §8).
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
13. **The toast change is site-wide.** The two toast findings (half-width wrapping, a repeated
    sentence not re-read) were fixed in the shared `Toast` / `useToast`, which also serve the
    consumer pages (favourites, search, account) — every class already existed, the shared
    stylesheet is byte-identical, and the five store-linked pages do not import either file
    (§13.5). It is its own commit, so it can leave this PR if the owner prefers it separate.

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
uploads exist or carry GPS; the app's black-logo behaviour.

## 13. Record (2026-11-09)

### 13.1 Commits

On `feat/web-pro-upload-resize`, from `origin/main` 62547f91: `0f3f3467` the spec (docs first) ·
`5c30f9b9` the code and tests · this record. Nothing pushed.

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
  ran in a real engine: its matrices are unit-tested against EXIF's definition only. The `<img>`
  path did run, in Chromium, with `createImageBitmap` removed.
- The two sentences at 200 % text on a 320 px screen (no screenshot taken).
- The full e2e suite (CI runs it); the CWV budget (no public page changed).
- The stored photos' count (§11, answer 3): not run — it waits for GCP billing (reported closed on
  2026-11-09, not re-checked here); this build used no production or cloud access.
