# Upload re-saves — a save must never re-send a `pending/` address the server already moved

| | |
|---|---|
| **Status** | Draft — awaiting the owner's sign-off |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-13 |
| **PRD ref / phase** | Storage / uploads (T61) · V1 · production incident of 2026-11-13 |
| **ROADMAP entry** | `docs/roadmap/entries/2026-11-13-upload-resave-stale-pending.md` (added with the build) |
| **Skills checked** | myweli-backend-guardrails · myweli-web-guardrails · myweli-dev-guardrails (the KYC line in the Pro app) |

Builds on [backend-upload-orphans.md](backend-upload-orphans.md) (the `pending/`
prefix, promotion) and [backend-upload-claim-hardening.md](backend-upload-claim-hardening.md)
(`promoteNewUrls` / `promoteNewKeys`, the "a save is not a claim" rule).

## 0. The incident, and why it is not R2

On 2026-11-13, after the B0.18 deploy, the owner added photos to a test salon on
the website's « Médias » page and some were refused: `PUT /providers/{id}/gallery`
answered **400 `upload_not_found` after ~2.4 s**. The first reading was R2
read-after-write lag — `objectSize` retries a 404 four times, 500 ms apart, and
its own comment records R2 once answering 404 for a just-written object.

**That reading is wrong for this incident.** The production request log
(`myweli-api`, salon `provider_1794572092706186`, read-only) shows a strict
pattern, not a random one:

| UTC | Gallery PUT | Latency | What it was |
|---|---|---|---|
| 12:18:17 | — | | Médias loaded (`GET /me/provider`) |
| 12:18:30.9 | 200 | 0.80 s | add photo 1 — promoted |
| 12:18:37.7 · 47.3 · 56.4 | 400 ×3 | 2.4–2.7 s | each later add refused |
| 12:19:01.3 | 200 | **0.08 s** | a save with **no storage work** (a removal) |
| 12:19:10.1 | 200 | 0.57 s | add — promoted |
| 12:19:16.8 | 400 | 2.44 s | the next add refused |
| 12:19:23.9 | — | | Médias reloaded |
| 12:19:29.3 | 200 | 0.57 s | add — promoted |
| 12:19:33.3 | 200 | **0.09 s** | a removal |
| 12:19:39.6 | 200 | 0.56 s | add — promoted |
| 12:19:44 → 12:29:39 | 400 ×6 | 2.4–2.5 s | every later add refused, no reload in between |

**Every refusal follows a successful add in the same page visit, and the run
only ends at a reload or at a save that removed a photo.** A real add costs
HEAD + copy + delete (≈0.56 s); the two 0.08–0.09 s successes did no storage
work at all, so they carried no new upload.

**The mechanism, read in the code and reproduced in a test:**

1. The page uploads photo A to `pending/gallery/{salon}/a.jpg` and saves
   `[...stored, pendingA]`.
2. The server promotes A — copies it to `gallery/{salon}/a.jpg`, **deletes the
   pending object** — stores the promoted address and returns
   `{ imageUrls: [...] }`.
3. `MediasClient.writePhotos` **ignores that body** and records its own list,
   still holding `pendingA`, as "what the server last accepted".
4. The next add sends `[...stored, pendingA, pendingB]`. `pendingA` is not in the
   stored set (the server stored the promoted address) but is a valid pending
   key, so it goes to `verify()` → HEAD → **404, five times, because it was
   deleted in step 2** → `upload_not_found` after 2.4 s. `pendingB` is never
   looked at, which is why the refused objects are still sitting under
   `pending/` and answer 200 to a HEAD minutes later.

