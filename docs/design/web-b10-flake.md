# B10 — the e2e suite tells the truth about itself

> **Row:** [WEB-SYSTEM.md §15 row 30](WEB-SYSTEM.md) · **Surface:** `web/tests/e2e/`
> **Guardrails:** [WEB.md](../WEB.md) · [WEB-SYSTEM.md](WEB-SYSTEM.md) · [SYSTEM.md](SYSTEM.md)
> **Preceded by:** [B9 — the tab strips](web-b9-tabs.md), which is where the flake was measured and parked.

---

## 1. Why this slice comes first

B9 spent three full baseline runs establishing that a suspected regression was
actually the standing weather. That is the cost of an unreliable gate: **a red
run carries no information**, so every red has to be re-measured before it can
be believed, and the cheapest response — re-run it — is also the one that
trains everyone to stop reading failures.

Every slice after this one is verified by this suite. Fixing the gate before
relying on it is the same discipline as watching a gate fail before trusting it
green.

---

## 2. What row 30 said, and what is actually true

Row 30 recorded three things. **Two of them are wrong**, and the correction
matters because each pointed at a different fix.

| Row 30 said | Measured |
|---|---|
| "the suite flakes ~2-in-3" | **True, but only locally with a surviving stub.** In the CI configuration it is **5 red / 29 runs = 17.2%** (6 workers). See §3.3 for why the two numbers differ by 4×. |
| "probably a missing `await expect(...)`" | **False, for both named suspects.** `booking.spec.ts:104` and `_auth.ts:63,75` already use `await expect(...)`. The real causes are a product-code race (§4.1) and a cross-file write-write conflict (§4.2) — neither is a wait. |
| "`proProvider` may be shared" | **False.** `stub-api.mjs:406` deep-clones it (`JSON.parse(JSON.stringify(provider))`), so the public provider `booking.spec.ts` reads is insulated from `pro.spec.ts`'s catalogue edits. |

A fourth thing row 30 did not know: **the largest single contributor is not
within-run interference at all.** It is state surviving *between whole suite
runs*, which `reuseExistingServer: !process.env.CI` enables locally and CI never
has. That is the 2-in-3.

---

## 3. The measurement

### 3.1 Per-test failure rates — 29 runs, `npm run e2e` as CI runs it

Default 6 workers, fresh server processes each run. One further run was excluded
as a harness failure, not a test failure (`Process from config.webServer was not
able to start`).

| test | file:line | failures | rate |
|---|---|---|---|
| `time-first: l'heure choisie survit ou se libère selon la durée` | `booking.spec.ts:85` | **3** | **10.3 %** |
| `the Réseau arc: switch the offer → the CTA appears → create → land on the new draft, switched` | `salons.spec.ts:70` | **2** | **6.9 %** |
| `pro detail: open a pending booking → Accepter → Confirmé` | `pro.spec.ts:54` | 1 | 3.4 % |
| `disponibilités: edit hours + save` | `pro.spec.ts:158` | 1 | 3.4 % |
| `profil: edit + save; acompte: enable + save` | `pro.spec.ts:212` | 1 | 3.4 % |
| `médias: manage photos (remove + save) + upload a new one` | `pro.spec.ts:242` | 1 | 3.4 % |
| `clients: list → search → card → note → tags` | `pro.spec.ts:274` | 1 | 3.4 % |
| `journal grid: Journée is the default view` | `pro.spec.ts:357` | 1 | 3.4 % |
| `« Vérification » : upload des documents KYC` | `pro.spec.ts:569` | 1 | 3.4 % |
| `go-live: le brouillon complet se met en ligne` | `pro.spec.ts:610` | 1 | 3.4 % |
| **the other 110 tests** | — | **0** | **0 %** |

**Read this table carefully: the eight `pro.spec.ts` rows all failed in one
single run, together.** They are not eight flaky tests; they are one polluted
run (§3.3). **Two tests are genuinely flaky run-to-run** — `booking.spec.ts:85`
and `salons.spec.ts:70` — and they have different causes.

