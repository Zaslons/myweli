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

`GET /providers/{id}` currently returns **draft and suspended** salons
(`routes/providers/[id]/index.dart:27-35`), while `by-slug` excludes draft
(`by-slug/[slug].dart:19-20`) and discovery excludes both. That contradicts the
contract's own promise that public reads only ever return `active`
(`openapi.yaml:4207-4212`), and it is the route by which a favourite reaches a
banned salon.

**The read closes for both**, bringing the route in line with the contract it
already violates. Verified safe: the pro reads its own salon through
`/me/provider` and `PATCH /providers/{id}` (authenticated, ownership-checked),
**never the public `GET`**; web uses `getProviderBySlug` only; admin has its own
`/admin/providers/…` routes.

A bare 404 is wrong for someone who booked there last month, so the **client**
lands it softly (§6, cell 5). The booking write keeps its own sentence as defence
in depth for a session that already had the page open.

## 6. The copy

The tense carries the whole distinction: **« pas encore »** for a salon that has
not published, **« ne … plus »** for one that has been stopped. None says
« Réessayez » — retrying fixes none of them — and each still offers a way out, per
SYSTEM.md:567 (*« an error state without a way out is a crash with better
manners »*).

| # | who | state | sentence | action |
|---|---|---|---|---|
| 1 | consumer, booking | `provider_not_published` | « Ce salon n’accepte pas encore de réservations en ligne. » | « Découvrir d’autres salons » |
| 2 | consumer, booking | `provider_suspended` | « Ce salon ne prend plus de rendez-vous sur Myweli. » | « Découvrir d’autres salons » |
| 3 | pro, manual booking | `provider_not_published` | *— not reachable. Decision A makes this succeed.* | — |
| 4 | pro, manual booking | `provider_suspended` | « Votre salon est suspendu. Contactez Myweli pour le réactiver — vos rendez-vous sont intacts. » | — |
| 5 | consumer, salon page | 404 from the closed read | « Ce salon n’est plus disponible sur Myweli. » | « Découvrir d’autres salons » |

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

**⑤ The closed read.** `GET /providers/{id}` → 404 for draft and for suspended;
still 200 for active. Red today on all three.

**⑥ The sentences.** One pin per surface reading the rendered French, so a copy
change cannot land silently.

## 8. Sequencing

Two PRs, so parity is atomic rather than drifting the way A14d's did (web learnt
the codes; mobile never did).

1. **Backend + contract.** Decisions A, B, C; gates ①–⑤; the OpenAPI 409 blocks
   for both booking routes — which also fixes the pro-manual description that is
   wrong today (§2).
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
  (`AujourdhuiClient.tsx:156`). Fixing it needs `status` on
  `mobile/lib/models/provider.dart` — the model change this spec otherwise avoids.
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
