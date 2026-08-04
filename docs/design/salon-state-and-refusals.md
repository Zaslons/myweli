# A salon that is not live — what it may do, and what everyone is told (SYSTEM.md §21 row 82)

> Modules: **online booking** + **salon lifecycle** (docs/MODULES.md).
> Closes §21 row **82**. Surfaces: backend · mobile consumer · mobile pro · web.
> Prior art: [pro-salon-lifecycle.md](pro-salon-lifecycle.md),
> [mobile-a14-pickers.md](mobile-a14-pickers.md) Part D (the `beyond_horizon` /
> `too_soon` precedent this follows exactly).

## 1. Goal & scope

A salon that is not `active` refuses every booking with **one code**, and no
surface has a sentence for it — so all four fall through to a generic apology.
The worst instance is the one every salon meets: **the pro's first ever manual
booking**, refused with « Une erreur est survenue. » two taps from a dashboard
card inviting them to go live.

This spec settles three things: **what a draft salon is allowed to do**, **what
the wire says**, and **what each of four surfaces tells which person**.

## 2. What was measured

**4 surfaces, none handling the code.** `grep provider_suspended` over
`mobile/lib`, `web/lib`, `web/components`, `web/app` → **zero hits**. Mobile
consumer falls to `api_appointment_service.dart:337-338` « Une erreur est
survenue. »; mobile pro to `api_pro_service.dart:793-794`, the same literal; web
to each call site's injected fallback — `BookingFlow.tsx:357-360` « La
réservation a échoué. Réessayez. » and `ManualBookingDialog.tsx:129-132`
« Création impossible. Réessayez. » **Both web fallbacks say « Réessayez » for a
state retrying can never fix**, which is the failure A14d named in row 76.

**2 write paths, byte-identical.** `booking_service.dart:56-59` (consumer `book`)
and `:204-207` (pro `bookManual`), both
`if (provider['status'] == 'suspended' || provider['status'] == 'draft')`.
Mapped to 409 at `routes/appointments/index.dart:168` and
`routes/providers/[id]/appointments.dart:73` — two switches, **already drifted**
(the pro one lacks `beyond_horizon`/`too_soon`).

**1 code, 2 statuses, 4 meanings.** `draft` is written at three sites meaning
three different things — never-published (`providers_repository.dart:738`),
owner-deleted-their-account (`provider_account_service.dart:70`), and
billing-past-grace (`subscription_scheduler.dart:55`). `suspended` is written at
exactly one, admin-only and audited (`admin/admin_provider_service.dart:59-60`).

**`suspended` is reachable.** `routes/admin/providers/[id]/suspend.dart` exists,
admin-guarded, and its UI ships — `main_admin.dart:25`,
`admin_providers_screen.dart:171` « Suspendre » / « Réactiver ». Not theoretical.

**Frequency asymmetry.** `draft` is the state **every** salon starts in. The code
is named for the rare case and silent about the universal one.

**The load-bearing constraint.** `mobile/lib/models/provider.dart` has **no
`status` field**, and `grep isSuspended mobile/lib` returns nothing. The mobile
pro app therefore **cannot** disambiguate client-side. That disqualifies any
option that pushes the distinction to the client.

**Test coverage: one assertion, on the wrong half.**
`backend/test/admin_provider_test.dart:73` suspends first, so it exercises a
genuinely suspended salon through `book()` only. The `draft` half, all of
`bookManual`, and both route mappings are untested.

**Contract: zero mentions.** `provider_suspended` appears nowhere in
`openapi.yaml`. The pro manual 409 (`:1968-1971`) documents only « Exact-start
slot already booked » — **already wrong**, since that route returns
`provider_suspended` as a 409 today.

## 3. Decision A — a draft salon owns its calendar

**`bookManual` stops refusing `draft`. It refuses `suspended` only.**

A salon populating next week's already-agreed appointments before going live is
ordinary onboarding, not an edge case, and it is what comparable products allow.
A14d already established the governing principle — *« the salon owns its
calendar »* — which is precisely why `bookManual` is exempt from the booking
window. And the salon can already set hours, block dates and add services while
draft; refusing only *appointments* is arbitrary.

