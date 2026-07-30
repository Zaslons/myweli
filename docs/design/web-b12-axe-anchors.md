# B12 — the wait that could not settle, and the scan that never checked

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-07-30 |
| **Register row** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §15 row 30 (reopened) · row 33 |
| **Skills checked** | `myweli-web-guardrails` |
| **Preceded by** | [B10 — the flake](web-b10-flake.md) · [B11 — the reflow contract](web-b11-reflow.md) |

---

## Context

A **mobile-only** PR (A14b) went red on `Web — e2e (Playwright)`:

```
1) tests/e2e/axe.spec.ts:86:5 › pro routes are axe-clean
   Test timeout of 30000ms exceeded.
   Error: page.waitForLoadState: Test timeout of 30000ms exceeded.
   > 92 |     await page.waitForLoadState('networkidle');
```

`main` was green on its previous four runs, and the same job had failed **twice
on B11** before going green. So B10's headline — *"5 red / 29 runs → **0**"* —
did not hold, and the row that recorded it needs reopening rather than a re-run.

## The mechanism

`next.config.mjs` allow-lists `cdn.stub` in `images.remotePatterns`. That entry
is what routes a stub photo **past** the cheap rejection in
`next/dist/server/image-optimizer.js:452` and into the outbound path, where
`fetchExternalImage` (`:722`) calls `fetch(href)` with **no `AbortSignal` and no
timeout**.

The consequence is the part that is easy to miss:

- `next/image` renders a **same-origin** `/_next/image?url=https%3A%2F%2Fcdn.stub%2F…`;
- the **Next process**, not the browser, then resolves `cdn.stub`;
- so `page.route('**/cdn.stub/**')` cannot intercept it — the browser never
  requests that host, and the percent-encoding means the glob would not match
  the optimizer URL either;
- Node resolves via `getaddrinfo` on libuv's **4-thread** pool, so a handful of
  hanging NXDOMAIN lookups can starve every other threadpool consumer in the
  server.

`networkidle` waits for the network to go quiet. It cannot, while that is
happening.

### ⚠️ Why this is recorded as *plausible*, not *proven*

The adversarial review would not sign off on the stronger claim, and it was
right not to:

- **Playwright attributes a test-level timeout to whatever call is in flight.**
  If the login plus four route cycles had already burned 28s, the fifth
  `waitForLoadState` gets blamed after 2s. The stack cannot distinguish that
  from a genuine stall.
- **"The log was flooded with `ENOTFOUND`" is much weaker evidence than it
  looks** — *every green run floods it too*, because `/beaute-divine` is scanned
  every time.
- Of the five pro routes, **only `/pro/apercu` renders a remote image at all**.
  If the failing iteration was one of the other four, the hypothesis is refuted
  for that run.

What tips it: `/pro/apercu` is **fully client-rendered**
(`SalonPreviewClient.tsx:44-51` paints a skeleton first), so `page.goto` returns
before any image request opens — meaning *100 %* of its image traffic, including
the eager `priority` hero, starts while `waitForLoadState` is the pending call.
On the SSR routes that traffic begins during `goto` instead.

**The missing datum was not capturable**, and that is now fixed: the config had
`reporter: 'line'` and no `trace`. With `retries: 0`, a red run is the only look
you get, and it produced nothing but a stack. `trace: 'retain-on-failure'` costs
nothing on green and answers "which route" in one look.

## The second finding, which is worse

The axe spec — WEB-SYSTEM §15 row 15's *"the whole of §4–§8, on real pages"* —
had **no content anchor on any of its 19 routes**. It waited on the network and
scanned whatever DOM was there.

So a 404, or an `ErrorState`, would have been scanned, found clean, and passed.
That is not hypothetical: **B8 caught exactly this in the overflow gate**, where
a slug rename had left a route measuring the 404 page for months — and the 404
page does not overflow either.

`ErrorState.tsx:32` renders the page's own `<h1>`, so even a heading anchor is
not sufficient on its own; its `role="alert"` is the discriminator.

## The fix

**Both halves, for different reasons.** Stubbing alone leaves an unbounded wait
one new remote asset away from the same failure; anchoring alone leaves the
server-side DNS burning wall-clock and threadpool.

1. **Kill the traffic, both paths.** `page.route('**/_next/image**')` and
   `page.route('**/cdn.stub/**')`, both *fulfilled* with a 1×1 GIF rather than
   aborted — a fulfilled image stays "loaded", so layout, paint and
   `naturalWidth` are unchanged and no `net::ERR_FAILED` reaches the console.
2. **Anchor every route.** The anchor is the render signal *and* the vacuity
   guard, which is the shape `type-overflow.spec.ts` already settled on — and
   which that file's own comment (`:369-372`) had already justified in terms of
   this exact `cdn.stub` stall. Every anchor is lifted from a spec that already
   proves it green, plus `lib/legal.ts`'s `h1` field, rather than invented.