So the 2.4 s is the retry loop exhausting itself on an object that will never
come back, not R2 being slow. Cloudflare documents R2 as strongly consistent
for read-after-write ([consistency model](https://developers.cloudflare.com/r2/reference/consistency/)).
The live test's occasional just-written 404 (backend-upload-orphans.md §6.2)
is still unexplained, but it did not cause this, and lengthening the window
would only have made each refusal slower.

Also visible to the owner: after step 2 the thumbnail on the page points at the
deleted pending object, so it breaks on the next re-render.

## 1. Goal & scope

**Goal:** a save never fails, and a thumbnail never breaks, because a client
re-sent the `pending/` address of a photo the server has already moved.

**Who else has this flaw** (every re-save surface, traced on all three clients):

| Surface | Website | Pro app (released) | Consumer app |
|---|---|---|---|
| Gallery | **broken** (this incident) | correct — adopts the response | — |
| Before/after pairs | **broken** (same code) | correct | — |
| KYC documents | **broken** — keeps pending keys after a submit; a 2nd submit in the same visit is refused | **broken** — same (`ProKycProvider.submit`) | — |
| Artist photo | correct — reloads after save | correct | — |
| Salon logo | (no web upload) | correct | — |
| Review photos | correct — form closes | — | correct |
| Avatar | (no web upload) | — | correct |

**In scope — three parts:**

- **A. Server: a re-sent pending address is the photo already stored.** In
  `promoteNewKeys` / `promoteNewUrls`, a pending key whose promoted form is
  **already in `alreadyStored`** passes through as that stored value — no HEAD,
  no copy, no delete. Because every re-save surface goes through these two
  functions, this one change covers all of them, **including the Pro app builds
  already installed**, and it also makes a retry after a lost response succeed
  (today that retry is refused for the same reason). The claim form
  (`verifyAndPromote`, i.e. deposits and bookings) passes an empty
  `alreadyStored` and is therefore unchanged.
- **B. Clients adopt what the server stored.** Website: Médias (gallery,
  before/after) and Vérification (KYC) replace their local list with the
  server's response after every successful write — the way the Pro app already
  does for the gallery. Pro app: `ProKycProvider.submit` refills its documents
  from the response, as `load()` does. A covers the old builds; B makes the
  clients correct on their own and fixes the broken thumbnail.
- **C. A storage fake that forgets.** `FakeStorageService.deleteObject` keeps
  the key "present" today, which is why no test could see this: re-sending a
  deleted pending key still stat'ed fine. It will report a deleted key as
  absent, as R2 does.

**Out of scope:**

- The `objectSize` 404 retry window — unchanged; it was not the cause (§0).
- **Undo after a delete is refused in production** — see §11.1. Found while
  tracing this; it needs its own security decision.
- Promoted objects of photos removed from a gallery are never deleted (§11.2).

## 2. UX & flows

No new screens or copy. What changes for the salon:

- Website Médias: adding a second, third… photo in the same visit no longer
  fails with « Échec de l’envoi », and a just-added thumbnail no longer breaks.
  Remove, reorder and « Mettre en couverture » after an add work too: they were
  refused in the same way.
- Website Vérification and Pro app KYC: submitting again in the same visit (for
  example after replacing one document) no longer fails.
- Undo (« Annuler ») after a delete stays broken until §11.1.

## 3. API & contract

No change to any shape or status code. The behaviour sentence on the seven
re-save operations in `docs/api/openapi.yaml` (gallery, before/after, artist,
logo, review, `PATCH /me`, `POST /me/kyc`) gains one clause: *a `pending/`
address whose promoted form is already stored for this resource is accepted as
that stored address* — re-sending is idempotent.

## 4. Data model

None.

## 5. Architecture

- **Backend:** `UploadVerificationService` only (`promoteNewKeys`,
  `promoteNewUrls`), plus `FakeStorageService.deleteObject`. No route or
  repository change.
- **Website:** `lib/api/pro.ts` — `saveGallery` / `saveBeforeAfters` return the
  stored list from the body; `MediasClient` and `VerificationClient` adopt it. A
  200 without a usable list re-reads the page rather than keeping local
  addresses: keeping them is the bug.
- **Pro app:** `ProKycProvider.submit` refills `_documents` from
  `res.data!.documents`.

## 6. Security & authz

- **What is returned is unchanged as a set**: every stored address is either a
  member of `alreadyStored` or an upload verified and promoted by this request.
  The new branch only ever returns a member of `alreadyStored`. Membership is
  checked on the **promoted** form, never on the shape of the address.
- **Tenant scoping comes from `alreadyStored`**, which each surface already
  scopes (this salon's gallery, this account's KYC documents, this artist's
  photo…). The pending form of **another** salon's stored photo is not in the
  set, so it takes the normal path and is refused if the object is gone —
  pinned by a negative test.
- **Claims unchanged:** `verifyAndPromote` passes an empty set, so deposits and
  bookings still require a live pending object.
- **Threat model:** no new endpoint or trust boundary; the T61 row gains one
  sentence recording the idempotent re-send and that it is membership-checked.

## 7. Performance

A re-sent pending address now costs nothing (no HEAD, copy or delete), so the
2.4 s refusal disappears instead of being moved. Nothing gets longer, so the
budgets of the Vercel BFF, the Cloudflare Worker front door and the clients are
untouched.

## 8. Testing plan — red first, then mutations

- **Backend** (`upload_verification_test.dart`, `upload_promotion_test.dart`):
  - the website's exact sequence on the gallery and on before/after: add A,
    then save `[pendingA, pendingB]` → 200, A kept as stored, B promoted, no
    HEAD/copy for A;
  - KYC re-submit with the pending keys of the first submit → 200;
  - negative: the pending form of another salon's photo is **not** passed
    through; the claim form still refuses a deleted pending key;
  - every existing test re-run against the forgetting fake, and any that
    depended on a deleted key still "existing" fixed or explained.
- **Website** (Vitest + RTL): the mocked BFF answers like the real one
  (promoted list in the body). Two adds in a row → the second PUT carries the
  first photo's **promoted** address and the thumbnail shows it; the same for
  before/after; Vérification submitted twice → the second POST carries the
  promoted keys; a 200 without a list re-reads.
- **Pro app:** `ProKycProvider` — after `submit`, `documents` are the server's,
  and a second submit sends them.
- **Mutation pass:** remove the server pass-through; check membership by shape
  instead of on the stored set; remove each client adoption. Every one must
  turn a test red.

## 9. Rollout

1. PR → CI green → owner merges.
2. **Backend deploy — only on the owner's explicit yes.** This alone stops the
   refusals for the website and for every installed Pro app.
3. Website: ships with the merge (Vercel) — fixes the thumbnail and makes the
   page correct on its own.
4. Pro app KYC line: next store build.
5. **Orphans:** the refused uploads (8 by 12:21, 10 by 12:29) sit under
   `pending/gallery/provider_1794572092706186/` and expire through
   `expire-unclaimed-uploads` — **read back live on 2026-11-13**
   (`myweli-uploads`: enabled, prefix `pending/`, 1 day). Nothing to clean by hand.

## 10. Definition of done

- [ ] backend: format · `dart analyze --fatal-infos --fatal-warnings` = 0 · tests green
- [ ] web: typecheck · lint · Vitest · `next build`
- [ ] mobile: `flutter analyze` = 0 · KYC provider tests green
- [ ] each new test watched red; mutation pass recorded in the PR
- [ ] contract sentence + T61 row + roadmap entry in the same PR
- [ ] feature branch + PR; CI green; deploy handed to the owner

## 11. Open questions

1. **Undo after a delete is refused in production — website and Pro app,
   gallery and before/after.** Undo re-sends the removed photo's *promoted*
   address. After the delete it is no longer stored and it is not pending, so
   the membership rule refuses it (`invalid_input`) — reproduced against the
   real service code. Neither client can work around it: the bytes are no
   longer on the device. Three ways out, each a rule change:
   - (a) remember the addresses a save removed for a short window and count
     them as stored — membership kept, needs a small migration;
   - (b) accept an existing object under the salon's own final prefix — shape
     plus existence, which these docs have so far refused on purpose;
   - (c) delete only once the undo window has passed — both clients, an app
     release, and the website must follow the app's flow.

   **Recommendation:** its own spec and PR right after this one, leaning (a).
   Not folded in here: it changes the trust rule this fix deliberately leaves
   alone.
2. A photo removed from a gallery leaves its promoted object in the bucket
   forever (outside `pending/`, so no rule collects it). This incident most
   likely left two: the 12:19:01 and 12:19:33 saves could only succeed by
   dropping the photo just added, whose promoted copy stays behind. Whatever
   §11.1 decides determines when such objects can be deleted.