### 3.2 Order, not load

| condition | runs | result |
|---|---|---|
| `--workers=1` | 2 | **120 passed, zero failures** |
| 8 CPU burners (load ≈ 7.8) | 1 | 120 passed |
| 24 CPU burners (load 19 → **190**) | 1 | 120 passed |
| `booking.spec.ts --fully-parallel --repeat-each=4` (84 executions) | 3 | 1 failure at `booking.spec.ts:107` |

Two clean results. **`--workers=1` removes the flakes**, which is what
cross-file interference looks like. And **raw CPU pressure does not cause
them** — at load average 190 the suite was 3× slower and still 120/120, because
uniform pressure slows Playwright's action dispatch as much as it slows the
server and so preserves relative timing. What breaks things is queueing latency
at the single shared Next/stub process while the next action fires at full
speed, which only parallel workers produce.

The `--repeat-each` result is the one that separates the two causes:
`booking.spec.ts:85` still fails when it is the *only* file running, so it is a
**within-test race**. `salons.spec.ts:70` never reproduced that way — it needs
its co-conspirator.

### 3.3 The stub accumulates, and that is the 2-in-3

`tests/e2e/stub-api.mjs` is one long-lived Node process holding module-level
mutable state. **There is no reset of any kind**: no endpoint, no `beforeEach`,
no per-run seeding. The `team-reset` "test-only DELETE" documented in the
comment at `stub-api.mjs:470` **does not exist** — a repo-wide grep finds no
implementation and no caller.

Three full suite runs against one deliberately-kept-alive stub:

| run | result |
|---|---|
| S1 | **3 failed** / 117 passed |
| S2 | **14 failed** / 106 passed |
| S3 | **16 failed** / 104 passed |

Monotonic, and the errors are unambiguously state rather than timing:

- `pro.spec.ts:226` — `Commune` had value `"marcory"`, a previous run's profil edit
- `pro.spec.ts:257` — `main img` count 4, a previous run's média upload
- `pro.spec.ts:586` — a KYC button enabled by a previous run's uploads
- `pro.spec.ts:618` — « Votre salon n'est pas encore en ligne » absent; a previous run published it
- `account.spec.ts:27` — landed on `appt3`; a previous run cancelled `appt1`
- `team.spec.ts:20` — « Invitez votre équipe » gone; a previous run added members
- `multi-pays.spec.ts:68` — `Wave` option count 0; a previous run switched the salon's country

**This is the ~2-in-3 row 30 recorded**, and B9 almost certainly measured it
with a surviving stub. It is a **local-only** hazard: CI sets `CI=true` →
`reuseExistingServer: false` → fresh processes per job. It still has to be
fixed, because the local suite is what every slice is developed against, and a
harness that degrades run over run teaches its user to stop believing it.

### 3.4 What `retries: 1` is hiding

`playwright.config.ts:17` is `retries: process.env.CI ? 1 : 0`, and
`.github/workflows/ci.yml`'s `web-e2e` job has no flake gate.

**Measured:** 5 of 29 runs had ≥1 failure. Without retries, a bit over **1 in 6**
CI runs would have gone red. A retry re-runs only the failed test, alone, in the
quiet tail of the job — precisely the `--workers=1` condition that produced zero
failures in two full runs. So the retry-pass probability is near 1 and the
observed red rate collapses to roughly **0–2 %**.

Two honesty notes:

- **CI runs 2 workers, not 6** (`ubuntu-latest` is 4 vCPU). Since the driver is
  worker parallelism, the true CI rate is **lower** than 17.2 %. That number is
  a local measurement and is not quoted as CI's.
- **It is not fully hidden.** Playwright prints `N flaky` on a fail-then-pass.
  The line exists and nothing asserts on it, so the job exits 0 and it scrolls
  past. The information was already there and already ignored — one step earlier
  than row 30 assumed.

