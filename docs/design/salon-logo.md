# Salon logo — settable at last

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-08-27 |
| **Module** | pro salon profile (`mobile/`, `web/`, `backend/`) |
| **PRD ref / phase** | FR-PRO-ONB (salon identity) · V1 |
| **Related** | [consumer-avatar-upload.md](consumer-avatar-upload.md) (the template) · [pro-image-upload-pipeline.md](pro-image-upload-pipeline.md) · [pro-gallery.md](pro-gallery.md) · [pro-salon-lifecycle.md](pro-salon-lifecycle.md) §2 (the parked gap) · BACKEND.md **T61** |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-web-guardrails |

## 1. Goal & scope

`logoUrl` has been **displayed but never settable** since the audit parked it
([pro-salon-lifecycle.md](pro-salon-lifecycle.md) §"open", ROADMAP L1
leftover): the consumer salon header renders it (72×72 `_SalonLogo`), the
« Mes salons » thumbnail prefers it server-side — and no surface anywhere can
write it. This closes that.

**In scope:** a `logo` upload purpose; a promotion-guarded `logoUrl` write on
`PATCH /providers/{id}`; the Pro app's profile-editor affordance; the web pro
profile uploader; v1 renders (mobile salon-picker rows, web Hero overlay, web
JSON-LD `LocalBusiness.logo`, web ProSidebar thumbs).

**Out of scope, with reasons:** an image cropper (the render is `ClipOval` +
`cover`, which center-crops acceptably; a cropper is a new dependency and its
own slice) · a publish-gate `logo` entry (contract change to the `missing`
enum; a salon without a logo is publishable) · dashboard-header and
consumer-card renders (deferred; nothing here forecloses them) · admin logo
moderation.

## 2. UX & flows

**Mobile (Pro):** a centered `_LogoField` at the top of « Profil du salon » —
`CircleAvatar` (radius 44 ⇒ 88 dp ≥ the 48 dp floor) showing the logo or a
store glyph, a camera badge, upload progress in place, and « Supprimer le
logo » when set. Picking a photo **uploads and saves immediately** (the
avatar pattern); the rest of the form stays staged — no conflict, because the
logo PATCH carries only `logoUrl`. Errors: « Échec de l'envoi. Réessayez. »
inline under the field, never a toast. Copy: « Ajouter un logo » / « Changer
le logo » / « Supprimer le logo ».

**Web (Pro):** an uploader block in the Profil form (the artist-photo staged
pattern): pick → upload → preview; `logoUrl` rides the existing
« Enregistrer ». Remove button clears it.

**States:** loading (progress ring on the field) · empty (glyph + « Ajouter
un logo ») · error (inline message, field keeps its previous value) ·
success (the image, immediately).

## 3. API & contract

- **`POST /uploads/sign` gains `purpose=logo`**: provider role,
  **`Cap.profileManage`** in the acting salon (see §6), `StorageBucket.public`,
  key `pending/logo/{providerId}/{random}.{ext}`, image content types, 5 MB
  advisory, `publicUrl` in the ticket. Salon-scoped via `?salonId=` (R6).
- **`PATCH /providers/{id}` accepts `logoUrl`** with promotion semantics:
  a fresh URL must be one this deployment issued (origin check) and is
  promoted out of `pending/`; re-sending the stored value is a no-op
  (`alreadyStored` membership); **`''` clears to null** (the `/me` `phone`
  semantics — no separate DELETE verb).
- OpenAPI deltas: sign `purpose` enum + description; `UploadTicket.publicUrl`
  public-purpose list; PATCH body property. `npm run gen:api` (CI pins drift).
- No new endpoints. Read contract already complete (ProviderSummary +
  Provider both carry `logoUrl`).

## 4. Data model

None. `logoUrl` lives in the provider jsonb document already (seeds carry it
as `null`); `updateProfile` merges. **No migration.**

## 5. Architecture — the two decisions

**A dedicated `logo` purpose, not `gallery` reuse** — the purpose string IS
the storage namespace (`upload_signing_service.dart` §"purpose"): a logo
filed under `gallery/{providerId}/` would be indistinguishable from a
portfolio photo to every future gallery sweep. Same argument, verbatim, as
the avatar's §3.