The rule that results is clean and says itself:

> **A salon that has not published yet owns its calendar. A salon that has been
> suspended does not.**

This removes row 82's worst case rather than papering over it: the pro's first
manual booking **succeeds**, so no copy is needed for it at all.

The consumer path (`book`) is unchanged in behaviour — a draft salon still
refuses public bookings, because it is not publicly listed.

## 4. Decision B — split the code

`draft` → **`provider_not_published`**. `suspended` → keeps `provider_suspended`.

The contract already contains the argument, written for A14d at
`openapi.yaml:2321-2330`: the last two codes are *« distinct from
`slot_unavailable` on purpose: that code makes every client say some version of
"someone else just took your slot", which is false for a window breach and leaves
the user retrying a time that can never be offered »*. `provider_suspended` fails
the identical test.

It also respects server authority in the way that matters here: the server is the
only party that knows the status, and after the split it is the only party that
needs to — **no client needs a `status` field it does not have** (§2).

`provider_suspended` keeps its meaning for suspended salons, so **no existing
code changes meaning** and the envelope's stability requirement
(`docs/BACKEND.md:42-46`) holds.

Naming: `provider_not_published` over `provider_draft` (which leaks an internal
lifecycle word onto the wire) and over `provider_unpublished` (ambiguous between
never-published and taken-down). No `not_published` exists in the backend today.

## 5. Decision C — close the public read

**Status: SHIPPED. The question was answered and built in PR1c; the doors
closed in PR1d.**

### The answer: the relationship lives on the server, so the server hydrates it

This section deferred one question — *how does a consumer's own appointment or
favourite keep resolving a salon they have a relationship with?* Here it is.

**An anonymous caller gets a 404 that is indistinguishable from « does not
exist »** (T51's no-oracle rule). **A caller with a relationship keeps the
salon's facts, and its `status`, through the AUTHENTICATED endpoint that owns
the relationship.** Concretely:

- `GET /appointments` and `/appointments/{id}` embed the salon's identity,
  contact, address, deposit coordinates, artist and service names, booking
  window and **`providerStatus`** (`withProviderFacts`). No status filter: a
  draft or suspended salon enriches in full.
- `GET /me/favorites` returns hydrated salons, also unfiltered, each carrying
  its status — so a favourite whose salon stopped is **marked, not dropped**.
- The write half does filter: you cannot NEWLY favourite a salon you cannot
  reach. An existing favourite is a relationship; a new one would be a way to
  name a hidden salon.

Two consequences worth stating, because they are not obvious:

1. **Cell 5's copy is status-agnostic BY CONSTRUCTION.** The 404 carries no
   status — deliberately — so the public salon page cannot say *which* kind of
   not-live a salon is. Only a surface holding the relationship can use the
   tense-carrying pair. That is a property of the no-oracle rule, not an
   oversight in the copy.
2. **The enrichment is a disclosure surface.** It runs on every consumer
   appointment read, so everything on it reaches anyone holding a booking at
   that salon. **Only fields that are public while the salon is `active` may
   ride it** — recorded in T51 before someone adds a fifth field.

### Two alternatives, rejected on the record

- **An authenticated by-id read** (`/providers/{id}` answering differently for a
  caller with a relationship) — re-opens the door PR1b closed, gives one URL two
  behaviours, keeps both N+1s, and does not answer the question for a *list*.
- **Snapshotting the salon's facts at booking time** — a March phone number is
  worse than none. `currency` is the single deliberate exception (multi-pays §4:
  a price is what it was, not what it is).

### What PR1c deleted

Web's fan-out (`bff.ts`'s `providerSummary`, one request per distinct salon),
the favourites fan-out, `fetchBookingWindow` and the `app/api/providers/[id]`
proxy that existed only to serve it, and **six** provider reads from mobile's
appointment-detail screen. Three live defects died with them: « Numéro
indisponible. » blaming a phone number for a salon-state problem, a deposit
sheet opening with no Mobile Money handle to pay to, and a calendar export
writing « Rendez-vous — le salon » at zero duration **while reporting success**.

### Verified against a running server, with the door actually shut