---

## 4. The causes, and the fix for each

### 4.1 `booking.spec.ts:85` — a stale-closure state clobber. **A product bug.**

`components/booking/BookingFlow.tsx` has exactly one generation guard, on
`loadSlots` (`:151`, `:154`) — the app's `slotsRequestId` pattern, ported. The
async pipelines that write `s` have none:

```ts
async function settle(state: HubState) {
  let next = await revalidateSlot(state);   // ← /availability round trip
  …
  next = advance(next, hasArtists);
  setS(next);                                // ← writes a pre-await snapshot
}
```

The race, step by step:

1. `booking.spec.ts:95` ticks a service → `onToggleService` calls `setS` **synchronously**, then starts `settle`.
2. `booking.spec.ts:96` `await expect(Confirmer).toBeEnabled()` passes **immediately**, off that synchronous write — it does not wait for `settle`.
3. `booking.spec.ts:103` clicks « Prestations » → `onOpenSection` sets `activeSection: 'services'`. (There is no `'prestations'` value — `Section` is `'services' | 'artist' | 'time'`; « Prestations » is the French label of the `'services'` card.)
4. If `settle`'s fetch resolves *after* step 3, its trailing `setS(next)` overwrites `activeSection` from a snapshot taken before the click. The Prestations card collapses and the variant chips — rendered only inside it (`BookingFlow.tsx:467`) — unmount.

Both observed failures are that unmount: a `toHaveAttribute` timeout on
`/^Moyen ·/` and a click timeout on `/^Long ·/`.

Ruled out: `/availability` (`stub-api.mjs:604-619`) is a pure function of
date/artist/duration and bookings never consume slots, so this is not stub state.

**The first fix was wrong, and the review caught it.** The obvious move —
*one* generation for the whole component, every post-`await` write dropped once
the user moves on — is what B10 shipped first. It is wrong because a pipeline
decides **two unrelated things**:

| | produced by | touches |
|---|---|---|
| the server's verdict on the chosen time | `revalidateSlot` → `clearSlot` / `autoPickSlot` | `slot`, `date`, `autoPicked` |
| the auto-advance | `advance` | `activeSection` |

Those field sets are **disjoint**. Losing the auto-advance to a newer user
intent is correct — the user said where they want to be. Losing the verdict is
not: it is the server's answer to *"does 10:30 still fit?"*, and no user action
makes it untrue. Dropping both together meant a header tap during the round
trip kept a time the salon can no longer honour, with « Confirmer » still
enabled.

That is **worse than the bug it replaced.** The original defect collapsed a
card; this one produces a wrong booking. And on the `onVariant` path the server
does not catch it either — `createBooking` sends no hair length, so the backend
re-derives the duration from the service default, accepts 10:30, and the chair
is under-blocked. The user sees no error at all.

`slotsRequestId` is a fair precedent for `loadSlots`, which guards a **cache**;
a cache is always safe to discard. `s` is not a cache.

**Fix — two generations.** `selectionReq` is bumped by anything that changes
*what is being booked*; a verdict computed for a selection the user has since
changed is genuinely stale and is dropped. `navReq` is bumped by anything that
changes *where the user is*; it outranks the auto-advance, and the verdict
travelling with it is **merged onto the user's latest state** instead of being
thrown away. `slotsReq` is restored, unchanged, for the slots cache.

### 4.2 `salons.spec.ts:70` — two files writing one key. **Not a timing bug.**

`salonOffers` has exactly two writers, confirmed by grep:

- `salons.spec.ts:79` switches the salon to **Réseau**
- `team.spec.ts:95` switches the same salon to **Business**

The salon-create handler gates on the result (`stub-api.mjs:1018`):

```js
const reseauLive = [...salonOffers.values()].some(
  (o) => o.tier === 'reseau' && o.status !== 'expired',
) && Boolean(p1Offer);
if (!reseauLive) return json(res, 403, { error: 'reseau_required' });
```