3. **A second stage where one is needed.** `/mon-compte` paints its heading
   before its bookings; `networkidle` was implicitly waiting for both, so an
   anchor-only wait would have *regressed* coverage and raced a DOM mutation
   under axe.
4. **`role="alert"` emptiness on every route**, with `.filter(Boolean)` — Next
   ships an empty `<div id="__next-route-announcer__" role="alert">` on every
   page, and keying on the role alone reddens everything (B11 measured that).

Two anchors were guessed wrong and corrected by the evidence rather than by
another guess: `/mon-compte/appt2` titles itself with the **salon**, not the
booking; and `/beaute-divine`'s exact string is unsafe because `pro.spec.ts`
renames the shared stub salon from another worker — both are regexes now, as
`roles.spec.ts` already does.

## What is NOT fixed, said plainly

`cdn.stub` still resolves nowhere for every **other** spec, so the server log
still carries `ENOTFOUND` noise and some wasted latency.

That is deliberate and bounded: **`axe.spec.ts` was the only spec in the suite
with an unbounded network wait** — verified by grep; `booking.spec.ts:102` even
carries a comment saying the wait has to be on the DOM. Without such a wait the
DNS failures cost log lines and milliseconds, not a red run.

The root fix, named here so it is not rediscovered: serve the stub images from
the stub API's own origin (`127.0.0.1:8787`) and drop `cdn.stub` from
`remotePatterns` entirely. Deleting the allow-list entry alone also stops the
sockets — every optimizer call becomes an instant local 400 — but it silently
makes every `next/image` a broken image, which is a landmine for any future test
that asserts one rendered.

## Follow-up: the trace immediately caught a second one, in this file's own PR

Within an hour of B12 landing, `Web — e2e` went red on **main** and on A14b's
branch — three runs across two branches, always
`focus.spec.ts:54 › keyboard focus wears the ring; a clicked button does not`.
It passes 3/3 locally.

**B12 is the trigger, and the honest reading is that it did its job.**
`trace: 'retain-on-failure'` instruments every action, and the added latency
moved the sample in a test that was always sampling a race:

```ts
const clicked = await outlineOf(search);   // one-shot evaluate, no retry
expect(clicked.outlineStyle === 'none' || …).toBe(true);
```

`locator.evaluate` resolves **once**. `expect(locator).toHaveCSS(...)` re-queries
until it matches; a bare `evaluate` fed into `expect(value)` does not. All three
call sites in `focus.spec.ts` read it that way, so each was a single sample of a
value the browser is still settling — the same class of defect as the
`networkidle` wait above, in the same suite, found the same week.

Fixed by wrapping all three in `expect.poll`. The helper still reads its four
properties in one `evaluate`, because `toHaveCSS` takes one property at a time
and the focus ring is a set.

**Recorded rather than reverted.** Turning the trace back off would have hidden
this, and the trace is exactly what turned a rare CI-only red into a
reproducible three-in-a-row that could be diagnosed.

## Correction: this row was filed as 31, and 31 was already taken

Shipped as **row 31**, directly under row 30 — narratively right, since B12
reopened row 30, and wrong on the only thing a row number has to be. **B11 had
already taken 31 and 32**, so the register carried two row 31s for an hour: the
axe anchor here, and *"the type and spacing scales are `px`"* three lines below.

Renumbered to **33** and moved below row 32, restoring 30 · 30h · 31 · 32 · 33.
**This row yielded, not B11's** — rows 31 and 32 are still **open**, and
renumbering a row that the slice which closes it will cite is how you
manufacture the confusion this fixes. The newcomer moves.

Written down rather than quietly renumbered, for the same reason row 30 keeps
B9's superseded 30h verbatim: **the register's own errors are part of what it
records.** A number silently corrected leaves no evidence that a number can be
wrong — and every claim in this file is cited by number.

And it is now a **gate rather than a habit**: `web/tests/register-pin.test.ts`
reads both registers from disk and fails on a repeated row id — §21's 78 rows
and §15's 44. Watched red by reinstating the duplicate (it named `"31"`), then
green. It carries a falsifiability case as well, because the real-file
assertions are green from birth and §21 row 67 is the record of six helpers
shipped unable to fail.

A lettered variant (`30h`, `7b`) is a distinct id, not a repeat of its stem —
that is asserted, since the register uses them deliberately.

## Verification

```bash
cd "/Users/sadreddinedaher/beauty app/web" && npx playwright test
```

`166 passed` on two consecutive full runs, ~42s each. The axe spec alone went
from *timing out at 30s* to **5 passed in 22.5s**.
