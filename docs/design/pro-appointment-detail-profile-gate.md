# The Pro appointment detail waits for its salon — design spec

**Status:** fix, web Pro dashboard (2026-10-16). Governs
`web/components/pro/ProAppointmentDetailClient.tsx`. Sits under the salon-time
seam ([timezone-salon-time.md](timezone-salon-time.md), multi-pays MP3) and the
shared error state (WEB-SYSTEM §12, `ErrorState`).

## 1. The defect (read on the code path, not assumed)

`/pro/rendez-vous/[id]` loads two things: the salon (`GET /api/pro/me` →
`getMyProvider`) and the appointment (`getProAppointment`, a search in
`GET /api/pro/appointments`). Before this fix, `load()` handled only a **401**
from `/me`. Any other failure — a 500, a 503 from a restart, a 403 — fell
through: `getMyProvider` returns `{ status, error }` with **no `profile`**, the
page ran `setProfile(me.profile ?? null)` and, the appointment list having
succeeded, **rendered the full page with no salon**.

With no salon, three things on that page are wrong, and one of them writes:

1. **« Reprogrammer » writes the wrong instant.** The picked date + time is the
   salon's wall-clock; `combineDateTime(date, time, profile?.provider.timezone
   ?? undefined)` received `undefined`, and `salonWallClockToUtc`'s default
   parameter turned that into `SALON_TZ = 'Africa/Abidjan'`. For a salon in
   Libreville (UTC+1), 10:00 was sent as `10:00Z` — 11:00 at the salon. The
   server re-validates the slot, not the intent: an hour-off booking that
   happens to be free is accepted.
2. **Every time shown is Abidjan's**, not the salon's (date row, « Arrivé à »,
   the « Client arrivé » same-day gate, the reschedule prefill and `min`).
3. **The role shape is an owner's.** `hasCap(undefined, …)` and
   `actionsForMembership(status, undefined)` read « no membership » as the
   legacy owner, so a Collaborateur saw every lifecycle button and
   « Reprogrammer » (the server still refuses — T40 — but the page lied).

Every other Pro page already gates on `me.status !== 200 || !me.profile` →
`ErrorState` (RendezVous, Aujourd'hui, ClientCard, Acompte, Avis, …). This page
was the one that did not.

## 2. The rule

> **A Pro page that renders salon data waits for the salon.** No `/me`, no
> page: the shared `ErrorState` with « Réessayer », exactly like its siblings.

And its corollary for this page's write:

> **« Reprogrammer » never computes an instant without the salon loaded.** A
> LOADED salon whose `timezone` is null is the server's own default
> (`backend/lib/src/salon_time.dart` — `locationOf(null)` → Abidjan), so the
> client's default agrees with it. An UNLOADED salon is not a salon with no
> timezone, and is never guessed.

## 3. States (unchanged except the first)

| `/me` | appointments | page |
|---|---|---|
| 401 | — | redirect `/pro/connexion` (unchanged) |
| **non-200 / no profile** | (not fetched) | **`ErrorState` « Rendez-vous » + « Réessayer »** — new |
| 200 | 401 | redirect (unchanged) |
| 200 | 404 (not in the list) | « Rendez-vous introuvable. » (unchanged) |
| 200 | other failure | `ErrorState` + « Réessayer » (unchanged) |
| 200 | 200 | the detail (unchanged) |

« Réessayer » re-runs `load()`. A 403 `not_a_member` / `forbidden` lands here
too; the shell's membership probe (`ProMembershipContext`, which re-fetches
`/me` on every navigation) owns the sign-out / rejoin gate / salon fallback —
the page does not race it, as on every sibling page.

A reload after a successful action (`await load()` after a lifecycle act or a
reschedule) follows the same table: a `/me` failure there shows the error
state rather than re-rendering without the salon.

## 4. The change

- `load()`: after the 401 check, `if (me.status !== 200 || !me.profile)` →
  `setLoadError(true)` and stop, **before** the appointment list is fetched
  (the ClientCard pattern). `setProfile(me.profile)` only on success.
- Render: `if (loadError || !profile)` → `ErrorState` — the guard narrows
  `profile` for everything below it, so no `profile?.` survives in the body.
- `reschedule()`: returns early when `!profile`; the instant is built from
  `profile.provider.timezone`.

No API, contract, copy or token change. No new component.

## 5. Tests (red first — `web/tests/pro-appointment-detail-profile-gate.test.tsx`)

- `/me` 500 with the list 200 → the error state (`role=alert` + « Réessayer »),
  and **no « Reprogrammer »**, no lifecycle button, no reschedule request, and
  the appointment list **not fetched**.
- `/me` 403, and a `/me` 200 with no profile body → the same.
- « Réessayer » after the failure, `/me` now 200 → the detail renders, in the
  salon's clock.
- `/me` 401 → still the redirect.
- Control: a **Libreville** salon (UTC+1) loads → « Reprogrammer » 2030-01-15
  10:00 sends `newDateTime = 2030-01-15T09:00:00.000Z` (passes before and
  after — it proves the test can see the timezone, so the red cases above are
  red for the right reason).

**Seen, not assumed:**

- Against the unfixed component: 4 red (the page rendered the full detail —
  owner actions and « Reprogrammer » — with no salon), the 401 and the control
  green. A throwaway probe on that code, `/me` 500 → « Reprogrammer » 10:00,
  sent `2030-01-15T10:00:00.000Z` — the control's own salon sends `09:00Z`.
- Mutations on the committed fix — each line has a guard that fires:

| mutation | caught by |
|---|---|
| the `/me` gate in `load()` dropped (render guard kept) | the test — 3 red, on the list being fetched. The render guard alone also hides the page, so without the `listReads` assertion this mutation survived; it was added after watching it survive. |
| gate and render guard both dropped (the old code) | the test — 4 red |
| `\|\| !profile` dropped from the render guard | `tsc` (CI `npm run typecheck`) — `profile` is possibly null in the body |
| `!profile` dropped from `reschedule()` | `tsc` — same |

## 6. App parity (mobile, read, not run)

The app's detail screen (`pro_appointment_detail_screen.dart`) has no
« Reprogrammer »; the app's reschedule lives in the journal
(`pro_journal_screen.dart` `_reschedule`), and reads
`ProAuthProvider.salonTimezone` = `_activeSalon?.timezone`. `_activeSalon` is
set only from a successful `/me`; on a cold start the session is restored from
cache and `/me` is fetched by `refreshMembership()`, whose failure branch
« keeps the cached shape » — but the cached shape holds the membership, **not
the salon**, so `_activeSalon` stays null and `salonDateTime(…, tz: null)`
falls back to Abidjan. Same class of defect, different surface: tracked as its
own follow-up (Flutter, `myweli-dev-guardrails`), not in this change.

## 7. Rollout

Web only; ships with the next web deploy (Vercel). No backend change, no
migration, no flag.
