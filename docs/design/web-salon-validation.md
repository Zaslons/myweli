# The website's Pro space under MyWeli's validation (B0.18, part 4a)

| | |
|---|---|
| **Status** | **Approved 2026-11-13**: the web details [salon-go-live-approval.md](salon-go-live-approval.md) §6 leaves open, written before the code; the owner answered §9's three questions the same day (each recommendation taken) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-13 |
| **PRD ref / phase** | FR-PRO-ONB-001 (go live) · V1 |
| **BACKLOG** | B0.18 (decisions 120, 123–133) |
| **Parent spec** | [salon-go-live-approval.md](salon-go-live-approval.md) §6.1–§6.4, §8.4, §9.1 item 4, §9.2. This file adds only what the parent leaves open; where they differ, the parent wins and this file is corrected |
| **Related** | [web-pro-golive-signup-like-app.md](web-pro-golive-signup-like-app.md) (the checklist) · [web-pro-notifications.md](web-pro-notifications.md) §3.4–§3.5 (`?salon=`, the route table) · [web-pro-browser-push.md](web-pro-browser-push.md) §5 (the service worker) · [web-pro-export-completeness.md](web-pro-export-completeness.md) (the export) · [web-true-sentences.md](web-true-sentences.md) |
| **Skills checked** | myweli-web-guardrails · myweli-dev-guardrails · myweli-verification-guardrails |

## 1. Goal & scope

**4a ships before the backend deploy and reads both servers.** Production's
backend is pre-B0.18 on the day 4a merges: publish answers 200 and goes live
at once, and `/me/provider` has no `validation` key. The new backend answers
202 for a request and sends `validation` (`null` when never asked).

The one rule: **the new states key on the `validation` key being present.**