If `team.spec.ts` flips the tier in the window between `salons.spec.ts:79` and
its create POST, the create 403s, the page never navigates, and `toHaveURL`
polls a **stable wrong URL** fourteen times. Fourteen consecutive polls of an
unchanging URL is a 403, not a slow redirect — **no wait would ever fix this.**

The suite already half-knew: `salons.spec.ts:83` carries the comment *"seat copy
can double-match when a parallel test already moved the cap to 15."* The
*symptom* was patched on the seat assertion; the tier itself was left shared.

**Fix — put both writers in one file.** With `fullyParallel: false`, tests
within a file are serial, so co-locating the two offer-switching tests makes the
conflict structurally impossible rather than merely unlikely. `team.spec.ts`'s
Abonnement test moves to `salons.spec.ts`, which is where the subscription arc
belongs anyway; the roster arc stays put because it only touches `teamMembers`.

### 4.3 The stub never resets

**Fix — never reuse the process.** Implementing the reset the comment already
promised, and calling it from a `globalSetup`, was the first plan and is **not**
what shipped: it restores the seeds while still letting the harness accept a
process it did not start. `reuseExistingServer: false` removes the class rather
than the instance, needs no reset route, and matches what CI already did.

Per-*worker* isolation was considered and is not reachable: the app fetches the
stub server-side and `NEXT_PUBLIC_API_BASE_URL` is inlined at build time, so
there is one stub URL for the whole run and nowhere to thread a worker index.

The same change is applied to the **Next server**, for a reason that is not
about flake at all: reusing it skips `npm run build`, so a local run silently
exercises the previous build of whatever was just edited. That one bit this
slice — the first post-fix run would have been a false green.

**The cost, stated because it is a real footgun.** An occupied port is now a
hard error before any test runs, and `npm run dev` uses the same port 3000. A
developer with a dev server up sees the suite abort where it previously ran
(against the wrong build), and Playwright's own message advises setting
`reuseExistingServer: true` — coaching them into reverting this. A hard-killed
run can also orphan a process. The remedy is one line and is recorded in the
config beside the flag:

```bash
lsof -ti:3000 -ti:8787 | xargs kill
```

### 4.4 The assertion timeout is accidental

`playwright.config.ts:14` sets `timeout: 30_000`. That is the **test** timeout.
There is no `expect` block, so every `toHaveURL` / `toHaveAttribute` /
`toBeVisible` silently runs on Playwright's **5 000 ms default** — visible in
every error message collected above. The config therefore advertises a number it
does not apply to assertions.

**Fix — state it deliberately.** Not raised: 5 s is the right value and §4.1/§4.2
are deterministic bugs that no timeout would touch. Writing it down stops the
next reader from believing the 30 s.

---

## 5. Flaky in the other direction — assertions that cannot fail

A gate that reports honestly has to be honest in both directions. **Two**
assertions were repaired and one comment was corrected; this section's heading
previously claimed three, which is one more than the diff contains.

| site | what it claimed | the finding | outcome |
|---|---|---|---|
| `booking.spec.ts:96` | that the chosen slot **survived revalidation** | `toggleService` does not clear the slot, so `setS` leaves « Confirmer » enabled *synchronously*, before `revalidateSlot` has been called | **repaired** — waits for « Spécialiste » to expand, a state only `settle`'s auto-advance produces |
| `pro.spec.ts:622` | that the go-live gate is met | the regex was `Au moins 3 prestations \(\d+\/3\)` — **`\d+` matches `0`**, so it asserted that the label renders and never the count | **repaired** — `\((?:[3-9]\|\d{2,})\/3\)` |
| `salons.spec.ts:85` | that the Réseau seat cap applied | its recorded reason was wrong — and so was B10's first replacement for it | **comment only**; the assertion is unchanged and CTA visibility remains correct |

