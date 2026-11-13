# Gallery — add several photos at once (website + Pro app)

| | |
|---|---|
| **Status** | Approved 2026-11-13 (owner: « Yes, build it » — §9 answered with the recommendations) · Built on `feat/gallery-multi-select` |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-13 |
| **PRD ref / phase** | Pro gallery (pro-gallery.md) · V1 |
| **ROADMAP entry** | `docs/roadmap/entries/2026-11-13-gallery-multi-select.md` (with the build) |
| **Skills checked** | myweli-web-guardrails · myweli-dev-guardrails · myweli-backend-guardrails (no backend change) |

Owner's ask (2026-11-13): « when selecting pictures we can select more at once,
so we don't have to upload one by one ». Builds on
[upload-resave-stale-pending.md](upload-resave-stale-pending.md): several adds in
a row is exactly the sequence that was refused before #784, and every add below
keeps the addresses the server stored.

## 1. Goal & scope

**Goal:** fill a salon gallery in one go — pick 5 or 10 photos, let them go up,
done — on the website's « Médias » and in the Pro app's « Photos ».

**In scope:** the **gallery** only, on both surfaces (parity: the website follows
the app's flow — memory `web-mirror-app-flow`).

**Out of scope, on purpose:**
- **Before/after:** a pair is one « avant » and one « après », picked by two
  separate buttons; several at once has no meaning there.
- **Logo, artist photo, KYC documents:** one image each, by nature.
- **The camera (app):** takes one photo per shot, as today.
- **Drag-and-drop onto the gallery on desktop:** a natural next step on the
  website, not asked for; §9.

No backend change: the gallery save already takes the whole list (max 20,
`_maxGalleryPhotos`), and each save promotes only the new photo.

## 2. UX & flow

### 2.1 Website — « Médias » › « Photos »

1. The button reads **« Ajouter des photos »** (was « Ajouter une photo »). The
   file picker now allows **several files** (`<input multiple>`); on a phone this
   opens the photo library with multi-select.
2. The pro picks N photos. If N is more than the room left (20 − current), the
   **first ones in the order picked** are kept up to 20, and a toast says how
   many were left out (§2.4).
3. The photos go up **one after another**, never in parallel: each is prepared
   in the browser (resize to the app's JPEG, web-pro-upload-resize.md), sent,
   then **saved at once**, exactly as a single add is today. Why one at a time:
   preparing means decoding a 12 MP image on a canvas; several at once on a
   2–3 GB Android phone is how a tab gets killed.
4. While it works, the button reads **« Téléversement 2 sur 5… »** and is
   disabled; each photo **appears in the grid as soon as it is saved** — progress
   you can see, and nothing to lose if the page is left.
5. At the end, one toast sums it up (§2.4).

Everything else on the page stays usable between photos, as during a single
upload today (move, cover, delete): each save re-sends the list the server last
returned, so a move in between is kept. In the app the add tile stays visible
and waits (disabled), between two photos of a pick too.

### 2.2 Pro app — « Photos »

1. The add tile opens the same sheet, titled **« Ajouter des photos »**:
   « Appareil photo » (one photo, as today) or « Galerie » (**several**, the
   system multi-select, limited to the room left).
2. Same sequence: one after another, each saved as it lands and shown at once.
3. The uploading tile reads **« Envoi 2 sur 5… 40 % »** during a batch of more
   than one; a single photo keeps **« Envoi… 40 % »**.
4. Same summary at the end (§2.4), as a snackbar.

The sheet is shared with « Avant / Après », which keeps its one-photo sheet and
title unchanged.

### 2.3 States & edge cases

| Case | What happens |
|---|---|
| One photo picked | Exactly as today — no new copy, no success toast. |
| Gallery already full (20) | Web unchanged: « Maximum atteint. ». **App: the add tile now goes at 20** — before, it stayed, and a 21st photo was refused by the server only after its upload (found while building). |
| More picked than room | First ones kept; « 20 photos maximum : 3 photos n’ont pas été ajoutées. » |
| One photo fails (unreadable, too large, network) | It is skipped, the others continue; counted in the summary. |
| A save is refused | That photo is not added; the batch continues with the list the server last accepted. |
| Page left / app screen left mid-batch | Website: the photo being prepared is dropped (the existing leave signal). App: the photo on its way finishes, as a single add always has. Either way the rest are not sent and the ones already saved stay. A salon switch in the app stops it the same way. |
| Upload ceiling (60 gallery signatures / hour / account) | Three full galleries' worth; a refusal counts as a failed photo. No special copy. |
| Picker cancelled | Nothing happens. |

### 2.4 Copy (French)

| When | Message | Kind |
|---|---|---|
| Batch ≥ 2, all added | « 5 photos ajoutées. » | success |
| Batch ≥ 2, some failed | « 3 photos ajoutées sur 5. 2 n’ont pas pu être envoyées. » (« 1 n’a pas pu être envoyée. ») | error |
| Batch ≥ 2, all failed | « Aucune photo n’a pu être envoyée. » + on the website, the specific hint when every failure shares one (« Choisissez des images JPEG, PNG ou WebP. » / « … plus petites. » / « Essayez avec un autre navigateur. »). The app has no typed reasons, so no hint. | error |
| More picked than room | « 20 photos maximum : 3 photos n’ont pas été ajoutées. » — on the website at once, and repeated at the end of the summary (one toast at a time, so the first may be replaced); in the app, in the end snackbar | info |
| Batch of 1 | Today's messages, unchanged | — |

## 3. API & contract

None. `PUT /providers/{id}/gallery` per photo, as today.

## 4. Data model

None.

## 5. Architecture

- **Website:** `PhotosTab` takes a `FileList`, caps it with a pure helper
  (`lib/pro/medias.ts`: room left, kept / dropped), and runs the existing
  `uploadGalleryImage` → `onAdd` per file in a loop, stopping on the leave
  signal. The summary text comes from a pure, unit-tested function.
- **Pro app:** `showImagePicker(context, multiple: true)` returns a list
  (`pickMultiImage(limit: room)` for « Galerie », `pickImage` for the camera);
  `ProGalleryProvider.addPhotos(providerId, sources)` runs the existing
  `addPhoto` path per source, exposes `uploadIndex` / `uploadTotal` for the
  tile, and returns the counts for the snackbar. Demo mode keeps its one-sample
  sheet.

## 6. Security

No new surface. Each photo is still signed, size-verified and promoted by the
server one by one (T61), under the per-identity signing ceiling (T65).

## 7. Performance

One photo in memory at a time (the low-end Android budget, ROADMAP Part 6). N
saves for N photos — each re-sends ≤ 20 URLs and promotes one object, the same
cost as N single adds today.

## 8. Tests — red first, then mutations

- **Website (Vitest):** 3 files → 3 uploads in the order picked, never two at
  once, 3 saves each carrying the previous photos' **stored** addresses (the
  strict server of `pro-stored-urls.test.tsx`), « 3 photos ajoutées »; 18 + 4
  picked → 2 sent and the « 20 photos maximum » toast; a failure in the middle
  → the rest continue, « 2 photos ajoutées sur 3… »; leaving mid-batch → no
  further sign; the input has `multiple`; one file → no new toast. Pure helpers
  for the cap and the summary.
- **e2e:** `pro.spec.ts` « médias » picks two files in one go.
- **Pro app:** `ProGalleryProvider.addPhotos` — sequential, each saved and the
  stored list adopted, counts, cap, screen left mid-batch; a widget test for
  « Envoi 2 sur 3… »; the before/after sheet unchanged.
- **Mutations:** parallel instead of sequential, cap off by one, summary
  counts, leave signal ignored, `multiple` removed.

### 8.1 What was measured (2026-11-13)

- **Red first:** the website's nine behaviour tests failed on the old page
  (one file at a time, no `multiple`); the app tests failed to compile before
  `gallery_batch.dart` existed.
- **Mutations — website 14/14 killed:** uploads in parallel, no cap, cap off
  by one, the LAST ones kept instead of the first, no over-cap notice, the
  leave signal ignored, stop at the first failure, a refused save counted as
  added, `multiple` removed, no progress label, a summary for one photo, the
  hint when the reasons differ, no cap note in the summary, a single failure
  silent.
- **App 13/13 killed — two only after a change.** A5 (the salon check removed)
  survived because the salon reset ALSO set the stop flag: the reset no longer
  does, so each guard has one job and its own test. A6 (not busy between two
  photos) survived because nothing listened between photos: the test now
  records `isUploading` on every change of a batch. A1 (in parallel) was first
  killed by a compile error only; rewritten to compile, it is killed by the
  test.

## 9. Rollout & decisions

Answered by the owner with the recommendations: **save after each photo**;
over the room left, **keep the first ones picked**; desktop drag-and-drop
**later**.

Website ships on merge; the app with the next store build; no backend deploy.

The questions as they were asked, kept for the record:

1. **Save after each photo (recommended) or once at the end?** After each:
   photos appear as they land, a left page loses nothing, and a failure costs
   one photo. Once at the end: one save instead of N, but nothing shows until
   the end, and leaving mid-way loses the whole batch.
2. **Over the room left:** keep the first ones picked (recommended), or refuse
   the whole selection?
3. **Desktop drag-and-drop** of several files onto the gallery — want it in
   this slice, or later?