2026-08-03, `dart_frog dev`, the realistic arc: register a salon → give it a
service, a Mobile Money handle and a 45-day / 90-minute booking window → admin
activates it → **a consumer books and favourites it while it is live** → admin
**suspends** it. Then PR1d's gate was applied temporarily — `isPublicSalon` on
`/providers/{id}`, `by-slug` and `/providers/{id}/reviews` — and the server
restarted. Measured over real HTTP:

| door | result |
|---|---|
| `GET /providers/{id}` | **404** |
| `GET /providers/by-slug/{slug}` | **404** |
| `GET /providers/{id}/reviews` | **404** |
| `GET /providers` (discovery) | 200, salon absent |

and, at the same moment, for the people who have a relationship with it:

| surface | result |
|---|---|
| the client's `GET /appointments` | `providerName: Salon PR1c` · `providerStatus: suspended` · `providerPhone` · `wave` + `+2250700112233` · `serviceNames: [Tresses]` · `durationMinutes: 180` · window `45` / `90` · `providerTimezone` |
| the client's `GET /me/favorites` | `providers: [(Salon PR1c, suspended)]` — **present and marked** |
| the owner's `GET /me/provider/reviews` | **200** |
| the owner's `GET /me/provider` | **200** |

The enrichment also refused to leak: none of `services`, `artists`,
`imageUrls`, `reviews` or `availability` appears on the appointment payload —
the allowlist rule, measured rather than asserted. The gate was reverted;
`git status` on the three route files is clean.

**One thing this run confirmed on the way past:** Decision A is live. A manual
booking into a salon that was still `draft` succeeded (`manual_…`), while the
consumer path refused the same salon.

### The original text, kept because the miss is the lesson

`GET /providers/{id}` currently returns **draft and suspended** salons
(`routes/providers/[id]/index.dart:27-35`), while `by-slug` excludes draft
(`by-slug/[slug].dart:19-20`) and discovery excludes both. That contradicts the
contract's own promise that public reads only ever return `active`
(`openapi.yaml:4207-4212`), and it is the route by which a favourite reaches a
banned salon.

**⚠️ Deferred to its own slice, and the safety claim above was wrong.** This
section originally read *"Verified safe: the pro reads its own salon through
`/me/provider` and `PATCH`, never the public `GET`."* That was checked against
`api_pro_service.dart` only. The pro app **also** uses the shared
`serviceLocator.providerService`, and four pro surfaces went through the public
read — **all four are fixed as of PR1b**, and the table is kept because the
shape of the miss is the lesson:

| call site | broke how | now |
|---|---|---|
| `core/router/pro_router.dart:222` → `/pro/apercu` | **404s the owner's own pre-publish preview**, reached from `pro_onboarding_screen.dart:125` | new `screens/provider/salon_preview_screen.dart` fetches `/me/provider` and seeds the shared screen via `ProviderProvider.showPreloaded` |
| `providers/pro_salon_profile_provider.dart:25` | a draft owner cannot load their own profile form | `proService.getMyProvider()` |
| `providers/pro_onboarding_provider.dart:85` | breaks **by construction** — the salon is draft precisely while that screen is used | `proService.getMyProvider()`, inside the existing `providerId != null` guard |
| `screens/provider/profile/pro_data_export_screen.dart:58` | RGPD export fails | `proService.getMyProvider()` |

Held by `mobile/test/unit/pro_reads_own_salon_test.dart`: **no pro-side file may
name `serviceLocator.providerService`, `getProviderById` or `loadProviderById`.**
That pin went red on three of the four and green on the preview — the preview
named no forbidden token, because its public fetch happened inside the *shared*
consumer screen. That is exactly the shape of a gate that passes while the worst
surface stays broken, so the preview is held behaviourally instead
(`salon_preview_test.dart` pumps it against a provider service that fails the
test if it is called at all). Recorded because the same blind spot recurs
whenever a source pin is scoped by directory and the defect lives across the
boundary.

**Verified against a running server, not only in tests** (2026-08-03,
`dart_frog dev`, a salon registered through `POST /auth/provider/register` so it
is genuinely `draft`). Two measurements, because the second is the only one that
proves anything:

1. **The documents match.** `GET /providers/{id}` and `GET /me/provider` were
   diffed field-by-field for the same draft salon: **`reviews` is the only key
   the public route adds, and every shared field is identical** — 31 keys,
   `status: draft` included. The « same document, so nothing is lost » claim is
   measured, not assumed.
2. **The read was then temporarily closed** — a two-line `status != 'active' →
   404` in `routes/providers/[id]/index.dart`, i.e. exactly what Decision C will
   do — and the server restarted. `GET /providers/{id}` → **404**, `by-slug` →
   404, and `GET /me/provider` → **200 with the complete document**. Before this
   PR that 404 was every one of the four pro surfaces, including the owner's own
   pre-publish preview; after it, the app never asks that door. The patch was
   reverted immediately (`git status` on `backend/` clean).

**One accepted delta.** `/me/provider` does not embed the 10-review preview the
public route adds, so `Provider.fromJson` yields `reviews: []` and « Avis »
renders empty inside the preview. Web ships the identical limitation (its
`ProProfile` type has no `reviews` field), so this is parity, not a new loss.

Web's pro preview is already correct — `SalonPreviewClient.tsx` uses
`/me/provider` and its comment says so explicitly. **Mobile is the outlier, and
that asymmetry is the real defect**: a pro app reading its own salon through an
unauthenticated public route is wrong whether or not the route is gated.

Web degrades in three more places for a suspended salon, none of them loud:
`lib/bff.ts:106` (`providerSummary` → every appointment card loses the salon's
**name**, which has no fallback), `app/api/me/favorites/route.ts:14` (the
favourite silently vanishes from the list **and** the RGPD export, and
`FavoriteButton` then renders un-favourited so a click re-adds it), and
`lib/booking/client.ts:110` (reschedule falls back to a default window — the
exact failure that file exists to prevent).

**A second leak this spec did not name:** `by-slug` excludes only `draft`
(`routes/providers/by-slug/[slug].dart:20`), so a **suspended** salon is
publicly readable by slug today — which is the route the web salon page uses.

So Decision C becomes its own slice, ordered behind: (a) moving the four mobile
pro reads onto `/me/provider` — **done, PR1b** — and (b) deciding how a
consumer's *own* appointment or favourite keeps resolving a salon they have a
relationship with — **answered and built above, PR1c**.

**A third blocker PR1c found, and it is (a) repeating one file over.** Both pro
« Avis » surfaces read the salon's own reviews through the PUBLIC
`GET /providers/{id}/reviews`: mobile through the *consumer* review service,
which sends no token at all, and web by forwarding whatever `providerId` the
browser sent. `pro_reads_own_salon_test.dart` was green on both, because every
token in its forbidden list named the provider *service* and this leak crossed a
different service. A `draft` salon **can** hold reviews — T53 erasure and T54
billing unpublish both write `status → draft` over a salon with history — so
closing that route would have 404'd the « Avis » page of exactly the owner being
asked to pay. `GET /me/provider/reviews` replaces it, membership-scoped through
the same primitive as `/me/provider`, and the pin's vocabulary grew.

**Two more public leaks that make the closure incoherent if left open**:
`GET /providers/{id}/reviews` (which also has **no provider read at all**, so an
unknown id returns `200 {items:[]}` — gating only the hidden case would make 404
mean « exists but hidden », the exact oracle T51 forbids), and
`GET /availability?providerId=`, which enumerates a hidden salon's bookable
slots. `POST /appointments/{id}/reschedule` also never checks salon status; its
route already defaults to 409, so the shipped codes map correctly once the
service refuses. **All four closed in PR1d**, plus the reschedule.

### PR1d — the doors, and who is told what

**One rule, asked at four doors.** `isPublicSalon` gates `/providers/{id}`,
`by-slug` and `/providers/{id}/reviews` in the routes; `/availability` is gated
**inside `SlotService`**, where the provider is already read — zero extra round
trips, and no route test needed a new stub, which is the whole reason for that
placement.

**Who gets the precise state, and who does not.** This is the same
anonymous-vs-relationship split PR1c drew, applied to refusals:

| caller | answer | why |
|---|---|---|
| `/availability`, anonymous | `provider_not_found`, identical to an unknown id | the only public door taking an arbitrary id in a query string; naming the state widens a one-valued channel into three |
| the consumer reschedule | **409 `provider_suspended` / `provider_not_published`** | the caller owns the booking — there is no oracle left to protect, and both sentences already ship |
| `/providers/{id}/reviews`, unknown id | **404**, moved from `200 {items:[]}` | otherwise the 404 means « exists but hidden » |

That last row makes a comment true that was false:
`appointment_detail_screen.dart` already claimed *« the server refuses the move …
hiding is a courtesy OVER the server gate, never instead of one »*. There was no
server gate. Now there is.

**Decision A, finally enforced on both salon paths.** Its rule reads *« a salon
that has not published yet owns its calendar; a salon that has been suspended
does not »*. `bookManual` obeyed it; `rescheduleByProvider` **never checked at
all**, so a suspended salon could still move its bookings and the written rule
was half true. PR1d refuses the suspended case there and keeps the draft one
working — watched as its own mutation, because the obvious way to close a door
is to close it on everyone.

**A second primitive, and the pin that keeps the two honest.**
`clientBookingRefusal` extracts the two-code split `book` had spelled inline
since row 82, because `reschedule` needs the identical answer — two call sites is
where a rule stops being a guard and becomes a spelling. It is held against
`isPublicSalon` by a **biconditional**: for every status,
`clientBookingRefusal(s) == null` ⟺ `isPublicSalon(s)`. That catches drift in the
**fail-open** direction too, which is the one nobody thinks to test: a fourth
status invented later must be public *and* bookable, or the two disagree the day
it lands.

**What the closure would have broken if it had shipped alone.** The mobile funnel
rendered « Une erreur est survenue. » beside a « Réessayer » that could never
succeed — row 82's headline sentence, back, in the funnel — because
`provider_not_found` fell to `_messageFor`'s default. Web's equivalent blamed the
connection (« Vérifiez votre connexion »). Both are fixed here rather than
recorded: a slice does not ship a defect it manufactured.

When it does land, a bare 404 is still wrong for someone who booked there last
month, so the **client** lands it softly (§6, cell 5).

### Verified against a running server — the REAL gate this time

2026-08-04, `dart_frog dev`, no temporary patch: the arc PR1c rehearsed, replayed
against the shipped code. Register a salon → service, Mobile Money, availability
→ admin activates → **a consumer books and favourites it while it is live** →
admin **suspends** it.

**The four doors:**

| door | | and an UNKNOWN id |
|---|---|---|
| `GET /providers/{id}` | **404** `{"error":"not_found"}` | **byte-identical** |
| `by-slug` | **404** | — |
| `/providers/{id}/reviews` | **404** `{"error":"not_found"}` | **byte-identical** |
| `/availability` | **404** `{"error":"provider_not_found"}` | **byte-identical** |

That third row is the one that needed the extra work: the route had no provider
read at all and answered `200 {items:[]}` for anything.

**The people with a relationship, at the same moment:**

| surface | |
|---|---|
| the client's `GET /appointments` | `Salon PR1d` · `suspended` · phone · Mobile Money number · `[Tresses]` · 30 min · window 45 |
| the client's `GET /me/favorites` | `[(Salon PR1d, suspended)]` — present and marked |
| the client's reschedule | **409 `provider_suspended`** — the state named, because they own the booking |
| the SUSPENDED salon's own reschedule | **409 `provider_suspended`** — Decision A's other half, which never checked before |
| the owner's `GET /me/provider` · `/me/provider/reviews` | **200** |

**And the closure did not over-reach.** A second, still-`draft` salon: its manual
booking succeeded, its own `rescheduleByProvider` **moved** that booking, and
`GET /providers/{id}` on it was **404** — a salon that has not published owns its
calendar while being invisible, which is the whole of Decision A in one
measurement.

## 6. The copy

The tense carries the whole distinction: **« pas encore »** for a salon that has
not published, **« ne … plus »** for one that has been stopped. None says
« Réessayez » — retrying fixes none of them — and each still offers a way out, per
SYSTEM.md:567 (*« an error state without a way out is a crash with better
manners »*).