**The claim is a promotion-guarded branch inside `updateProfile`, not a
dedicated route.** The flat-allowlist purity argument fails on its own
precedent: `areaId` is already a specially-validated sibling beside the
allowlist. A dedicated `PUT .../logo` would force the web's staged save into
two requests and cost a route + path + BFF + service method for nothing.

## 6. Security & authz

- **One capability for sign AND save: `Cap.profileManage`.** The save gate
  already is; web hides the editor on it. Using `catalogueManage` at sign
  time (the gallery's choice) would let a catalogue-only member sign uploads
  they can never claim — a guaranteed-orphan generator.
- **The naive allowlist add is a hole** (an arbitrary string PATCHed into
  `logoUrl` — the hole `/me` closed for avatars): the write validates
  non-string/length ≤ 2048/origin, then `promoteNewUrls([url],
  alreadyStored: {current logoUrl}, bucket: public)`. Both named failure
  modes from `upload_verification_service.dart` apply and are tested:
  never-promote (daily `pending/` expiry orphans the URL) and
  promote-everything (second save 400s).
- Rate limit: **explicit `signLogo` arm, 10/h** + `LIMIT_SIGN_LOGO` env —
  the `signLimitFor` switch's default arm silently inherits the avatar
  ceiling, the exact silent-trap its own comments warn about.
- **T61 delta:** `updateProfile` becomes the **eighth** claim surface — the
  BACKEND.md row updated in this PR.
- Declared residual (gallery parity): public logo objects are not erased on
  provider account deletion.

## 7. Performance

Nothing new: mobile compresses to ≤1600 px JPEG q80 before upload (existing
pipeline); web sends the raw file (native type); rendering reuses
`TimedCachedImage` / `next/image` with the R2 origin already allowlisted.

## 8. Testing plan

Backend (`upload_signing_test` avatar-group mirror): logo → public bucket +
`pending/logo/{providerId}/` + `publicUrl`; salonId selects among ACTIVE
memberships, forged → forbidden; member **without `profile.manage`** →
forbidden; provider 200 / consumer 403 at the route.
(`provider_catalog_test` gallery-write-once mirror): first save promotes out
of `pending/`; re-sending the stored URL does not 400; a never-issued URL is
refused; foreign origin refused; `''` → null; cross-tenant 403.
Wiring: `LIMIT_SIGN_LOGO` plumbing + a `signLimitFor('logo')` pin with
`signLogo != signAvatar` in the fixture.
Mobile: sign carries `purpose=logo` **and** `?salonId=`; the DI slot
instance-identity test (`isA<>` proves nothing under mocks); provider
`uploadLogo`/`removeLogo`; the profile form renders the field and the
untouched-form lockout test stays green; picker-sheet renders `imageUrl` with
the initial-letter fallback.
Web: `buildProfilePayload` carries `logoUrl` (and `''` on clear);
`uploadLogoImage` signs/PUTs/returns; BFF accepts `logo`, refuses junk;
JSON-LD `logo` present iff set.
**Ten mutations watched red** (committed-first), each on one named test —
including the naive-allowlist hole and the rate-limit default-arm
fall-through. **Goldens: none change** (seeds keep `logoUrl: null` — held).

## 9. Rollout

Mock mode free (`MockProService.updateSalonProfile` merges arbitrary changes;
the model round-trips `logoUrl`). Backend reaches prod via the usual
staging-rehearsal → promote (owner's word). **Owner follow-up:** upload a
real logo to the demo salon, then re-capture the snapshot
(`POST /admin/demo/snapshot`) — otherwise the 7-day reset reverts it.

## 10. Definition of done

- [ ] All gates green on all three surfaces; mutations red; contract
      regenerated with no drift.
- [ ] T61 row, `pro-salon-lifecycle.md` parked note, and the design index
      updated in this PR.
- [ ] Spec status flipped to Built; cross-linked from the signing service,
      the catalog branch, and the two editor surfaces.

## 11. Open questions

- Cropper (deferred — revisit if owners upload obviously off-center logos).
- Consumer-card / dashboard-header renders (deferred, nothing foreclosed).