**Two claims this section itself made, both false, corrected rather than
quietly dropped:**

- *"Same shape at `:80` and `:167`."* Neither is. `:80` is preceded by an
  assertion on « Prochain créneau : », which renders only once `settle` has
  auto-picked, so it cannot pass early. `:167` follows a slot click, and
  `onPickSlot` is wholly synchronous — no revalidation is involved. A review
  had flagged all three; only one was real.
- *"With the interference gone, they can assert what they were written to
  assert."* Not true of `pro.spec.ts`. Its looseness was never about
  `salonOffers` — its own comment blames services and photos, i.e.
  `proProvider`, which B10 does **not** isolate (§8). That is why the new regex
  raises the floor to ≥3 and still declines to pin a count.

Preserved as a counter-example, not a defect:
`tap-targets.spec.ts:131` waits with `await expect(...).toBeVisible()` *before*
`count()`, commented *"prefs load async — wait, don't skip"* — the correct shape,
already present in one place.

---

## 6. What is explicitly not done

**No `test.slow()`. No raised timeouts. No added retries.** Those hide exactly
what this row exists to stop hiding, and §4.1 and §4.2 are deterministic bugs
that a retry only conceals.

`retries` goes to **0** on CI. The evidence standard for that change is the same
one the flake was diagnosed with: **six consecutive green full runs** after the
fixes, recorded in §7.

---

## 7. Before / after — measured

| | before | after |
|---|---|---|
| full suite, 6 workers, `retries: 0` | **5 red / 29 runs (17.2 %)** | **1 red / 17 runs (5.9 %)** on the shipped tree — see §7.1; the red is a test B10 does not touch. An earlier tree (before the guard was corrected) ran 6/6 green; those runs are not counted. |
| `booking.spec.ts` under `--fully-parallel --repeat-each=4` | **1 failure / 84 executions** | **0 failures / 84 executions** — the identical experiment |
| `booking.spec.ts:85` | 3 / 29 | 0 |
| `salons.spec.ts:70` | 2 / 29 | 0 — and now structurally impossible, not merely unobserved |
| three runs against one surviving stub | 3 → 14 → 16 failed | not reachable; the stub is never reused |
| `retries` on CI | 1 | **0** |
| assertion timeout | 5 s, undeclared | 5 s, declared |
| local run tests the current build | **no** — a reused server skipped `npm run build` | yes |

**The honest weight of this evidence.** Seventeen runs is a thin sample against
a 10 % base rate, and it is **not clean** — one red, §7.1. Sampling is quoted
here because it accompanies stronger arguments, not instead of them:

- §4.2 is now **impossible by construction**, not unlikely. The two writers are
  in one file and files are serial; no sampling can improve on that.
- §4.3 is impossible by construction: there is no surviving process to pollute.
- §4.1 is the only one resting on sampling, and its evidence is the *targeted*
  experiment that reproduced it before — 84 executions of the racy file under
  the parallelism that caused it, 1 failure before and 0 after.

### 7.1 — the one red, named rather than retried

**`axe.spec.ts:86 › pro routes are axe-clean` failed once in 17 runs** on the
shipped tree. It is not a test this slice touches, and it did **not** fail once
in the 29-run baseline.

What is known, and it is not much:

- the run that failed took **1.0 min**; the median across the other sixteen is
  **37 s**. The whole suite was ~2.7× slower on that run alone.
- it did not recur in the sixteen runs around it.
- **I did not capture the error text**, so the timeout hypothesis below is a
  hypothesis. Saying otherwise would be exactly the kind of inferred cause this
  slice exists to stop recording as fact.

The plausible reading is a host-level slowdown against `timeout: 30_000`: axe
scans are the longest tests in the suite, and a 2.7× stretch would push one over
the per-test budget. That would make it environmental rather than a defect, and
it is consistent with §3.2's finding that uniform CPU load does *not* break the
suite — a transient stall is not uniform load.