- **Absent** (a server before B0.18) → today's screens and words, unchanged.
- **Present** (`null` or an object) → the states of §6.1.
- **Publish** branches on the status, whatever the page was loaded from:
  200 = live (today's « 🎉 »), 202 = a request (the new message and state).
  A 202 can reach a page loaded from the old server if the backend is
  deployed in between; the page then follows the 202.

4a makes no new public claim: no public page changes (4b does).

**In scope (4a):** `GoLiveCard`, `AujourdhuiClient`, the sidebar's salon rows,
`/pro/apercu`'s banner, `/pro?salon=`, `proWebRouteFor`, the service worker,
the refresh points, R8, the Pro data export, the e2e stub and the tests.

**Out of scope:** the public pages (4b); the Pro app (PR 3, which also owns the
app's export half); a feed icon for `salonValidation` (it keeps the bell, as
every type without one does — web-pro-notifications §3.3).

## 2. The state, derived once

`lib/pro/salon-validation.ts` holds the derivation and every French string of
this file, so the copy has one home and one ban test (§7).

`goLiveState(status, validation)`, first match wins:

| # | Condition | State |
|---|---|---|
| 1 | `validation === undefined` | `legacy` (today's screens) |
| 2 | `status === 'suspended'` | `suspended` |
| 3 | `status === 'active'` (or no status) | `live` |
| 4 | `validation === null` | `neverAsked` |
| 5 | `state === 'pending'`, or `approved` with `wentLive` false | `pending` |
| 6 | `state === 'refused'`, `refusal.final` true | `refusedFinal` |
| 7 | `state === 'refused'` | `refused` |
| 8 | `approved`, `wentLive`, `offerLive === true` | `offlineRepublish` |
| 9 | `approved`, `wentLive`, `offerLive === false` | `offlineUnpaid` |
| 10 | `approved`, `wentLive`, `offerLive` absent (not the owner) | `offline` |

`suspended` comes before `live` and the validation: a pending salon an admin
suspends reads « Suspendu » (submit refuses it anyway). `live` comes before the
validation: an `active` salon is public whatever its row says (a rollback,
§9.3 of the parent).

## 3. Copy

### 3.1 Approved words (parent §6.1, §4.3, Q9 — word for word)

| State | Sidebar line | Card banner title | Card banner text | Action |
|---|---|---|---|---|
| `neverAsked` | « Brouillon — pas encore en ligne » | (none: today's card heading, §3.3) | the checklist; the hint « Complétez les étapes essentielles pour demander la mise en ligne. » | « Demander la mise en ligne » |
| `pending` | « En cours de validation » | « En cours de validation » | « Nous examinons votre salon avant sa mise en ligne. Nous vous préviendrons dès que c’est fait. » | none: « Demande envoyée le {date} » |
| `refused` | « Mise en ligne refusée » | « Mise en ligne refusée » | the code's sentence; the note on its own line; « Modifiez votre salon, puis renvoyez-le pour validation. » | « Renvoyer pour validation » |
| `refusedFinal` | « Mise en ligne refusée » | « Mise en ligne refusée » | the code's sentence; the note | none |
| `live` | « En ligne » | — | — | — |
| `offlineUnpaid` | « Plus en ligne » | « Votre salon n’est plus en ligne » | « Votre salon n’est plus visible des clients. Contactez-nous pour réactiver — vos données sont intactes. » (« Mon abonnement »'s billing sentence) | the billing pointer: a link « Mon abonnement » (the page's own title) to `/pro/abonnement` |
| `offlineRepublish` | « Plus en ligne » | « Votre salon n’est plus en ligne » | « Vous pouvez le remettre en ligne. » | « Remettre en ligne » |
| `offline` | « Plus en ligne » | — (no card: not the owner) | — | — |
| `suspended` | « Suspendu » | « Votre salon est suspendu » | « Contactez MyWeli pour en savoir plus. » | none |

**The refusal sentences** are the backend's (`salon_validation_copy.dart`),
copied, and pinned equal to it by a test that reads the Dart file:

- `incomplete_info`: « Certaines informations du salon sont incomplètes ou peu claires. »
- `photos`: « Les photos ne montrent pas assez clairement le salon et son travail. »
- `unconfirmed`: « Nous n’avons pas pu confirmer l’existence de ce salon. »
- `outside_ci`: « MyWeli n’est pas encore disponible dans votre pays. Si votre salon est en Côte d’Ivoire, écrivez-nous depuis « Aide & Support ». »
- `test_salon`: « Ce salon est un salon de test : il ne sera pas mis en ligne. »
- `other`: the note alone.

**After a request (202):** « Demande envoyée. Nous vous préviendrons de la
décision. ». **After a 200:** today's « 🎉 Votre salon est en ligne ! Il
apparaît maintenant dans les recherches. », said only for a 200.

**The date** in « Demande envoyée le {date} » is `formatDateFr` in the salon's
timezone (« 13 novembre 2026 »). No line when `submittedAt` is absent.

### 3.2 Words the owner approved for the web (§9, 2026-11-13)

- `/pro/apercu`'s banner per state (§4.4).
- R8's sub-line under « Profil de l’entreprise »: « Choisissez la commune dans la liste » (§5).

### 3.3 Kept as they are

- The card heading for `legacy` and `neverAsked`: « Votre salon n’est pas
  encore en ligne » and « Complétez votre profil pour apparaître dans les
  recherches et recevoir des réservations. ». Both stay true: completing is
  needed, and the hint under the button names the request.
- `legacy`'s button « Mettre en ligne » and hint « …pour mettre votre profil en
  ligne. ». Against the old server, the publish does put it online.
- The 409 lines: « Choisissez votre offre avant la mise en ligne. » with
  « Choisir mon offre », and « Certaines étapes ne sont pas terminées.
  Vérifiez la liste. ». The latter predates B0.18 and stays outside the
  validation copy the « vérif » ban covers.

## 4. Surfaces

### 4.1 `GoLiveCard` (the owner's card on « Aujourd’hui »)

Shown, as today, to `salon.publish` holders while the salon is `draft`; and,
with the new server, while it is `suspended` (§9 Q2): the banner alone. Layout, top to bottom:

1. **The state banner** for `pending`, `refused`, `refusedFinal`,
   `offline*` and `suspended`: the KYC page's banner (`VerificationClient`),
   a tinted box with a title and its lines. Tones: `pending` neutral
   (`border-border bg-surface`), `refused`/`refusedFinal`/`suspended` error,
   `offline*` warning. The note is plain text on its own line (React escapes
   it); a long word wraps (`break-words`). `legacy` and `neverAsked` keep the
   card heading instead (§3.3).
2. **The checklist,** unchanged, in every draft state: each step stays editable
   while pending (parent §6.2), and a republish re-runs the gate.
3. **The action row:** the state's button (`neverAsked`, `refused`,
   `offlineRepublish`, `legacy`), enabled when the server's five are done; or
   « Demande envoyée le {date} » (`pending`); or the « Mon abonnement » link
   (`offlineUnpaid`); nothing for `refusedFinal` and `suspended`. « Aperçu de
   ma page » stays in every state.
4. **The hint** only beside a button that is disabled.
5. **The error line** (`role="alert"`), as today.

**Publish outcomes:**

| Answer | What the card does |
|---|---|
| 200 | `onPublished('live')`: today's « 🎉 » line; the salon `active` |
| 202 | `onPublished('requested', validation)`: the card takes the body's `validation`; the line says « Demande envoyée… » when that state is `pending` (or finishing); then both reads (§4.6) |
| 409 `validation_refused_final` | re-read `/me/provider`: the card shows the final refusal and its reason (the button was stale) |
| 409 `incomplete` + `offer` | today's offer line |
| 409 `incomplete` | today's « Certaines étapes… » line |
| 403, 0, 5xx | today's `salonRefusalMessage` lines |

`publishSalon` reads a 202's body (`validation`, possibly `null`) and returns
`{ ok, status, validation? }`; an unreadable 202 body is still `ok` (the
request is recorded) and the page re-reads.

### 4.2 `AujourdhuiClient`

- Keeps `validation` beside `profile` (from `getMyProvider`), resets it with
  the page (a salon switch remounts it).
- Renders the card for `draft`, branching inside it; and for `suspended`
  with the new server (§9 Q2).
- The `role="status"` line, already in the DOM before it speaks, says « 🎉 … »
  on a 200, « Demande envoyée… » on a 202.

### 4.3 The sidebar's salon rows

The rows of « Mes salons » (the switcher's menu) put the state **on its own
line**, under the role, as the app's picker does (at 200% text a
« role · state » line cuts the state off). `legacy` keeps today's
« Propriétaire · Brouillon ». The single-salon block shows no state: there is
no switcher there today, and the owner reads the state on the card.

### 4.4 `/pro/apercu`'s banner

The preview reads `getMyProvider` itself (it sits outside the dashboard
shell). `legacy` keeps today's three sentences. With the new server (approved
by the owner, §9 Q1):

| State | Banner |
|---|---|
| `neverAsked` | today's « Aperçu — votre salon n’est pas encore en ligne. Voici ce que verront vos clients. » |
| `pending` | « Aperçu — votre salon est en cours de validation. Voici ce que verront vos clients. » |
| `refused` | « Aperçu — la mise en ligne de votre salon a été refusée. Voici ce que verront vos clients une fois votre salon validé. » |
| `refusedFinal` | « Aperçu — la mise en ligne de votre salon a été refusée. » |
| `offline*` | « Aperçu — votre salon n’est plus en ligne. Voici ce que verront vos clients. » |
| `suspended` | « Votre salon est suspendu. Contactez MyWeli pour en savoir plus. » |
| `live` | today's « Votre salon est en ligne — ceci est votre page publique. » |

### 4.5 `/pro?salon=`, the notice's landing

The backend's push and feed row carry `/pro/onboarding?salon={id}`; its
e-mail opens `https://myweli.com/pro?salon={id}`.

- **`proWebRouteFor`:** `/pro/onboarding?salon={s}` → `/pro?salon={s}`;
  `/pro/onboarding` → `/pro`. The feed row becomes a link.
- **`/pro` reads `?salon=`** (the page passes it to `AujourdhuiClient`) and
  switches once, with the booking detail's guard: a module-level set of the
  salons this page already tried, so a server that does not take the switch
  cannot send the page round in circles.
  - Already on that salon → nothing to switch.
  - `switched` → the shell re-keys; the page loads under that salon.
  - Refused or no answer → the page loads the **current** salon's day, with
    the detail's sentence above it (`role="alert"`): « Changement impossible —
    votre accès à ce salon a peut-être été retiré. », or « Pas de connexion.
    Réessayez. ». The app goes to « Accueil » on a failed switch; on the web
    `/pro` is « Accueil ».
  - **Then the `?salon=` is dropped from the address** (`router.replace('/pro')`).
    Without this, a later switch from the sidebar would remount the page under
    the old address and switch back.
- **Signed out:** the page's 401 goes to `/pro/connexion?salon={s}`; the login
  reads `?salon=` (only `[A-Za-z0-9_-]{1,128}`, never text) and lands on
  `/pro?salon={s}`. A two-salon owner who opens the e-mail on a signed-out
  browser then still lands on the right salon.

### 4.6 Refresh points

`/me/provider` (the page's own read) and `/me/salons` (the sidebar,
`refreshSalons`) are re-read:

- after a submit, 200 or 202;
- when « Aujourd’hui » loads (`/me/salons` only; the page reads `/me` anyway);
- when a `salon.validation.*` push arrives while « Aujourd’hui » is open: the
  service worker's message now carries the push's `event`, and the page re-reads
  both, quietly (no skeleton);
- on a notice tap (it lands on `/pro?salon=`, which loads).

« Ajouter un salon » needed no change: it lands on `/pro`, whose load now
re-reads `/me/salons`. Before, it never did, so the new salon's row (and now
its line) was missing from « Mes salons » until a reload.

