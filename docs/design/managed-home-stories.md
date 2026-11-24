# Managed home stories — design spec

| | |
|---|---|
| **Status** | **Approved (2026-11-23).** The owner answered all eleven questions of §14 « Approve as recommended »: decisions 171–181. Nothing is built yet: the build comes after Track A (Q9, decision 179), each PR and each deploy on the owner's word (§12). |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-23 |
| **PRD ref / phase** | FR-DISC-010 (« *partial: `stories/` consumer-side exists for system stories* »; salon stories V2) · FR-WEB-AD-004 (content moderation, « reviews, photos, stories », V1) · FR-WEB-AD-005 (featured placement, V1, its closest kin) · FR-PRO-STORY-001 (salon-posted stories, **V2**, option B only) · BACKLOG B0.10, decision 170 |
| **Module** | `online-booking` (the client home, [MODULES.md](../MODULES.md) §2) with the admin console. Salon-posted stories belong to `marketing` (§6, V2). |
| **ROADMAP entry** | [2026-11-23-managed-home-stories-spec.md](../roadmap/entries/2026-11-23-managed-home-stories-spec.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-web-guardrails · myweli-verification-guardrails |
| **Read at** | `main` `d0a31d63`, and A1's code branch `feat/consumer-app-truth` (#834) at `ce9570f1`. Every « today » below names its file and line. |
| **Reviewed** | once by an independent read-only reviewer told to refute it (2026-11-23): 22 findings, each checked against the code and folded in |
| **Related** | [consumer-app-truth.md](consumer-app-truth.md) §2.1 (A1, #833: the flag, decision 170) · [consumer-app-release-audit.md](consumer-app-release-audit.md) (#832) · [admin-console.md](admin-console.md) §12 (featured) · [admin-console-ui.md](admin-console-ui.md) · [admin-remote-images.md](admin-remote-images.md) §1 (R2 CORS) · [backend-upload-orphans.md](backend-upload-orphans.md) · [backend-upload-size-verification.md](backend-upload-size-verification.md) · [web-pro-upload-resize.md](web-pro-upload-resize.md) · [mobile-a8-motion.md](mobile-a8-motion.md) (the 6 s dwell) · [SYSTEM.md](SYSTEM.md) §9.1, §12, §13, §19, §21 rows 25 and 62 |

**How to read it.** *Observed* means read in the code, in a document, or on a
public page on 2026-11-23. *UNVERIFIED* means not, and says who or what can
check it. Nothing in a cloud console was read or changed for this spec.

---

## 0. Three things this spec found that change the brief

1. **The admin console is Flutter Web, not Next.js.** It is
   `mobile/lib/main_admin.dart`, built by `deploy-admin.yml`
   (`flutter build web --target lib/main_admin.dart`, `deploy-admin.yml:80-85`)
   and served from Cloudflare Pages at `admin.myweli.com`, behind Cloudflare
   Access. `docs/WEB.md` says it outright: « admin stays Flutter Web ». So the
   staff screens of §6 are Dart, in `mobile/lib/screens/admin/`, beside the
   KYC queue and « Version minimale ». `web/` has no admin page.
2. **The console cannot upload to R2 yet.** A browser upload is a presigned
   `PUT` from the page's origin straight to R2, so the bucket must answer that
   origin's CORS preflight. On 2026-11-12 the public bucket `myweli-uploads`
   refused a **GET** preflight from `https://admin.myweli.com` (403, no CORS
   header) and accepted both GET and PUT from `https://myweli.com`; a PUT
   preflight from `admin.myweli.com` was **not** probed
   ([admin-remote-images.md](admin-remote-images.md) §1.1, observed then, not
   re-probed here). The manifest lists only `https://myweli.com` for that
   bucket (`infra/cloudflare/r2-manifest.json:30`). So step 3 of the rollout
   (§12) is a cloud change on the owner's word: allow `PUT` with the
   `content-type` header from `https://admin.myweli.com` on the public bucket.
3. **A1 is not on `main`.** `FeatureFlags.homeStories`, its guard in
   `test/unit/feature_flags_test.dart`, and « the home stories fit » pumped
   alone in `test/a11y/layout_test.dart` exist on `feat/consumer-app-truth`
   (#834), stacked on #833 and #832, none merged. This spec cites them there.
   Its app PR (§12, PR D) starts from a `main` that holds A1. *(Since
   2026-11-23 12:18 UTC it does: #834 merged as `f891a301`.)*

---

## 1. Goal & scope

**Goal.** The client home's « stories » row comes back, filled by people who
can vouch for what it says, instead of three hard-coded pictures. Decision 170,
in the owner's words: « don't remove stories, put it under a flag, or make it
that someone manage them ». A1 did the first half (the flag). This spec is the
second.

**What « managed » means here:** a story exists because a named person at
MyWeli published it, from the console, with an end date, after writing down
how they know it is true. The server stops serving it when it ends, when a
salon it names stops being public, or within 60 seconds of being withdrawn.

### 1.1 In scope

| Part | What | Section |
|---|---|---|
| Backend | the `home_stories` table, a public read, admin routes, a `story` upload purpose, the contract, threat T85 | §4 |
| App (client) | `AnnouncementStories` and `StoryViewer` read the API through an interface with a mock; the demo list and its three SVGs deleted; then the flag flips | §5 |
| Console | « Stories » for staff: list, editor with preview, publish, withdraw, reorder | §6 |
| Web | the same stories on `myweli.com`'s home (Q3, decision 173) | §7 |

### 1.2 Out of scope, and where each goes

- **Salons publishing stories** (option B, §1.3): V2, FR-PRO-STORY-001, the
  `marketing` module. The data model leaves room for it (§4.2), nothing more.
- **Promotions with a price or a discount**: not in this version (§3.2, Q2).
  When promo codes exist (FR-BOOK-013, V2) the booking can carry the offer the
  story makes; until then a story would promise a price the booking flow does
  not show.
- **Paid placement** (PRD §5, add-ons V2+): no story is paid for. A paid one
  would be an advertisement and need a « Sponsorisé » label (§3.4).
- **Counting views or taps**: not in this version (§9, Q5).
- **Push notifications about a story**: no.
- **MyWeli Pro**: nothing changes.
- **Per-country targeting**: the communes of §2.3 belong to one city. A second
  market adds a country field then.

### 1.3 Who publishes: two options

| | **A. MyWeli staff, from the console** | **B. Salons, from MyWeli Pro** |
|---|---|---|
| PRD phase | Fits V1: FR-WEB-AD-004 lists stories under content moderation, and the « system stories » surface exists (FR-DISC-010's note) | **V2** (PRD §7.2 « Pro: provider-posted stories », FR-PRO-STORY-001) |
| Who vouches | the publishing admin, in writing (§3.3) | the salon; MyWeli must still moderate before or after |
| Store rules | not user-generated content | **user-generated content**: App Store 1.2 requires a filter for objectionable material, a way to report, a way to block abusive users, and published contact details; Play's UGC policy requires terms accepted before posting, in-app reporting and blocking, and ongoing moderation (both read 2026-11-23) |
| Surfaces to build | backend + console + app (+ web) | backend + Pro app (iOS, Android) + web Pro + a console moderation queue + report and block in the client app and on the web |
| Who could post today | the owner | nobody: no salon is public in production (decision 51's gate, [consumer-app-release-audit.md](consumer-app-release-audit.md)) |
| Risk to the truth rule | one publisher, one rule | every salon a publisher; a false « -30 % » is a few taps away |

**Decided: A now; B stays V2** (Q1, decision 171). A is the smaller build, carries no UGC
obligations, and has a publisher today. Two choices in A keep B open without
building it: a `publisher` column (`myweli` only, for now) and the storage
prefix `story/myweli/` (§4.4), so salon stories can later live under
`story/{salonId}/` beside them. **Q1: A, decision 171.**

### 1.4 How it fits the architecture

- **Backend:** `routes → services → repositories → DTOs`
  ([BACKEND.md](../BACKEND.md) §1). A `HomeStoryService` in `lib/src/admin/`
  holds every rule of §2–§3 (that folder is one the audit-label test scans,
  §6.7); routes stay thin; a `HomeStoryRepository` interface with an in-memory
  twin and a Postgres impl.
- **App:** `models → services (interface + mock + api) → providers →
  widgets`. A `HomeStoryServiceInterface` with `MockHomeStoryService` and
  `ApiHomeStoryService`, wired in `dependency_injection.dart` on
  `AppConfig.useApiBackend`, the way `LocalityServiceInterface` is
  (`services/interfaces/locality_service_interface.dart`).
- **Shared drawing:** the card's face and the viewer's page become
  presentational widgets that take their image as a widget (§5.3), so the app
  feeds them `TimedCachedImage` and the console feeds them local bytes or
  `AdminRemoteImage`, without the console importing `TimedCachedImage` (§6.5).
- **Console:** `AdminService` methods (`services/admin/admin_service.dart`), an
  `AdminStoriesProvider`, screens on `AdminScaffold` and `AdminDataTable`
  (`screens/admin/widgets/`).
- **Web:** the generated typed client on the server, a Next route handler for
  the browser (§7.2).

---

## 2. What a story is

### 2.1 Its fields

| Field | Rule | Who sees it |
|---|---|---|
| `id` | uuid, server-made | all |
| `kind` | `announcement` (news from MyWeli: a new commune, a new feature) or `salon` (puts one public salon forward). No `promotion` kind (§3.2) | all |
| `salonId` | **required** for a `salon` story: the salon it is about. Not allowed on an `announcement` | all (with `salonSlug`) |
| `title` | required; 2 to **20** characters after trim; no line break; no word longer than the card can hold on one line (§2.6) | all |
| `body` | optional; at most **140** characters; plain text, no line break, no link | all |
| `image` | required to publish; portrait 9:16; a full image (at most 1080×1920, at most **500 KB**) and a thumbnail (300 px wide, at most **60 KB**), both prepared by the console (§6.4); no words drawn in it (§3.2) | all (as public URLs) |
| `imageAlt` | required to publish; 5 to 150 characters; what the image shows, for a screen reader | all |
| `cta` | optional: a `label` (2 to 20 characters) and a `target` (§2.2). Without it, the viewer shows no button | all |
| `startsAt` | required to publish; defaults to the moment of publishing; at most **30 days** ahead of the moment of publishing | all |
| `endsAt` | **required** to publish; after `startsAt` and after now; at most **30 days** after `startsAt` (§3.5, Q6) | all |
| `areaIds` | the communes it targets (§2.3); empty means every commune; at most 20; each must be an area of the locality tree (`GET /localities`) | all, as commune names |
| order | the staff's order (§2.4); sent as the order of the list, never as a number | all, as the list's order |
| `sourceNote` | required to publish; 10 to 300 characters: **how we know this is true** (§3.3) | **console only** |
| `publisher` | `myweli` (the only value now; room for B) | console only |
| `createdBy`, `publishedBy`, `withdrawnBy`, their times, `withdrawReason`, `imagesDeletedAt` | server-set | console only |

### 2.2 Where its button goes: a closed list

A story never carries a free URL. Its target is one of two shapes, and each
client builds its own link:

| `target.type` | Fields | App route | Web link |
|---|---|---|---|
| `salon` | `salonId` (+ `salonSlug`, server-filled) | `/provider/{id}` (`app_router.dart:55`) | `/{slug}` |
| `search` | `category` (optional) | `/providers?category={key}` (`app_router.dart:47-52`) | `/recherche?category={key}` |

- **A `salon` story's button**, when it has one, goes to its own salon; it
  takes no other target. **An `announcement`** may point at any public salon,
  at a search, or nowhere.
- **Why closed:** a stolen admin session must not be able to send every
  client to a phishing page (T85, §8), and an external link would leave the
  app with no warning.
- **The category key.** `GET /providers?category=` filters on any string
  (`providers_repository.dart:229-231`, `postgres_providers_repository.dart:39-41`),
  so it holds no list to validate against. The one closed set is what a salon
  may *be*, checked when a salon saves its category
  (`provider_catalog_service.dart:422`: `salon`, `barber`, `spa`, `nails`,
  `massage`); `providers.category` can hold nothing else, so a story's key is
  checked against that set, one constant shared by both checks. *Observed
  drift, not this spec's to fix:* the web asks for `nail`
  (`web/lib/landing.ts:17`) and the contract lists `nailSalon`
  (`openapi.yaml:1208`). A4 (search and the Ivorian categories) settles the
  set; this check follows the constant.

### 2.3 Which communes see it

- `areaIds` hold area ids from the locality tree, which do not change when a
  name is respelled. The public read sends the **names** beside them, because
  the app stores its commune as a name (`provider_provider.dart:120`,
  `selectedCommune`). It is the same name equality the commune filter on
  `/providers` already relies on (`SalonMarket.providerChanges`,
  `localities_service.dart`: `commune` is the area's name).
- **A client who has chosen a commune** sees the stories targeting it, plus
  those targeting every commune.
- **A client who has chosen none** (the pill reads « Toutes les communes »,
  `commune_pill.dart:18`) sees only the stories targeting every commune.
  **Q4, decision 174.** The other reading, « show them all », would put a Cocody salon in
  front of someone in Abobo.
- **An area that leaves the tree** never widens a story: a story with an
  `areaId` the tree no longer holds is not served (« Masquée — commune
  inconnue » in the console), rather than falling back to « every commune ».
- **The filtering happens on the device**, never on the server (§9): the
  request carries no commune.

### 2.4 The order

- **The server sends the list in the staff's order.** Each published story
  has a `position`; a newly published one goes **last** (`max + 1`). Staff
  reorder with « Monter » / « Descendre » (§6.2).
- **Reordering is a compare-and-set on the whole order:** the console sends
  the order it read and the order it wants (`PUT /admin/stories/order
  {expected, ids}`, §4.3). If the stories published and not ended or withdrawn
  are not exactly `expected`, in that order, the answer is `409 order_stale`
  and nothing moves. Two tabs reordering at once: one wins, the other reloads.
- **The app keeps today's rule: unseen first,** then seen
  (`announcement_stories.dart:74-84`), and within each group the order the
  server sent. *Today's sort is not stable:* `List.sort` in Dart makes no
  stability promise, so equal keys may swap. The key becomes the pair (seen,
  index in the response).
- **The web keeps the server's order** and does not move seen cards to the
  end (§7.1): a re-sort after the page is drawn would move cards.

### 2.5 Its life, derived from its columns

The first line that applies wins:

| # | State (console) | When | Clients see it? |
|---|---|---|---|
| 1 | **Retirée** | withdrawn by staff | no |
| 2 | **Brouillon** | never published | no |
| 3 | **Terminée** | `now ≥ endsAt` | no |
| 4 | **Programmée** | `now < startsAt` (with an amber warning when it would be « Masquée » if it started now) | no |
| 5 | **Masquée** | a salon it names (its `salonId` or its button's) is `draft`, `suspended` or gone, or one of its `areaIds` left the tree | no |
| 6 | **En ligne** | everything else | **yes** |

- **A published story does not change.** Its words, image, button, dates and
  communes are what someone vouched for, and what the audit log says clients
  saw. To change one, staff press « Dupliquer » (a new draft holding the same
  fields and **copies** of its images, §4.4), fix it, publish it, and withdraw
  the old one. Only its order moves after publishing.
- **The seen state follows the id,** so a corrected story shows as new. That
  is right: it says something new.
- **At most 8** stories may be published, not ended and not withdrawn at once
  (states 4, 5 and 6 together). The ninth publish is refused
  (`409 too_many_stories`). Eight cards already overflow a phone's width
  twice; more is a wall, not a row. Two publishes at the same moment cannot
  both pass the count: publishing takes one transaction-wide lock first
  (§4.3).

### 2.6 The title on the card

- At 1× the card's text box is 64 dp wide and holds two lines of
  `labelSmall` (`_cardWidth`, `_titleBlock`, `announcement_stories.dart`). The
  demo titles were 13 to 15 characters; twenty is the most two such lines
  hold, measured in PR D against the SDK's Roboto as A13 measured row 62.
- **A word must fit one line,** or §13.3's « no break inside a control's
  label » fails. A13 measured that the box holds « Week‑End » (8 glyphs) at
  1×. PR D measures the longest token the box holds and sets one constant;
  the server refuses a longer word (`400 title_word_too_long`), the console
  shows the limit, and the gate pins it.
- **If « Treichville » (11 letters, the longest commune name) does not fit,**
  PR D widens the card for every story rather than forbid a commune in a
  title, and re-makes the goldens. A title must be able to name a commune.
- A title the two lines cannot hold ends in « … »; the accessible label
  carries it whole, and the truncation is **declared** to the layout gate.

---

## 3. Moderation and the truth rule

### 3.1 The rule

> **Everything a story says is true when it is published and stays true until
> it ends. Someone at MyWeli has checked it, and wrote down how.**

It is the rule A1 applied to the app's own sentences, applied to content that
arrives from the server.

### 3.2 What a story may not say

- **No price, discount or free offer** (Q2). Apple 2.3.1 calls marketing that
  promotes « content or services » the app does not offer, « or a false
  price, inside or outside the App Store », grounds for removal. Play's
  Deceptive Behavior policy, §1 « Misleading Claims », does not allow false or
  misleading information or claims (both read 2026-11-23). A « -15 % » the
  booking then charges in full is that, and the booking flow has no way to
  carry a discount until promo codes exist (FR-BOOK-013, V2).
- **No words drawn into the image.** The demo SVGs drew their claims inside
  the picture (« -15% sur une sélection de salons »,
  `assets/images/stories/promo_weekend.svg`). Words in a picture escape every
  check below, cannot be read by a screen reader, and do not grow at 200 %.
  A story's words live in `title` and `body`, where the app draws them as
  text.
- **No availability claim the app does not show.** « Dernière minute »
  promised free slots; only the booking flow knows them.
- **No person who has not agreed.** A recognisable face needs that person's
  written consent (§9).

**The server's backstop.** Publishing is refused (`422 story_claims_price`)
when `title` or `body` holds a price or discount token: a digit followed by
`%`, `FCFA`, `F CFA` or `XOF`, or one of « gratuit », « offert », « offerte »,
« réduction », « remise », « promo », « solde », case- and accent-folded.
**Its blind spot, written in the code beside it:** a claim worded without
those tokens (« moitié prix »), and any text in the image. The attestation
(§3.3) is the control; the list only catches the obvious slip.

### 3.3 Who vouches

- **The admin who publishes.** Publishing needs two things the server checks
  (`422 source_required`, `422 attestation_required`):
  - `sourceNote`: how we know, e.g. « Salon validé par MyWeli le 20/11 ;
    horaires confirmés par téléphone avec la gérante le 23/11 »;
  - `attest: true`, the box « Je confirme que cette story est vraie
    aujourd'hui et le restera jusqu'à sa date de fin, et que MyWeli a le droit
    d'utiliser cette image ».
- **Both are kept:** `sourceNote` on the row (never in a public response),
  and the audit row `story.publish` names the admin and records the
  attestation.
- **One admin role** today ([admin-console.md](admin-console.md) §10, decision
  3): no second person reviews. Sub-roles (« modérateur ») are a later slice;
  when they exist, publishing can need a second admin. Not built here.

### 3.4 Kinds of truth, kind by kind

| Kind | What must be true | How the server helps |
|---|---|---|
| `announcement` | the news itself (« MyWeli arrive à Yopougon » means salons in Yopougon are bookable) | dates and the price backstop; a salon its button names must be public, at publish and at every read |
| `salon` | the salon is real, public, and what the story says of it holds (« Nouveau sur MyWeli » means it went live recently) | the salon must be public **at publish** (`422 salon_not_public`) **and at every read**: the story stops being served the moment the salon is suspended, unpublished or purged (§2.5), by the one visibility rule, `isPublicSalon` (`salon_visibility.dart`) |

- **Paid placement** is out of scope (§1.2). If it ever comes, the story
  carries a visible « Sponsorisé »; Apple's guideline on display advertising
  and Play's Ads policy then apply (*UNVERIFIED wording: read only in summary
  for this spec; that spec re-reads them*).

### 3.5 Expiry, withdrawal, and what happens to what already exists

- **No story lives more than 30 days** (Q6): `endsAt` is at most 30 days
  after `startsAt`, and `startsAt` at most 30 days after the moment of
  publishing, so no attestation covers more than 60 days from the day it was
  given. A sentence true when written is not true forever; the cap makes
  someone look again.
- **The server stops serving** a story at `endsAt`, at withdrawal, and when a
  salon it names stops being public, on its own clock. A response may be
  cached up to 60 s (§4.6).
- **A phone or a browser already showing it** drops it at its next read
  (§5.2: the home's first frame, pull-to-refresh, coming back to the
  foreground, the home shown again, the viewer opened on an old list; §7.2 for
  the web). Between reads, the app also hides any story past `endsAt` by its
  own clock. That clock is a second filter, never the first: a phone whose
  clock runs ahead hides a live story early; one whose clock runs behind
  still loses an ended story at its next read.
- **So « Retirer » is not instant everywhere.** It is the kill switch the
  product has, faster than any deploy or build, and the console says what it
  does: « Elle n'est plus servie dans la minute. Un téléphone ou un onglet
  déjà ouvert la retire à sa prochaine actualisation. » (§6.6). A
  compile-time flag is not a kill switch: it reaches clients only with a
  build.
- **Texts are kept; images are not, for long.** An ended or withdrawn story
  keeps its row: the record of what clients were shown. Its two images stay
  public at their URLs (unlisted, but reachable by anyone who kept the link)
  until they are deleted:
  - **at once**, when staff tick « Supprimer aussi l'image » while
    withdrawing, or press « Supprimer les images » on an ended or withdrawn
    story (an offensive image, consent withdrawn);
  - **otherwise 90 days after the end** (Q11), by a new task on the existing
    maintenance cron.
  The row then says when and by whom (`imagesDeletedAt`).
- **A draft never published** is deleted with its images.
- **The demo stories** (« -15 % », « Beauté Divine », « Dernière minute »)
  never reach a client: they are deleted from the tree in PR D, before the
  flag flips (§5.6).

### 3.6 The stores' review

- **App Review sees what is live** on the day. Apple 2.3.1 also asks that a
  new feature be described in the Notes for Review (read 2026-11-23). The
  consumer store packet (B3) says, in English: stories are published by
  MyWeli staff only, never by users, with an end date, and may be absent.
- **Play's Behavior Transparency** (Deceptive Behavior §5) forbids hidden or
  dormant features. A row that shows only when staff publish is content, not
  a feature switched on remotely; the listing (B3) may mention « actualités
  de MyWeli » rather than promise a row that can be empty. B3 decides the
  words.

---

## 4. The backend

### 4.1 The public read

**`GET /stories`** — public, no token, no query parameter.

```json
{
  "items": [
    {
      "id": "6f1c…",
      "kind": "salon",
      "salon": { "id": "…", "slug": "awa-coiffure-cocody" },
      "title": "Nouveau sur MyWeli",
      "body": "Le salon Awa Coiffure, à Cocody, prend ses rendez-vous en ligne.",
      "imageUrl": "https://cdn.myweli.com/story/myweli/Qm9….jpg",
      "thumbUrl": "https://cdn.myweli.com/story/myweli/Xk3….jpg",
      "imageAlt": "Une coiffeuse tresse les cheveux d'une cliente dans un salon lumineux.",
      "cta": {
        "label": "Voir le salon",
        "target": { "type": "salon", "salonId": "…", "salonSlug": "awa-coiffure-cocody" }
      },
      "communes": [ { "areaId": "…", "name": "Cocody" } ],
      "startsAt": "2026-12-01T08:00:00Z",
      "endsAt": "2026-12-15T23:59:00Z"
    }
  ]
}
```

- **What it returns:** the stories « En ligne » (§2.5), at most 8, in the
  staff's order. `salon` is absent on an `announcement`; `cta` is absent
  without a button.
- **Not paginated, and why that is allowed:** BACKEND.md §2 asks list
  endpoints for `{items, page, pageSize, total}` and §4 forbids an unbounded
  list. This list is bounded by construction, the publish cap of §2.5, the way
  `GET /localities` is a bounded tree; the server still applies `LIMIT 8`.
- **The public-field allowlist:** the DTO is built field by field, never from
  the row. `sourceNote`, `publisher`, `position`, every `*By`,
  `withdrawReason` and `imagesDeletedAt` never leave the server here. A
  contract test fails if a new column appears in the response.
- **Salon checks without N+1:** the candidate rows (published, in their
  window, not withdrawn: at most 8 by the cap) are read in one query, the
  salons they name in one batch read, and each story is kept only if
  `isPublicSalon` holds for every salon it names and every `areaId` resolves.
- **Errors:** `405` on another verb; a database failure is a `500` with the
  standard envelope. There is no `404`: no stories is `{"items": []}`.

### 4.2 The table

Migration **`0047_home_stories`** (the next id after `0046_salon_purge`,
`migrations.dart:1248`; renumbered at build if another lands first).
Additive: an older image never reads it.

```sql
CREATE TABLE IF NOT EXISTS home_stories (
  id                 text PRIMARY KEY,
  publisher          text NOT NULL DEFAULT 'myweli'
                     CHECK (publisher IN ('myweli')),
  kind               text NOT NULL CHECK (kind IN ('announcement', 'salon')),
  salon_id           text REFERENCES providers(id) ON DELETE SET NULL,
  title              text NOT NULL,
  body               text,
  image_key          text,
  thumb_key          text,
  image_alt          text,
  cta_label          text,
  target_type        text CHECK (target_type IN ('salon', 'search')),
  target_salon_id    text REFERENCES providers(id) ON DELETE SET NULL,
  target_category    text,
  area_ids           text[] NOT NULL DEFAULT '{}',
  starts_at          timestamptz,
  ends_at            timestamptz,
  position           int,
  source_note        text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  created_by         text NOT NULL,
  updated_at         timestamptz NOT NULL DEFAULT now(),
  published_at       timestamptz,
  published_by       text,
  withdrawn_at       timestamptz,
  withdrawn_by       text,
  withdraw_reason    text,
  images_deleted_at  timestamptz,
  images_deleted_by  text
);
CREATE INDEX IF NOT EXISTS home_stories_live_idx
  ON home_stories (ends_at)
  WHERE published_at IS NOT NULL AND withdrawn_at IS NULL;
```

- **Times are UTC.** Côte d'Ivoire is UTC+0 all year, so the console's
  « heure d'Abidjan » equals UTC today. The console still converts with the
  `Africa/Abidjan` zone rather than assuming it, so a second market needs no
  rewrite.
- **Both salon references are `ON DELETE SET NULL`,** not `CASCADE` and not
  `RESTRICT`:
  - the salon purge (T84, B0.24) deletes salon rows, and must not be refused;
  - the story's row is the record of what was shown, and must outlive it;
  - a story whose salon is gone is « Masquée » and never served (§2.5).
  PR B adds a story pointing at the salon to the purge's Postgres test, so the
  purge is watched succeeding with it.
- **The CHECKs hold the closed values only** (`kind`, `target_type`,
  `publisher`). « A `salon` story has a salon » is the service's rule at
  write, not a CHECK: a CHECK would refuse the purge's `SET NULL` (23514).
  The read treats the null as « Masquée ».
- **`position`** is null on a draft and set at publish (`max + 1`, §2.4).
- **`publisher`** has one value. Option B would add `salon` and a
  `publisher_salon_id`; nothing reads it now.

### 4.3 The admin routes

All under `/admin/*`: the existing gate refuses no token with `401` and any
non-admin token with `403` (`routes/admin/_middleware.dart`, T17). Each
mutation writes **one** `audit_log` row: actor, action, `target_type = 'story'`,
the id, and for publish the attestation.

**Errors** use the standard envelope plus the field they belong to:
`{"error": "<code>", "field": "<field>"}`.
- `400` for what is wrong with the input itself, at save **and** at publish:
  lengths, types, unknown values (`title_too_long`, `category_unknown`, …).
- `422` for what only publishing requires: an image, the attestation, dates
  in the future, a public salon, the price backstop.
- `400 invalid_body` for unreadable JSON. BACKEND.md §2's readers
  (`lib/src/http/body_fields.dart`) read strings and lists today; PR B adds
  the boolean (`attest`) and object (`cta`) readers it needs.

| Route | Does | Notable answers |
|---|---|---|
| `GET /admin/stories?state=&page=&pageSize=` | the list, by state (§2.5). `draft`, `ended` and `withdrawn` are paginated in SQL (`{items, page, pageSize, total}`, `pageSize` clamped to 50). `live` returns states 4, 5 and 6 together, at most 8 by the cap, with each one's state computed in Dart by `isPublicSalon`, so the rule is never copied into SQL | `400 invalid_input` on an unknown state |
| `POST /admin/stories` | creates a draft; `kind` and `title` required, the rest optional; images as pending keys (§4.4). Wrapped in `idempotent()` (BACKEND.md §3.7), the console sending an `Idempotency-Key` | `400` per field · audited `story.create` |
| `GET /admin/stories/{id}` | the whole story, console fields included | `404 not_found` |
| `PATCH /admin/stories/{id}` | edits a **draft** | `409 story_published` on a published one · audited `story.update` (the changed field names, never their values) |
| `POST /admin/stories/{id}/publish` `{attest: true}` | in one transaction: `pg_advisory_xact_lock` on one fixed key (the in-memory twin, a mutex), the count of §2.5, every check of §4.5, then `UPDATE … SET published_at = now(), position = max + 1 WHERE id = @id AND published_at IS NULL` | `422` with the first failing code · `409 too_many_stories` · `409 story_published` when already published (a second click: the console reloads and shows it published) · audited `story.publish` |
| `POST /admin/stories/{id}/withdraw` `{reason?, deleteImages?}` | stops serving a published story; with `deleteImages`, deletes its two objects too | `409 not_published` · an already withdrawn one answers `200` and writes nothing · audited `story.withdraw` (+ `story.images_delete`) |
| `POST /admin/stories/{id}/images/delete` | deletes the two objects of an ended or withdrawn story | `409 story_live` on a story still served or scheduled · audited `story.images_delete` |
| `POST /admin/stories/{id}/duplicate` | a new draft with the same fields and **copies** of the images under new keys (§4.4). Wrapped in `idempotent()` | audited `story.duplicate` |
| `PUT /admin/stories/order` `{expected, ids}` | a compare-and-set on the whole order (§2.4) | `409 order_stale` when the stories published, not ended and not withdrawn are not exactly `expected`, in that order · audited `story.reorder` |
| `DELETE /admin/stories/{id}` | deletes a draft never published, and its images | `409 story_published` otherwise · audited `story.delete` |

### 4.4 The images: `/uploads/sign` with a new purpose

**Today** (`upload_signing_service.dart`, `routes/uploads/sign.dart`): six
purposes. The key is built on the server, `pending/{purpose}/{prefixId}/{random}.{ext}`,
so a client never chooses a path. The route picks the role a purpose needs:
`deposit`, `review` and `avatar` need a client token, everything else a
provider token (`sign.dart:36-42`).

**After:**
- **Purpose `story`**, which needs an **admin** token. The route's role choice
  becomes a closed map, purpose → role (`story` → `admin`), so an admin token
  asking for `gallery`, or a salon or client token asking for `story`, is a
  `403` like today's cross-role refusals.
- **The key:** `pending/story/myweli/{random}.{ext}` in the **public** bucket.
  `myweli` is the publisher, not the admin: a story outlives the person who
  published it, and the purpose is the namespace erasure and sweeps reason
  about (the header comment of `upload_signing_service.dart`). Option B would
  use `story/{salonId}/`.
- **Types:** JPEG, PNG, WebP (`_imageTypes`); the console always sends JPEG
  (§6.4).
- **Rate limit:** its own `signStory` ceiling in `IdentityLimits` and its own
  arm in `signLimitFor` (`identity_limits.dart:263-274`), never the default
  arm (the comment there says why).
- **The claim** is the draft's create or patch carrying `imageKey` and
  `thumbKey`. In this order:
  1. **The prefix.** A new key must start with `pending/story/myweli/`; an
     unchanged one must be this row's own current key. Anything else is
     `400 invalid_input`. Without it, an admin request naming
     `pending/gallery/{salonId}/x.jpg` would be promoted to
     `gallery/{salonId}/…`, a salon's namespace that the purge deletes. Every
     claim path re-checks its own prefix the same way (T16; the deposit
     service, `deposit_service.dart:132`).
  2. **The sizes:** `verify([imageKey])` with a **500 KB** cap, then
     `verify([thumbKey])` with **60 KB**. `verify` only reads sizes and deletes
     what is too large (`400 upload_too_large`); it moves nothing, so two calls
     leave nothing half-promoted. `UploadVerificationService`'s cap is a
     constructor field today (`upload_verification_service.dart:17-24`):
     `verify` gains an optional per-call cap, and the eight existing callers
     keep the constructor's 5 MB.
  3. **The move:** one `promoteNewKeys([imageKey, thumbKey], alreadyStored:
     the row's current keys)`, which copies both, then deletes both pending
     sources (T61's order).
  4. **The old objects** of a replaced image are deleted, best effort. Safe
     because no two rows ever share an object (duplicate copies, below).
  - Storage unreachable at any step answers `503 storage_unavailable` with
    `Retry-After`, as every claim path does
    (`storage_unavailable_status_test.dart`, T61).
- **Duplicate copies the objects** to fresh `story/myweli/{random}` keys
  (`copyObject`), so each row owns its images and replacing or deleting one
  never reaches another row's, the published original's least of all.
- **Orphans:** an unclaimed upload stays under `pending/`, which the lifecycle
  rule already empties ([backend-upload-orphans.md](backend-upload-orphans.md)).
- **The purge (T84)** deletes only `gallery/{id}/`, `logo/{id}/`, `review/`
  and `deposit/` keys: it never touches `story/` (observed in T84's row). A
  story about a purged salon is « Masquée » at once; its images go by §3.5's
  rule.

### 4.5 The service's checks

Each refusal names its field, so the console can put it under that field
(SYSTEM.md: errors belong to fields).

**At save and at publish (`400`):**
1. `kind` known; `salonId` present for `salon`, absent for `announcement`;
   `title` 2–20 (`title_too_short`, `title_too_long`) and no word over the
   card's limit (`title_word_too_long`, §2.6); `body` ≤ 140; `cta.label` 2–20
   when a target is set, and a target when a label is set (`cta_incomplete`);
   a `salon` story's target is its own salon; `imageAlt` 5–150;
   `sourceNote` 10–300; `withdrawReason` ≤ 300; no control characters in any
   of them.
2. The salons named exist (`salon_unknown`); the category is in the closed set
   (`category_unknown`, §2.2).
3. `areaIds`: ≤ 20, each an area of the tree (`area_unknown`), no duplicates.
4. The image keys: §4.4 steps 1–3.

**At publish only (`422`):** image and thumbnail present (`image_required`);
`imageAlt` present (`alt_required`); every salon named public
(`salon_not_public`); `startsAt ≤ now + 30 days` (`starts_too_far`);
`endsAt` present (`ends_required`), after now (`ends_in_past`), after
`startsAt` (`ends_before_start`), at most 30 days after it
(`lifetime_too_long`); `sourceNote` present (`source_required`);
`attest == true` (`attestation_required`); the price backstop
(`story_claims_price`). Then the cap (`409 too_many_stories`).

### 4.6 Caching

- `GET /stories` answers `Cache-Control: public, max-age=60`. Sixty seconds is
  the most a withdrawal or an end can wait to leave the response.
- *UNVERIFIED:* whether the Cloudflare Worker in front of `api.myweli.com`
  caches it. Nothing depends on it: the header only allows a cache, and the
  server reads the table on every request it receives. The read is one indexed
  query on a table of tens of rows.
- The app keeps **no copy of the stories on the device** (§5.2): a stale story
  offline is worth less than no row. It keeps one bit: whether its last read
  had any (§5.2, loading).

### 4.7 The contract: `docs/api/openapi.yaml`

In PR B, beside the code:
- `GET /stories` with `HomeStory`, `HomeStorySalon`, `HomeStoryCta`,
  `HomeStoryTarget` (`oneOf` salon / search, `discriminator: type`) and
  `HomeStoryCommune`;
- the ten admin operations of §4.3, with `AdminHomeStory`, its create and
  patch bodies, the error shape with `field`, and each code;
- `story` in the `/uploads/sign` purpose enum, with its admin-only note;
- the `HomeStory` schema's field names are the Dart model's, field for field
  (`HomeStory.fromJson`, §5.1), pinned by the contract test.

---

## 5. The app

### 5.1 Layers

| Layer | New or changed | Notes |
|---|---|---|
| Model | `models/home_story.dart`: `HomeStory`, `HomeStoryCta`, a sealed `HomeStoryTarget` (`SalonStoryTarget`, `SearchStoryTarget`) | immutable, `Equatable`, `fromJson`/`toJson` mirroring §4.1. **An unknown `kind` or `target.type`** from a newer server drops that story, never the whole list and never a crash |
| Interface | `services/interfaces/home_story_service_interface.dart`: `Future<ApiResponse<List<HomeStory>>> getHomeStories()` | |
| Mock | `services/mock/mock_home_story_service.dart` | latency, an error mode and an empty mode, like the other mocks. **Its stories are neutral** (« Bienvenue sur MyWeli », one `salon` story on a mock salon): mock mode is what screenshots and goldens photograph, so no price, no discount, no invented claim (§11 guard) |
| API | `services/api/api_home_story_service.dart`: `GET /stories` through `api_errors.dart` (`networkError`, `errorFromResponse`, `readOrUnreadable`), as `ApiLocalityService` does | |
| State | `providers/home_story_provider.dart` (`ChangeNotifier`): `isLoading`, `error`, `stories`, `readAt`; `visibleFor(commune, now)` applies §2.3 and §3.5 | **does nothing while `FeatureFlags.homeStories` is off**: no request leaves the app for a row that cannot show |
| DI | `dependency_injection.dart` | mock or API on `AppConfig.useApiBackend` |
| Widgets | `AnnouncementStories` reads the provider; `StoryViewer` takes `HomeStory`; the card's face and the viewer's page are drawn by two presentational widgets that take an image widget (`StoryCardFace`, `StoryPageFace`, in their own files with no `TimedCachedImage` import) | `StoryItem` and its `assetPath` go (§5.6) |

### 5.2 When the app reads, and the row's four states

**It reads** `GET /stories`:
- on the home's first frame, beside `loadFeaturedProviders`
  (`home_screen.dart:47`);
- on pull-to-refresh (`home_screen.dart:84-103`);
- when the app returns to the foreground, if its last read is older than
  60 s;
- when the home is shown again (a tab or a route back to it), if its last read
  is older than 5 minutes;
- when the viewer opens on a list older than 60 s (§5.4).

**The four states** (SYSTEM.md §12). The row is optional content inside the
home, not something the client asked for, so two of its states are
deliberately silent. **That is an exception to §12** (« every async section
renders four states »; loading « never a blank screen »; an error needs « a
way out »), and PR D writes it into §12 as a declared exception for optional
promotional rows, with this row as its one user. **Q10: approved, decision 180.**

| State | What the home shows | Why |
|---|---|---|
| **Loading** | a skeleton row at the strip's computed height **if the last read on this device had stories**; otherwise nothing | the skeleton prevents the jump when stories are usual; nothing prevents the collapse when they are not. The one bit (`had stories`) is all the device keeps |
| **Empty** (no story for this commune) | nothing; a skeleton shown while loading collapses | an `EmptyState` saying « no stories » is noise on a home; nothing is missing |
| **Error** | nothing; no banner, no snackbar | the row is optional, and an error on it must not cover the home. The way out is the home's own pull-to-refresh. The failure is reported the way the API layer reports others |
| **Success** | the row, as today: cards 92×126 at 1×, tracking the text scale (`_cardWidth`, `_stripHeight`) | the A13 geometry stays (or widens, §2.6) |

- **When the row arrives,** it opens with `AnimatedSize` at `AppMotion.base`,
  and appears at once under reduced motion (`reduceMotionOf`, SYSTEM.md §9.1).
- **When the commune changes,** the row re-filters at once; nothing is
  fetched.
- **Offline,** the row is absent.

### 5.3 The card

- **The thumbnail** comes from `thumbUrl` through `TimedCachedImage`, never
  the full image: eight full images would be 4 MB on the home, eight
  thumbnails under 0.5 MB. It is decoded at the card's size;
  `TimedCachedImage` takes no cache width today, so PR D adds one.
- **While it loads, and if it fails:** the card's `surface` fill, the title
  over it as today. A broken image does not hide a story whose words are
  intact.
- **Rings and weights stay** (§21 rows 3b, 25): unseen is a 3-px `gold` ring
  and a bold title; seen a 1-px `border` ring and a regular one.
- **Semantics:** `button: true`, label « {title}, nouvelle » or
  « {title}, déjà vue » (today's, `announcement_stories.dart:154-157`), hint
  « Ouvrir ».
- **The title** follows §2.6.

### 5.4 The viewer

**Today** (`story_viewer.dart`): the full image from an asset, a 6 s timer,
taps left (35 %) and right, a long press to pause, the title on one line with
an ellipsis, the button.

**After:**
- **The image** is `imageUrl` through `TimedCachedImage`, with `imageAlt` as
  its semantic label (it is meaningful here). Behind it, while it loads, the
  thumbnail already in the cache, so the screen is never black.
- **The timer waits for the image.** It starts when the image is painted or
  has failed, never before: on 3G a 6 s timer would otherwise run out over a
  loading screen.
- **Reading time:** 6 s for a story with a title only, **10 s** with a body
  (140 characters read in about 8 s). A content timer, not motion
  (SYSTEM.md §9): it keeps its literal and gains the `// ds-ignore` §9 asks
  for (`story_viewer.dart:46` has none today).
- **The timer survives « Supprimer les animations ».** SYSTEM.md §9.1 already
  rules it: « A content timer must not be collapsed », and a controller
  driving dwell « takes `AnimationBehavior.preserve` ». `_progress` takes it
  in PR D, unconditionally. A8 could not make its gate go red
  ([mobile-a8-motion.md](mobile-a8-motion.md)); PR D runs the reel on the
  Galaxy with the setting on, before and after, and records what it saw, and
  writes a gate that fails if `_progress` is built without `preserve`.
- **With a screen reader on** (`MediaQuery.accessibleNavigationOf`): **no
  timer.** Two visible buttons, « Story précédente » and « Story suivante »,
  48×48 with tooltips, beside « Fermer ». Today the taps are a bare
  `GestureDetector` that a screen reader cannot reach.
- **The words:** the title as a header, wrapping, no ellipsis; the body under
  it; both white on the scrim. Title, body and button sit in a bottom block
  that scrolls if it must, so at 200 % on a 360-dp phone nothing is clipped
  and the button is never pushed out of reach.
- **The button** builds its route from the target (§2.2); a salon hidden since
  the list was read lands on the salon page's own not-found state.
- **Opening on an old list:** when the viewer opens on a list read more than
  60 s ago, the provider reads again in the background, and any story no
  longer served leaves the reel as soon as the answer comes (the open one
  closes the viewer if it is the one withdrawn). A story past `endsAt` by the
  clock is skipped when the viewer opens or advances to it.

### 5.5 Seen state

- **Stays on the device**, in `StorySeenService` (`shared_preferences`, key
  `myweli_seen_story_ids_v1`), never sent anywhere.
- **Each seen id keeps the day it was last served.** After each successful
  read the served ids' days are refreshed, and an id not served for 30 days
  is forgotten. So a story hidden for a while (its salon suspended, then
  restored) keeps its « déjà vue », and the set stays small. The demo ids
  (`promo_weekend`, `new_salon`, `last_minute`) are never served, so they go
  after 30 days. A failed read changes nothing. The stored value moves from a
  list of ids to ids with days; PR D reads the old list as « served today ».

### 5.6 What is deleted, and the order

In PR D, in this order:
1. the source: `_stories()` (`announcement_stories.dart:48-72`) gives way to
   the provider;
2. the three SVGs in `assets/images/stories/` and their `pubspec.yaml` line
   (`pubspec.yaml:163`);
3. `StoryItem.assetPath` and both `SvgPicture.asset` calls (`flutter_svg`
   stays: eight other files use it);
4. the tests that held them: the three demo titles in « the home stories
   fit » (`layout_test.dart`) become fixtures from the mock, longest title and
   body included; `motion_test.dart`'s reel (`:331-344`), whose second asset,
   `nouveaux_salons.svg`, never existed, uses fixtures too.

**Only then, in PR E, does the flag flip** (`FeatureFlags.homeStories = true`,
the home goldens re-made with the row). A1's guard (`feature_flags_test.dart`)
stays green through both: after step 2 it finds no demo and stops asserting
the flag. PR E is its own PR (Q8, decision 178).

### 5.7 Accessibility and 200 % text

Gates, each watched red before it is trusted (§11):
- « the home stories fit » (`layout_test.dart`). **On A1's branch it keeps only
  the mid-word check and `takeException`** (`:615-645`); A1 left the
  truncation, legibility, vertical-clip and glued-token checks on the home
  pump (`:589-605`), where the row is hidden. PR D puts those four back on the
  row pumped alone, on fixtures holding the longest allowed title, so the
  declared truncation of §2.6 is gated before the row can show;
- **new:** « the story viewer fits » at each width × scale of the file, the
  longest title and body, the button visible without scrolling at 1× and
  reachable at 2×;
- **new:** the viewer under a screen reader shows the two buttons and runs no
  timer;
- **new:** `_progress` is built with `AnimationBehavior.preserve` (§5.4);
- the ring's two cues and the semantics label (rows 25 and 3b) unchanged.

---

## 6. The console (staff)

### 6.1 Where

A new sidebar group **« Contenu »**, one item **« Stories »**, at
`/admin/stories` in `admin_router.dart` like the others, after « Marché ».

### 6.2 The list

- **Title** « Stories de l'accueil ». **Subtitle** « Ce que les clients voient
  en haut de l'accueil de l'app MyWeli et de myweli.com. Tout ce qui est
  publié doit être vrai. »
- **Segments:** « En ligne (n) », « Brouillons », « Terminées »,
  « Retirées ». « En ligne » lists states 4, 5 and 6 of §2.5 (at most 8), each
  with its chip: « En ligne » (green), « Programmée » (neutral),
  « Masquée — salon non public » or « Masquée — commune inconnue » (amber).
  Staff must see what they think is live and is not.
- **Columns:** « Aperçu » (the thumbnail, through `AdminRemoteImage`, which
  needs no CORS), « Titre », « Type », « Communes » (« Toutes » or the names),
  « Du », « Au », « État ».
- **Order:** under « En ligne », « Monter » and « Descendre » on each row
  (buttons, not drag alone, so the keyboard works). A `409 order_stale`
  reloads the list with « La liste a changé entre-temps : vérifiez l'ordre. »
- **Primary action:** « Nouvelle story ».
- **States:** skeleton rows; empty « Aucune story en ligne. Les clients ne
  voient pas de rangée de stories. » (and one per segment); error with
  « Réessayer ».

### 6.3 The editor

Left, the form; right, the preview (§6.5).

| Field | Label | Help under it |
|---|---|---|
| kind | « Type » : « Annonce MyWeli » / « Salon » | |
| salon | « Salon » (Salon only): « Rechercher un salon en ligne » | only public salons are offered (`GET /admin/providers?status=active&q=`) |
| title | « Titre » | « 20 caractères au plus, mots de {n} lettres au plus. Affiché sur la vignette. » + a counter |
| body | « Texte (facultatif) » | « 140 caractères au plus. Ni prix, ni réduction. » |
| image | « Image » : « Choisir une image » / « Remplacer » | « Portrait (9:16). Aucun mot dans l'image : les mots vont dans Titre et Texte. » |
| alt | « Description de l'image » | « Lue par les lecteurs d'écran. Décrivez ce que montre l'image. » |
| button | « Bouton » : « Aucun » / « Ouvrir le salon » / « Rechercher » (+ « Catégorie (facultatif) ») ; « Libellé du bouton ». A « Salon » story offers only « Aucun » and « Ouvrir le salon » | suggestions « Voir le salon », « Voir les salons » |
| dates | « Début » (« Dès la publication » or a date and time) ; « Fin » | « Heure d'Abidjan. Début dans les 30 jours ; fin 30 jours au plus après le début. » |
| communes | « Communes » : « Toutes les communes » / a multi-select from the tree | |
| source | « Comment savez-vous que c'est vrai ? » | « Ex. : salon validé par MyWeli le 20/11 ; horaires confirmés par téléphone le 23/11. Visible seulement dans la console. » |
| attest | the box of §3.3 | |

**Buttons:** « Enregistrer le brouillon » (secondary) and « Publier… »
(primary). On a published story the form is read-only, with « Dupliquer »,
« Retirer… » and, once it has ended or been withdrawn, « Supprimer les
images… ».

### 6.4 The image, prepared in the browser

- The console decodes the chosen file, refuses anything under 720×1280
  (« Image trop petite : 1080 × 1920 conseillé. »), and warns when it is not
  9:16 within 5 % (« L'image sera recadrée ; vérifiez l'aperçu. »).
- It produces **two JPEGs**: the image (at most 1080×1920, quality 80) and
  the thumbnail (300 px wide, quality 70). Re-encoding drops every metadata
  field, GPS included, as the web's Pro uploads do
  ([web-pro-upload-resize.md](web-pro-upload-resize.md)).
- *UNVERIFIED, decided at build:* the mechanism under CanvasKit
  (`flutter_image_compress`'s web side, already a dependency, or
  `package:image`). PR C measures both on the console and keeps the one that
  works; if neither does, the fallback is to refuse files over the caps with
  « Exportez l'image en JPEG, 1080 × 1920, moins de 500 Ko. »
- Then two `POST /uploads/sign` (`purpose: story`), two `PUT`s to R2 from the
  page, and the keys go with the next save. **The PUT needs the CORS rule of
  §0 item 2.**
- **Errors, under the field:** a failed PUT « L'envoi de l'image a échoué.
  Réessayez. » ; `upload_too_large` « Image trop lourde après préparation. » ;
  `upload_not_found` « L'image n'est pas arrivée. Choisissez-la de nouveau. » ;
  `rate_limited` « Trop d'envois d'images. Réessayez dans quelques minutes. » ;
  `storage_unavailable` « Le stockage ne répond pas. Réessayez dans un
  instant. »

### 6.5 The preview

- **The card** at 1× and 2× side by side, and **the viewer** in a 360×800
  frame, both drawn by the app's own presentational widgets
  (`StoryCardFace`, `StoryPageFace`, §5.1) fed the draft. So what staff see is
  what clients get, including a title that ends in « … ».
- **Their image** is the prepared bytes (`Image.memory`) while editing, and
  `AdminRemoteImage` for a saved or published story. Neither needs a CORS
  `GET` from R2, and the console never imports `TimedCachedImage`: the guard
  `test/infra/admin_remote_images_guard_test.dart` walks the console's imports
  and would fail, and SYSTEM.md §19 makes `AdminRemoteImage` « the only way
  the console draws an image from another origin ».
- A line under it: « Visible par : {toutes les communes | Cocody, Marcory} ·
  du {date} au {date} ».

### 6.6 Publishing, withdrawing, and every code as a sentence

- **« Publier… »** opens « Publier cette story ? » — « Elle sera visible par
  les clients de {communes}, du {date} au {date}, dans l'app et sur
  myweli.com. Une story publiée ne se modifie plus : pour la changer,
  dupliquez-la puis retirez celle-ci. » — « Publier » / « Annuler ».
- **« Retirer… »** opens « Retirer cette story ? » — « Elle n'est plus servie
  dans la minute. Un téléphone ou un onglet déjà ouvert la retire à sa
  prochaine actualisation. » — « Motif (facultatif) » — the box « Supprimer
  aussi l'image (contenu inapproprié, accord retiré) » — « Retirer » /
  « Garder ».
- **« Supprimer les images… »** opens « Supprimer les images de cette
  story ? » — « Le texte reste dans l'historique. Les images ne pourront pas
  être récupérées. » — « Supprimer » / « Garder ».

| Code | Field | Sentence |
|---|---|---|
| `title_too_short` / `title_too_long` / `title_word_too_long` | Titre | « Au moins 2 caractères. » / « 20 caractères au plus. » / « Un mot est trop long pour la vignette ({n} lettres au plus). » |
| `body_too_long` | Texte | « 140 caractères au plus. » |
| `story_claims_price` | Titre or Texte | « Une story ne parle ni de prix ni de réduction. » |
| `image_required` | Image | « Ajoutez une image. » |
| `alt_required` / `alt_length` | Description | « Décrivez l'image. » / « Entre 5 et 150 caractères. » |
| `cta_incomplete` | Bouton | « Choisissez une destination et un libellé. » |
| `salon_required` / `salon_unknown` | Salon | « Choisissez le salon. » / « Ce salon n'existe plus. » |
| `salon_not_public` | Salon | « Ce salon n'est pas en ligne : il ne peut pas être mis en avant. » |
| `category_unknown` | Catégorie | « Catégorie inconnue. » |
| `area_unknown` | Communes | « Commune inconnue. » |
| `starts_too_far` | Début | « Le début doit être dans les 30 jours. » |
| `ends_required` / `ends_in_past` / `ends_before_start` / `lifetime_too_long` | Fin | « Ajoutez une date de fin. » / « La fin est passée. » / « La fin précède le début. » / « 30 jours au plus après le début. » |
| `source_required` / `source_length` | Source | « Dites comment vous savez que c'est vrai. » / « Entre 10 et 300 caractères. » |
| `attestation_required` | the box | « Cochez la confirmation pour publier. » |
| `too_many_stories` | top of the form | « Huit stories au plus en ligne ou programmées. Retirez-en une d'abord. » |
| `story_published` | top of the form | « Cette story est déjà publiée. » (the page reloads) |
| `order_stale` | the list | « La liste a changé entre-temps : vérifiez l'ordre. » |
| `story_live` | top of the form | « Retirez d'abord la story. » |

### 6.7 The journal

`audit_actions.dart`'s `kAuditActions` gains a French label for each new code,
in PR B itself: `validation_labels_test.dart:274-317` reads the backend's
writers under `lib/src/admin` and fails on a code with no label, and the
service lives there (§1.4).

| Code | Label |
|---|---|
| `story.create` | « Story créée (brouillon) » |
| `story.update` | « Brouillon de story modifié » |
| `story.publish` | « Story publiée » |
| `story.withdraw` | « Story retirée » |
| `story.images_delete` | « Images de story supprimées » |
| `story.duplicate` | « Story dupliquée » |
| `story.reorder` | « Ordre des stories modifié » |
| `story.delete` | « Brouillon de story supprimé » |

---

## 7. Web parity: does `myweli.com` show them?

**The rule** (WEB.md §0): the consumer web reaches parity with the consumer
app, or the gap is called out. The stories are on the app's home, so the
web's home owes them too, adapted to a desktop. **Yes, in its own PR after
the app's (PR F): Q3, decision 173.**

### 7.1 Where and how it looks

- **On `/`**, under the hero's search (`SiteHero` + `HomeSearch`), above the
  category tiles, in a `SiteSection`. Up to 8 portrait cards, larger than the
  app's on a desktop; a horizontal scroll at phone width. Tokens only, the
  closed Tailwind theme, no arbitrary value.
- **Each card is a `<button>`** with the same accessible name as the app's.
  Unseen and seen get the same two cues (ring width, title weight), applied
  after mount (`useEffect`), never during the server render, so the HTML
  matches and nothing moves: **the web keeps the server's order** (§2.4).
- **The viewer is the existing `Modal`** (it traps focus and restores it):
  the image with `alt`, the title as its heading, the body, the button as a
  link (`/{slug}` or `/recherche?category=`), « Précédente » / « Suivante »
  buttons, the arrow keys, Esc. **No timer on the web**: the visitor moves.
- **The install push** (WEB.md §0 rule 2): a `salon` story's dialog also
  offers « Ouvrir dans l'app » (`OpenInAppButton`).
- **Commune:** the web keeps no chosen commune (`HomeSearch`'s field is not
  stored), so it shows the stories that target every commune (§2.3).
- **Seen state:** `localStorage`, same key name, every read and write in a
  `try`; without it everything reads as unseen.

### 7.2 Rendering: server first, then checked through a route handler

- **Rendered with the page** (ISR), the server fetching `GET /stories` with a
  60-second revalidation, so the row is in the HTML and causes no layout shift
  (CWV: CLS). A row inserted after load would push the tiles down on every
  visit with stories.
- **The browser never calls the API.** WEB.md §4: « the browser only talks to
  Next route handlers »; the CSP's `connect-src` does not list
  `api.myweli.com` (`web/next.config.mjs:170-179`). A new `/api/stories`
  route handler, `dynamic = 'force-dynamic'`, forwards `GET /stories`, the way
  `web/app/api/localities/route.ts` forwards the tree.
- **Checked after hydration, on dialog open, and on return to the tab**
  (`visibilitychange`): the client reads `/api/stories` and removes any card
  no longer served (withdrawn, ended, its salon hidden), and any past `endsAt`
  by the visitor's clock. A stale ISR page or a tab left open shows a
  withdrawn story only until its next check. The removal moves the layout only
  in that rare case.
- **Not indexed as content:** the section carries `data-nosnippet`, and no
  structured data. A time-limited sentence in a search snippet outlives its
  end.
- **The page's own revalidation** drops from 3600 s to 60 s (in the App
  Router the lowest fetch revalidation sets it). PR F measures the cost
  (*UNVERIFIED*: the Vercel usage after the change).

---

## 8. Security and the threat model

### 8.1 Authz

- **Public read:** no token, no input, an allowlisted DTO (§4.1).
- **Admin routes:** under `/admin/*`, deny by default, `role == admin` (T17);
  each route pinned `401` (no token, expired, foreign key) and `403`
  (provider, client) with nothing written.
- **`/uploads/sign` `story`:** admin only; every other role `403`; the key is
  the server's; the claim re-checks the prefix (§4.4).
- **Server authority:** the server decides what is served (its clock, its
  salon read), never the client.

### 8.2 T85, a new row in BACKEND.md §7

In the table's own columns (`# | Surface | Threat | Mitigation | Status`):

| # | Surface | Threat | Mitigation | Status |
|---|---|---|---|---|
| T85 | **Staff-published home stories** (`design/managed-home-stories.md`; `GET /stories` public; `/admin/stories*`; `/uploads/sign` purpose `story`; migration 0047 `home_stories`; the public bucket's CORS rule for `admin.myweli.com`) | **S/E** — a stolen admin session publishes to every client's home: phishing, offence, a false offer. **T** — a client or salon token writes a story or signs a `story` upload; an admin claim names another namespace's key (`pending/gallery/{salonId}/…`) and moves it into a salon's prefix. **I** — drafts, source notes or staff ids leak through the public read. **R** — nobody can say who published what. **D** — an oversized image costs every client's data plan; publishes racing past the cap | The T17 gate on every admin route. A **closed target list**, no URL (§2.2): the worst a stolen session can do is say something false or offensive inside the app, never send clients elsewhere. Text drawn as text (no HTML, no markdown). The claim's **prefix check** (`pending/story/myweli/` or the row's own key). The cap of 8 under a transaction lock; the 30-day lifetime. One audit row per mutation. « Retirer » (served no more within 60 s; open clients at their next read) and « Supprimer les images ». The field allowlist and its contract test. Size caps verified at claim (500 KB / 60 KB). `Cache-Control` on the read. The CORS rule is not an auth control: the presign still is. **Residuals:** one admin password and no second factor on the API (Cloudflare Access covers the console's bundle only, as T82 says; 2FA is R7); a false story with no price token; text in an image; an open app showing a withdrawn story until its next read; a story image public at its URL until deleted (at most 90 days after the end, Q11) | Specified, not built |

PR C also updates what says `admin.myweli.com` is on no bucket's list: the
`cors.$comment` in `r2-manifest.json`, SYSTEM.md §19's `AdminRemoteImage`
row, and the guard's comment. Their point stands (the console still never
*reads* R2 through CORS); the fact changes.

---

## 9. Privacy

**What the client sends:** a `GET /stories` with no token, no commune, no
identifier. The commune filter (§2.3) and the seen state (§5.5) stay on the
phone.

| Question | Answer |
|---|---|
| Does the App Store privacy label change? | **No**: Q5 is answered « no counting » (decision 175), so nothing new leaves the device. The request's IP address reaches our servers as every request's does |
| Does Play's Data safety change? | **No**, for the same reason |
| Does the privacy policy change? | **No new processing of a client's data.** Q5 is « no » (decision 175). If a later spec counts views or taps, they are « usage data » and must be declared first (Apple: Product Interaction) |
| Staff data | the admin ids in `audit_log` and on the row, as for every console action |
| People in the images | a recognisable person needs their written consent, held by MyWeli; the attestation covers it (§3.3), and `sourceNote` says where the consent is. If consent is withdrawn, « Supprimer les images » removes the picture at once (§3.5) |
| Image metadata | the console's re-encode drops it, GPS included (§6.4) |
| How long images live | 90 days after the story ends, or at once on request (§3.5, Q11) |
| A salon in a story | business information about a public salon; the row stays after the salon is purged (the record), its salon set to null; its images follow §3.5's rule |

---

## 10. Performance

| Budget | How it holds |
|---|---|
| Home interactive < 1.5 s on 3G | the row loads beside the featured salons, never before them, and shows only a skeleton until it has something (and only where stories are usual) |
| Data on the home | thumbnails only, ≤ 60 KB each, ≤ 8: under 0.5 MB with every story live; the full image only when a story is opened |
| 60 fps | a `Row` of at most 8 in a horizontal scroll, as today; thumbnails decoded at card size |
| p95 read | one indexed query plus one batch salon read; `max-age=60` |
| Web CWV | rendered with the page (no CLS); the dialog's code split from the page's |

---

## 11. Testing

**Backend (PR B)**
- **Unit**, `HomeStoryService`: every check of §4.5 one by one, each code and
  its status (400 or 422); the state derivation of §2.5 at its edges
  (`startsAt == now`, `endsAt == now`, withdrawn and ended at once, scheduled
  with a hidden salon); the price backstop, its tokens and a sentence it must
  let through (« Prenez rendez-vous à Cocody »); the cap; the published
  story's immutability; duplicate's copies; an unknown `areaId` hides.
- **Claims:** a key outside `pending/story/myweli/` refused (`gallery`,
  `deposit`, `review`, a promoted key of another row); each size cap;
  `upload_not_found`; `503 storage_unavailable` on every step (the T61 test
  gains this path); replacing a duplicate's image leaves the original's
  objects in place.
- **Concurrency (Postgres, DB-gated):** two publishes with 7 live → one
  `409 too_many_stories`; two reorders from the same `expected` → one
  `409 order_stale`; a double publish → one `409 story_published`.
- **Repository**, both twins through one contract file; the purge's Postgres
  test with a story pointing at the purged salon.
- **Handlers:** each admin route `401` / `403` (provider, client) / `405` /
  `400` / `404` / `409` / `422`, with nothing written on a refusal; one audit
  row per success; `idempotent()` on create and duplicate (a replay returns
  the first answer, one row); the public read's filters (draft, scheduled,
  ended, withdrawn, salon `draft`, `suspended`, gone, as subject and as
  target, unknown area), its order, its cap, its header, and **its field
  allowlist**.
- **`/uploads/sign`:** `story` with an admin token → `200`, a key
  `pending/story/myweli/…` in the public bucket; with a client or provider
  token → `403`; an admin token with `gallery` → `403`; the `signStory`
  bucket.
- **The journal's labels:** `validation_labels_test.dart` green with the eight
  codes, red with one label removed.
- **Contract:** every response checked against `openapi.yaml`.

**App (PR D, PR E)**
- **Unit:** `HomeStory` round trip against a §4.1 sample; unknown kind or
  target dropped; `visibleFor` for each commune case of §2.3 and each clock
  case of §3.5; the stable (seen, index) order; the seen days and the 30-day
  forgetting, and the old list read as « served today ».
- **Provider:** no request while the flag is off; each read trigger of §5.2
  and none outside them.
- **Mock:** latency, error and empty modes.
- **Widget:** the four states of §5.2, the skeleton only after a read that had
  stories; the viewer's timer waiting for the image; the image failure; each
  target's route; the screen-reader mode; a withdrawn story leaving an open
  reel.
- **A11y gates** of §5.7; **goldens** on Linux (`./tool/update_goldens.sh` or
  the workflow): the home with the row (PR E), the viewer, each changed PNG
  opened.
- **Guards** (each watched red):
  - after the demo goes, `feature_flags_test.dart` gains « no
    `assets/images/stories/` and no `StoryItem(` literal under `lib/` »;
  - « the row's only source is `HomeStoryServiceInterface` » (a source pin
    on `announcement_stories.dart`, comments stripped);
  - « no mock story says a price »: the mock's strings against the backend's
    token list, read from both files the way
    `cancellation_notice_parity_test.dart` reads two (A1, #834), so the two
    lists cannot drift. **Blind spot, written in it:** a claim without those
    tokens.

**Console (PR C):** `AdminService` methods against a fake client; the list's
states, segments and chips; the editor's field errors from each code; the
publish, withdraw and image-delete dialogs; the image preparation (sizes,
metadata gone); `admin_remote_images_guard_test.dart` still green with the
preview in the import graph; a golden of the editor.

**Web (PR F):** unit (the check removes a withdrawn and an expired story;
`localStorage` failing; seen styles applied after mount, the order unchanged);
the `/api/stories` handler; Playwright with the handler stubbed (row, empty,
error, the dialog by keyboard, Esc, focus back on the card); axe; the CWV
budget on `/`.

**Mutations to watch red, at least:** the public read without its salon
filter; without its `endsAt` filter; a column added to the DTO; the role map
letting `provider` sign `story`; the claim without its prefix check; publish
without `attest`; publish without the lock (the concurrency test); the
reorder without `expected`; the app's sort back to `List.sort` on seen only;
the viewer's timer started before the image; `_progress` without `preserve`;
the web without its check.

---

## 12. Rollout: each step on the owner's word

| Step | What | Who | Reaches clients? |
|---|---|---|---|
| 1 | this spec approved; its PR merged | owner | no |
| 2 | **PR B, backend:** migration 0047, routes, `story` purpose, contract, T85, the journal's labels (a `mobile/` file, because the label test reads the backend). Merged on the owner's word; the production deploy is `workflow_dispatch`, **asked for, then run** | owner's yes ×2 | no: nothing publishes yet |
| 3 | **R2 CORS:** the public bucket also allows `PUT`, with the `content-type` header, from `https://admin.myweli.com`; `r2-manifest.json` gains the origin. A cloud change: shown, asked, then applied, then **probed**, because `95-verify-r2.sh` only checks that the origin is listed and that GET and PUT appear somewhere (`:89-110`): a PUT preflight with `content-type` from `admin.myweli.com` answers `204`, and the same from an unlisted origin still `403` (the control) | owner's yes | no |
| 4 | **PR C, console:** « Stories », the comments of §8.2 updated. Merged, then `deploy-admin.yml` on the owner's word | owner's yes ×2 | no |
| 5 | the owner publishes (or not) a first real story in production. **Every consumer build still has the flag off** | owner | no |
| 6 | **PR D, app:** the managed source; the demo list and SVGs deleted; the timer's `preserve`; the §12 exception in SYSTEM.md; flag still off | owner's yes | no |
| 7 | **PR E, app:** the flag on, goldens with the row | owner's yes | **with the next consumer build** (Track C, each build on the owner's yes) |
| 8 | **PR F, web:** the row on `myweli.com` (Q3, decision 173). Merging deploys to production | owner's yes | **yes, at merge** |

- **Not on the release's path** (Q9, decision 179): the consumer app can ship with the row
  hidden; nothing here blocks A2–A6 or Track C.
- **The 90-day image task** (Q11, decision 181) is part of PR B: a new task on the existing
  maintenance cron, in rehearsal first like the salon purge, its run logged as
  one line.
- **Rollback:** « Retirer » (served no more within 60 s); the web's PR
  reverted; the flag off in the next build. The table stays (additive).
- **Production data is real:** no step deletes or rewrites a row outside the
  new table.

---

## 13. Definition of done (per PR)

- [ ] `analyze` = 0 (Dart, both packages) · `tsc` + lint clean (web) ·
      format clean · tests green · coverage not down.
- [ ] Contract, BACKEND.md §7 (T85) and the roadmap entry in the same PR as
      the code.
- [ ] This spec linked from the code it governs (`// Design:
      docs/design/managed-home-stories.md`) and its status updated.
- [ ] Each new guard's mutation watched red and listed in the commit.
- [ ] Each deploy and the CORS change asked for, then done, then read back
      on the deployed thing.
- [ ] Feature branch + PR; CI green; no Claude attribution.

---

## 14. Questions for the owner — answered

**All eleven answered on 2026-11-23, in the owner's words « Approve as
recommended »**: each recommendation below is the decision, numbered 171–181
in [BACKLOG.md](../BACKLOG.md) (B0.10). Q7's answer approves the CORS rule;
the change itself is still shown, asked for and probed at step 3 of §12, like
every cloud change.

| # | Question | Answer (decision) | Why |
|---|---|---|---|
| Q1 | Who publishes: MyWeli staff from the console, or salons from MyWeli Pro? | ✅ **Staff, now; salons stay V2** (171) | V1-sized, no UGC obligations (App Store 1.2, Play UGC), a publisher exists today; the model leaves room for salons (§1.3) |
| Q2 | May a story state a price, a discount or a free offer? | ✅ **No, not until promo codes exist** (172) (FR-BOOK-013, V2) | the booking would charge the full price the story undercut: Apple 2.3.1's « false price », Play's misleading claims (§3.2) |
| Q3 | Does `myweli.com` show the stories? | ✅ **Yes, in its own PR after the app's** (173) | the parity rule; server-rendered then checked, so no layout shift and no stale claim for long (§7) |
| Q4 | With no commune chosen, which stories show? | ✅ **Only those for every commune** (174) | a story targeted at one commune is about that commune (§2.3) |
| Q5 | Count views or taps? | ✅ **No, not now** (175) | nothing new leaves the phone, so no label or policy change (§9); a later spec can add aggregate counts and declare them |
| Q6 | Must every story end within 30 days of its start, and start within 30 days? | ✅ **Yes** (176) | a sentence true today is not true forever; the cap makes someone look again (§3.5) |
| Q7 | Let the console upload to R2 by allowing `admin.myweli.com` to `PUT` on the public bucket (a cloud change), rather than sending images through the API? | ✅ **Yes, the CORS rule** (177) | the API never carries upload bytes today, and the rule only widens who may PUT with a server-issued signature (§0, §4.4) |
| Q8 | Turn the flag on in its own PR, after the one that deletes the demo? | ✅ **Yes** (178) | you choose the moment; the build that carries it is yours anyway (§5.6, §12) |
| Q9 | When to build it? | ✅ **After Track A, not blocking the release** (179) | the release ships with the row hidden and loses nothing (§12) |
| Q10 | May the row show nothing while it loads (unless stories are usual on that phone), when there are none, and when the read fails — an exception written into SYSTEM.md §12? | ✅ **Yes** (180) | the row is optional content; an empty-state or an error banner about it would be noise on the home, and the home's pull-to-refresh is the way out (§5.2) |
| Q11 | How long do an ended story's images stay online? | ✅ **90 days after the end, then deleted automatically; at once on request** (181) | the text stays as the record; a picture of a person, or a mistake, should not stay public for ever (§3.5, §9) |