| # | who | state | sentence | action | |
|---|---|---|---|---|---|
| 1 | consumer, booking | `provider_not_published` | « Ce salon n’accepte pas encore de réservations en ligne. » | « Découvrir des salons » | ✅ |
| 2 | consumer, booking | `provider_suspended` | « Ce salon ne prend plus de rendez-vous sur Myweli. » | « Découvrir des salons » | ✅ |
| 3 | pro, manual booking | `provider_not_published` | *— not reachable. Decision A makes this succeed.* | — | ✅ |
| 4 | pro, manual booking | `provider_suspended` | « Votre salon est suspendu. Contactez Myweli pour le réactiver — vos rendez-vous sont intacts. » | — | ✅ |
| 5 | consumer, salon page | 404 from the closed read | « Ce salon n’est plus disponible sur Myweli. » | « Découvrir des salons » | with C |

**The action is « Découvrir des salons », not « d’autres salons ».** The first
draft of this table minted a phrase that does not exist; the shipped one is in
`web/components/account/AccountClient.tsx`'s two empty states, pointing at `/`.
§17 says the product has one way to say a thing, so both surfaces reuse it —
`bookingErrorCta` on web and in `mobile/lib/core/utils/booking_error_cta.dart`,
each pinned against the other's label and destination.

**The action is deliberately absent from every other refusal.** §12 as amended
by this slice says the way out must *lead somewhere*: for `slot_unavailable` it
is another time at this salon, and for A14d's two window codes it is the jump
the slot picker already offers. `bookingErrorCta` returns `null` for all three,
and that null arm is what stops « offer a way out » collapsing into « put a
button on every error ».

**Why these words.** Cell 1 deliberately mirrors its A14d sibling « Ce salon
n’accepte pas encore les réservations à cette date. » (`web/lib/booking/window.ts:98-99`)
— same verb, same « pas encore », so the family reads as one voice. Cell 2 states
the fact and never the reason: the suspension reason is an audited admin field
(`admin_provider_service.dart:73-81`) and `docs/BACKEND.md:50` forbids leaking
internals. Cell 4 mirrors the one existing precedent for explaining an
unpublished salon to its owner, `pro_subscription_screen.dart:283-288`
(« Contactez-nous pour réactiver — vos données sont intactes. »); the
« intacts » clause is the reassurance that precedent proved is needed.

**Cell 3 is the point of Decision A.** Row 82's headline case does not get better
copy — it stops happening.

## 7. The gates

**① The split, red-first.** Book against a `draft` salon and assert
`provider_not_published` on `book`. Watched red by reverting the condition to the
single `||`.

**② The guard that stops the fix over-reaching.** A `suspended` salon must still
return `provider_suspended`, on **both** paths. Extends
`admin_provider_test.dart:73` to `bookManual`. Green throughout. The pair is
proven distinct by a second mutation: make `'suspended'` also map to
`provider_not_published` and **② goes red while ① stays green** (§21 row 78's
discipline).

**③ Decision A, both directions.** A `draft` salon's `bookManual` **succeeds** —
red today, since it currently returns `provider_suspended`. And a `suspended`
salon's `bookManual` still fails — the pair that stops A becoming « anyone may
book ».

**④ The 409 mapping, on both routes.** `provider_not_published` → **409**, not
400. Watched red by deleting the case: `routes/appointments/index.dart:169-172`
records in its own comment that a new conflict code without its own case
« silently ships as a bad request ».

**⑤ The closed read — SHIPPED in PR1d**, and it grew from one door to four.
See ⑩–⑲.