### 4.7 The service worker

`public/pro/push-sw.js` learns the two events. The link stays **built**, never
read from `route` (browser-push §5):

- `salon.validation.approved` / `.refused` with a `providerId` matching the id
  pattern → `/pro?salon={providerId}`; without one → `/pro`.
- Tag `salon.validation:{providerId}`, so a second decision on a salon replaces
  the first (approved after refused included).
- The click guard accepts `/pro?salon={id}` and `/pro` besides the booking
  links; anything else still opens the bookings list.
- Every push posts `{ type: 'myweli-pro-push', event }` to the open tabs
  (`event` only when it is a string).

## 5. R8: « Profil de l’entreprise » follows the server

The server (`SalonProvisioningService.publishGate`) wants description, address
and commune non-empty, **and** `areaId` set or the commune matching a seed area
by slug (`seedAreaForCommuneName`: `slug == slugify(commune)` or
`slugify(name) == slugify(commune)`). The web's `slugify` is the backend's
twin.

`publishChecklist` gains the localities tree (`useLocalities`, which
`GoLiveCard` already can read):

- `areaId` set → the area is valid (the server only ever stores a resolved one);
- else the commune must match an area of the tree, as above;
- **the tree not read** (loading or failed) → today's rule: the server decides,
  and its 409 says so. Blocking a valid salon on a failed read would be worse.