**It is left named.** No retry, no raised timeout, no `test.slow()`. The
instruction in row 30 was not to paper over what cannot be explained, and with
`retries: 0` a recurrence will now fail CI loudly instead of being absorbed —
which is the point. If it recurs, the next step is to capture the failure text
before theorising, which is what I should have done here.

### 7.2 — a fragility found while proving the fix, and two miscounts

`salons.spec.ts` depends on its own test order, and that dependency lived
entirely in `fullyParallel: false` — **a flag in another file that nothing in
this one declared a dependency on.** It now says so with
`test.describe.configure({ mode: 'serial' })`.

Two claims made here on the way were wrong, and both overstated the coupling:

- *"a four-test chain in which each test establishes the next one's
  precondition"* — false. Tests 3 and 4 each only need the tier to differ from
  the one they select, which the seed (`liveOffer()`, tier `pro`) already gives
  them.
- *"Two of those links predate B10"* — **one** does: test 2 asserts there is no
  add-salon CTA and test 4 switches the offer to Réseau, so 2 must precede 4.
  Test 1 writes no offer state at all.

**And the cost, which the first version of this section omitted.**
`mode: 'serial'` skips every later test in the file once one fails. A failure in
test 1 — which touches no shared state — now removes three tests from the run,
reported as « 3 skipped » on a summary line nobody reads. For a slice whose
thesis is that a gate must report honestly, that is a real trade and not a free
win; it is accepted because the alternative is an order held up by a flag in
another file.

---

## 8. Out of scope, recorded rather than silent

**A 308 served from `.next/cache` loses its `Location` header.** Reproduced 3/3
against a hand-started `npm run start`: `curl -D - /coiffure-cocody` returns
`308` with `x-nextjs-cache: HIT`, an HTML body, and **no `Location`**. It fails
`redirects.spec.ts:15` and `:32`, and survives a server restart because the
poisoned entry is on disk.

**This never occurs in `npm run e2e` or in CI** — 0 / 29 occurrences — because
`npm run build` regenerates the cache each run. It is therefore not part of this
slice's flake. It is recorded because a warm ISR-cached deploy is the production
shape, and an SEO 308 without a `Location` header is the same class of
silent-wrong-route defect B8 found. Substantiating it against a real deploy is
its own row.

**`proProvider` is still shared, and B10 only removed half of it.** Services,
artists, photos and KYC state are written by `pro.spec.ts` and read by
`type-overflow`, `tap-targets`, `z-layers` and `axe`. Killing the reused stub
removes the *between-run* accumulation; within a run those files still share one
mutable salon. Nothing currently fails on it — the readers assert geometry and
axe rules, not counts — which is why it is recorded rather than fixed. It is
also the reason `pro.spec.ts`'s go-live assertion still refuses to pin a number
(§5).

**`confirm()` writes state after two awaits with no guard, and « Retour » is not
disabled while it runs.** `setCreated` and `setS(goPhase(s, 'done'))` land from
a stale `s` closure, so leaving the confirm screen mid-request can yank the user
onto « Réservation envoyée ✓ ». This is **pre-existing**, not introduced here,
and it is deliberately *not* given the new generation guard: a booking that was
actually created must never be hidden by a navigation. The right fix is to
disable the exit while the request is in flight, which is a booking-flow change
and not a flake. Recorded because B10's first draft claimed **"one generation
for every asynchronous write in this component"** — that claim was false, and
`confirm()` plus the `getMe` effect (which has its own `active` flag) are the
two writes it did not cover.

**Nothing prevents the next regression of the guard itself.** No unit test
asserts that a header tap during `settle` preserves the cleared slot. The one
behaviour this slice calls a product bug is covered only by the e2e that flaked
on it 3 times in 29 runs — and the corrected two-counter design is, today,
verified by reading rather than by a test. That is the weakest part of this
slice and it is stated plainly rather than left to be discovered.