**⑥ The sentences.** One pin per surface reading the rendered French, so a copy
change cannot land silently. Shipped in PR2 (booking refusals) and PR1c (the
salon-state sentences: `salon_stopped_message_test.dart` and
`salon-stopped.test.ts`, which asserts the account copy is byte-identical to
`conflictMessage`'s so one fact cannot acquire two wordings).

**⑦ The enrichment survives the closure (PR1c).**
`appointment_enrichment_test.dart`: a **draft** salon's appointment enriches in
full — name, phone, deposit handle — and `providerStatus` says which state it is
in. Every other assertion in that file would pass on an implementation that
filtered hidden salons out of the enrichment, and that implementation would
reintroduce the silent degradation one layer down.

**⑧ The NULL trap, as a watched mutation rather than a comment (PR1c).**
`salon_visibility_test.dart` asserts a salon with **no `status` key** is public.
Re-spelling `isPublicSalon` as `status == 'active'` reddens exactly that
assertion and the explicit-null one, while the draft/suspended cases stay green
— the pair proving the two spellings are not the same rule. `booking_service.dart`
had recorded the same trap in prose for a year.

**⑨ Fail-if-called, twice (PR1c).**
`appointment_detail_artist_test.dart` used to stub `getProviderById` to FAIL and
assert the « Spécialiste » row simply vanished — *« facts stay null → OK »*. It
now pumps against a provider service that fails the test if it is touched at
all, which no implementation that still fetches can satisfy. Its sibling
`no-public-provider-read.test.ts` holds the web half, and proves its own matcher
fires on the exact line deleted from `bff.ts` — a regex pin that cannot
demonstrate that is green about nothing.

**⑩ The three read doors.** Isolated fixtures, never the shared mutable
`seedProviders`: `/providers/{id}` → 404 for draft and suspended, **200 for
active AND for a salon with no `status` key**; `by-slug` → 404 for suspended,
which is where that state stopped leaking. *Mutation:* restore the hand-rolled
`== 'draft'` → the suspended assertion reddens alone.

**⑪ Hidden and unknown are one 404 — the oracle argument, executable.**
`/providers/nope/reviews` → 404 (it returned `200 {items:[]}`), draft → 404,
`provider1` → 200; and on the detail route the two responses are asserted
**identical in status AND body**. *Mutation:* gate only the hidden case → the
unknown assertion reddens while the hidden one stays green.

**⑫ The pro's « Avis » survives.** `me_provider_reviews_test.dart` stays green,
untouched. If it reddens, the gate went into `ReviewsService.list`, which the
pro's own read shares — the wrong layer.

**⑬ `/availability`, gated inside the service.** Draft and suspended →
`provider_not_found`; `requireVisibleSalon: false` → slots. The four existing
route tests stay green **with no new stub**, which is the whole reason the gate
is in `SlotService` and not in the route.

**⑭ The consumer is told which state; the salon is not stopped.** Consumer
reschedule into a draft → `provider_not_published`, into a suspended →
`provider_suspended`, into a live one → ok. `rescheduleByProvider` into the
**same draft salon** → ok. *Mutation:* delete `requireVisibleSalon: false` from
the pro path → the salon assertion reddens while both consumer ones stay green.
**The pair that proves the closure did not eat Decision A.**

**⑮ Decision A's other half.** `rescheduleByProvider` on a **suspended** salon →
`provider_suspended` — red before PR1d, because that path never checked at all.
*Mutation:* remove the check → this reddens while ⑭'s draft case stays green.

**⑯ The 409 arm is load-bearing.** The reschedule route has no case for these
codes; its **default** is 409, unlike `POST /appointments`, whose default is 400
with a comment warning that a new conflict code « silently ships as a bad
request ». Asserted so a future refactor toward that shape goes red.

**⑰ The primitive pair.** `clientBookingRefusal(s) == null` ⟺ `isPublicSalon(s)`
across every spelling, including the no-key and explicit-null rows and an
unknown fourth status. *Mutation:* re-spell the new primitive `!= 'active'` →
three assertions redden, including the biconditional, while `isPublicSalon`'s own
five stay green.

**⑱ The three landing states.** Each of the salon detail, the booking hub and the
booking confirmation, pumped against `not_found` → the sentence + « Découvrir des
salons », **« Réessayer » absent**; against `network` → « Réessayer » present,
CTA absent; and — no `pumpAndSettle` — **frame one is the loader**, against a
future that never completes.

**⑲ Rebook parity.** A past visit at a stopped salon offers no « Réserver à
nouveau » and says why. Web's `rebookHref` had gated this since PR1c; this list
renders from the client's own appointments, which are deliberately unfiltered,
so it was the last live route onto a salon that is gone.

## 8. Sequencing

Two PRs, so parity is atomic rather than drifting the way A14d's did (web learnt
the codes; mobile never did).