When description, address and commune are filled and the area is not valid,
the step stays « à faire » with the sub-line « Choisissez la commune dans la
liste » (§9 Q3).

## 6. The Pro data export

`buildProviderDataExport` gains a top-level `validation`, beside `salon` (as
`/me/provider` puts it beside `provider`), **only when the server sent the key**:

```
validation: null                     // never asked
validation: {
  state, submittedAt, decidedAt, wentLive,
  refusal: { code, final, note, reason } | null   // reason: the sentence, null for `other`
}
```

The values are the wire's, as everywhere in the file; `reason` is the one
French value, the sentence the salon reads. `offerLive` is billing state and
stays out. The source is the profile Profil already read (no new read: the
export's sections and their failure sentence do not change).

## 7. Tests

**Unit (Vitest):**

- `salon-validation.test.ts`: `goLiveState` over every row of §2; the
  refusal sentences equal `backend/lib/src/validation/salon_validation_copy.dart`
  (read and parsed, comments stripped); the « vérif » ban over every string the
  module exports and every card/banner rendered in §3.1's states.
- `pro-golive-card.test.tsx`: each state's banner, button, hint and date;
  `legacy` unchanged; 200 vs 202 vs 409 final.
- `pro-aujourdhui-validation.test.tsx` (new): the dashboard in every state;
  the 202 line vs the 200 line; the push re-read; `?salon=` switching once
  (two salons: switched, refused, offline, already there, the address dropped,
  a later sidebar switch not pulled back).
- The sidebar rows (`pro-sidebar-switcher.test.tsx`), the preview banner, R8
  (`onboarding`), `proWebRouteFor`, the service worker (`pro-push-sw.test.ts`),
  the export, the login's `?salon=`, and `pro-api-network.test.ts`'s
  `publishSalon` row (`payload: ['validation']`).

**E2E (the stub becomes a B0.18 server):**

- `/me/provider`, `/me/salons` and publish carry `validation`; `p1` and `p3`
  stay never asked (`null`); publish answers 202, records `pending` and no
  longer mints a trial; 200 for an active salon and for the republish; 409
  `validation_refused_final`.
- `POST /__stub/validation` stands in for the admin: approve, refuse, seed a
  state, reset (the stub's existing `/__stub/*` convention).
- Go-live: p1 submits → 202 → « En cours de validation »; the stub approves →
  live; reset after.
- The refused-by-country path on its own identity and salon (a dedicated
  e-mail, as `FRESH_LISTS_EMAIL` does), so no other spec sees it: refused
  `outside_ci` (final, no button); refused `photos` → « Renvoyer pour
  validation » → pending.
- Axe on the pending and refused cards.

Every new guard is watched red once, on committed code, and the commit says how.

## 8. Rollout & verification

- **No staging backend exists** (retired 2026-10-07), so before merge 4a is read
  on the stub (new server) and in unit tests (both servers).
- **After the merge** (Vercel deploys `main`): the served bundle carries the new
  strings; `/pro/push-sw.js` serves the new worker; production's pre-B0.18
  backend still gets today's screens (`validation` absent). Reading a signed-in
  Pro page needs an owner's session; what can't be read from here is marked so.
- Then the backend deploy is the owner's to approve (parent §9.2 step 3), and
  4b waits for it.

## 9. The owner's answers (2026-11-13)

- **Q1. The preview's banner** (§4.4): « Use these sentences ». The table of
  §4.4 is approved word for word.
- **Q2. A suspended salon on « Aujourd’hui »:** « Show it ». Parent §6.2 said
  both « the card for `draft` » and « one branch per state »; the owner's
  dashboard shows §6.1's suspended banner (« Votre salon est suspendu » ·
  « Contactez MyWeli pour en savoir plus. ») to `salon.publish` holders, with
  the new server only. No checklist and no button under it: the admin's
  restore decides.
- **Q3. R8's sub-line:** « Choisissez la commune dans la liste » under
  « Profil de l’entreprise », only when description, address and commune are
  filled and the commune is not from the list.