1. **Backend + contract — shipped.** Decisions A and B; gates ①–④; the OpenAPI
   409 blocks for both booking routes — which also fixed the pro-manual
   description that was wrong (§2) — plus the T51 amendment, since that row's
   mitigation *was* the conflation (« booking refuses them like suspended »).
   **Decision C and gate ⑤ moved out**, see §5.
2. **Clients, all four surfaces at once.** The five cells of §6, gate ⑥, and
   `conflictMessage` gains an `audience` discriminator following
   `teamErrorMessage(code, ctx)` (`web/lib/pro/team.ts:36`) rather than a third
   injected string.

## 9. Explicitly out of scope — recorded, not absorbed

Each is real, each is separable, none is row 82:

- **The pro mapper's missing `slot_unavailable` case** (`api_pro_service.dart:779-796`)
  — the pro's *most* common manual-booking refusal still reads « Une erreur est
  survenue. ». Same switch, different defect.
- **Mobile never learnt `beyond_horizon` / `too_soon`** — A14d's asymmetry.
- **The mobile go-live card is not gated on status**
  (`dashboard_screen.dart:229`): an **active** and a **suspended** salon are both
  invited to go live, where web already gates on `status === 'draft'`
  (`AujourdhuiClient.tsx:156`). **The blocker is gone:** PR1c added `status` to
  `mobile/lib/models/provider.dart` (the favourites list needed it to mark a
  stopped salon). That does **not** reopen Decision B — B split the code because
  a client cannot infer WHY a *write* was refused from a document it fetched
  earlier; the field answers a different question, about a document it holds.
- **`getProviderBySlug` collapses 5xx and network into `notFound()`**
  (`web/lib/api/providers.ts:15-25`), and Next then caches that 404 for the whole
  revalidate window — so a 30-second backend blip serves a 404 for a **live**
  salon. PR1d bounds it to 5 minutes by lowering `revalidate`; the real fix is to
  throw on 5xx so the error boundary serves stale-or-error instead of a cached
  lie. Its own slice.
- **`enforceBookingWindow` and `requireVisibleSalon` always travel together.**
  Both are « this is a CLIENT rule » flags and `rescheduleByProvider` passes false
  for both. The honest long-term shape is one `SlotAudience.client | salon`;
  renaming now would churn four files and blur A14d's gate. **Trigger: the day a
  third caller-kind flag appears.**
- **`salonEntered` is derived two different ways.** Web reads
  `userId === 'manual'` (`bff.ts`), mobile reads `clientName != null`. One
  product fact, two client derivations — a candidate for the backend to own.
- **The review sheet's artist picker was a control that controlled nothing.**
  It asked « Avec quel professionnel ? » and sent the answer;
  `ReviewsService.submitForAppointment` derives `artistId`/`artistName` from the
  APPOINTMENT and discards it. It survived because the mock honoured it and the
  real backend never did. PR1c replaced it with a read-only line — the fix was
  forced by deleting the read that fed it, but the defect is independent and
  worth naming: **a mock that is more permissive than the server hides a lying
  control.**
- **The admin console's binary suspend** — « Réactiver » restores straight to
  `active` with **no publish gate** (`admin_provider_service.dart:63`), unlike
  `salon_subscription_service.dart:122-124` which does check.
- **The billing-unpublished third meaning.** A salon taken offline for non-payment
  is stored as `draft` and would read « pas encore en ligne » when it *was*
  online. Currently harmless — `SUBSCRIPTION_ENFORCEMENT` defaults to `off`
  (`dependencies.dart:419-420`) and the case has its own surface via
  `unpublishedForBilling`. **Documented trigger: revisit at switch-on**, when the
  sentence becomes a lie.
- **Owner preview of an unpublished salon page.** Decision C closes the public
  read; no preview path exists today (`by-slug` already excluded draft). A « see
  how your salon looks before publishing » feature is worth having and is not
  this spec.
