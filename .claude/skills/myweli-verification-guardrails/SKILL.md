---
name: myweli-verification-guardrails
description: >-
  How to know a thing is true before saying it is. Use this skill WHENEVER you
  are about to state that something works, is configured, is deployed, is fixed,
  or is done — and whenever you write a test, an alert, a guard, or a checklist
  entry that is supposed to catch a problem. Also use it before ticking any box
  in docs/LAUNCH.md, before reporting a PR as verified, and before claiming a
  state you cannot directly observe (an external console, someone else's
  account, a running deployment). Every rule here was learned from a real defect
  in this repo, and each names the one that taught it.
---

# Verification Guardrails

This skill exists because the same defect kept shipping in different costumes.
Not *bugs* — **claims**. A test that could not fail. An alert that could not
fire. A document that was true when written. A checklist that stated a fact
nobody had checked.

They are all one mistake: **something stood in for evidence, and nobody asked
what would happen if it were wrong.**

Each rule below is followed by the incident that taught it. Read the incidents;
they are the part that transfers.

---

## 1. Say what you verified, not what you believe

**Before asserting any state, ask: did I observe this, or infer it?** If you
inferred it, say so — `UNVERIFIED` is a complete and respectable answer.

The bar is highest for things you *cannot* reach: an Apple Developer portal, a
Sentry dashboard, a Play Console, a colleague's machine, anything behind
someone else's login.

> **The incident.** A checklist said the Sign in with Apple capability was
> missing from the App IDs. Nothing in this repo can see the Apple Developer
> portal. It had been enabled all along. The repo half of that finding was real
> and verified by reading files; the account half was a guess wearing the same
> sentence.
>
> **Its twins, in the other direction.** LAUNCH.md said production held no
> seeded data (it held three smoke accounts). `mobile-store-submission.md` said
> Sign in with Apple was "already working" (the entitlement was absent from both
> entitlements files). Two too optimistic, one too pessimistic — identical
> defect.

**Rule:** where a claim depends on a system this repo cannot reach, write the
claim *and* how it would be checked. If it cannot be checked from here, mark it
and name who can.

---

## 2. A check that cannot fire is worse than no check

It reads as coverage. Coverage is exactly what it is not.

**Before trusting any new test, alert, guard or assertion, make it fail on
purpose.** Break the thing it watches and watch it go red. If you cannot make it
red, you have not written a check — you have written a comment that runs.

> **The incidents, all from one week.**
> - An alert watched for a log line whose branch had just been deleted. It could
>   never fire again, and a permanently-inert alert looks exactly like a healthy
>   system.
> - A widget test asserted `tester_hasNoOverflow()`, a helper that returned
>   `true` unconditionally.
> - Two tests matched strings that appeared only in **comments** — one of them
>   the comment explaining the defect it was meant to catch. Strip comments
>   before matching.
> - A version gate returned "allow" on the only machine that could run its
>   tests: it read `Platform.isAndroid`, and a test VM is neither Android nor
>   iOS. Every test exercised an early return.
> - The same gate consulted `AppConfig.useApiBackend`, a `bool.fromEnvironment`
>   that is false under `flutter test` — so the suite could only ever reach the
>   "do nothing" branch. **A branch a plain test run cannot reach needs a CI
>   step that reaches it.**

**Rule:** every guard ships with the record of it having failed. "Watched red"
belongs in the commit message, not in your memory.

---

## 3. The manifest is not the deployment

A committed change is inert until something replaces the running thing. A
merged PR is not a deployed service. A corrected document is not a corrected
page.

**Verify against the deployed artifact, not the source.**

> **The incidents.**
> - The live privacy policy denied using Sentry while the bundle served from
>   `myweli.com` posted to `ingest.de.sentry.io`. Both claims were true when
>   written; a later change made them false and had no reason to open that file.
> - A backend feature was merged and *not* in production — staging auto-deploys
>   on merge, production is `workflow_dispatch`. `/client-version` answered on
>   one and 404'd on the other.
> - Cloud Run publishes two hostnames; only `status.url` is the one traffic
>   uses. `spec.template…image` and `status.latestReadyRevisionName` both lie
>   after a traffic pin.
> - A hand `gcloud run services update` is reverted by the next deploy of the
>   committed manifest. Declarative or it did not happen.

**Rule:** after a deploy, fetch the thing a user would fetch. After a doc fix
about a live page, fetch the live page.

---

## 4. Make the oracle discriminate

An assertion that passes for the wrong reason is not evidence. **Before
believing a probe, run the control** — the case that must produce a *different*
answer. If both produce the same answer, the probe measured nothing.

> **The incidents.**
> - Probing whether a route existed by calling it unauthenticated: it returned
>   401. So did a route that did not exist, because the middleware runs before
>   routing. The working oracle was **405 vs 404** on a wrong verb.
> - A floor of `0` and a missing database table both answer `{"status":"ok"}`.
>   The discriminating move was to raise the floor, see the verdict change, and
>   set it back.
> - `grep` over a test log found nothing because the reporter prints no test
>   names — the absence proved nothing about the tests.
> - `echo "exit=$?"` after a pipe reports the exit status of `tail`.
> - A CI run printed "Action failed" from a step that legitimately fails
>   (creating an already-existing resource) while the run's conclusion was
>   `success`. Read the conclusion, not the scariest line.

**Rule:** state what result would falsify your claim *before* you run the check.

---

## 5. Never suppress the error you are about to act on

`>/dev/null 2>&1` on a command whose success you are about to assume is how a
failure becomes an assumption.

The subtler form: **a shell chain that silently does not run.** `cmd-that-finds-nothing && python3 - <<'PY' …` never executes the heredoc, and the next
step then "passes" against unchanged code.

> **The incidents.**
> - Stderr suppressed three times in one session, hiding a rejected
>   authorized-networks patch and a crashing `--remove-headers`.
> - `gcloud` printed a help hint rather than an error for a non-existent flag,
>   so a retention setting silently stayed as it was.
> - A `.replace()` without an assertion meant a fix silently did not apply; the
>   subsequent green run was against the old code. **`git status` said "working
>   tree clean" and that was the only reason it was caught.**

**Rule:** assert the resulting *state*, never the exit code — and never the
absence of output.

---

## 6. Read the target before you change or delete it

Especially when the instruction names a count or a set.

> **The incident.** "Purge the ~5 `users` rows the PITR restore found." The
> smoke residue was **three** rows. Two of the other five were the owner's own
> Google and Apple sign-ins. Reading the table before deleting from it is the
> only reason that did not become the story.
>
> The purge script then enforced the `.test` suffix *itself* and asserted a
> count of exactly three, so a mistake in the operator's reasoning could not
> reach a real account.

**Rule:** print the keep-list and the delete-list before acting, and put the
safety condition in the script rather than in your head.

---

## 7. A statement true when written is not true forever

Descriptions decay into *incomplete*. **Denials decay into false.**

> **The incidents.**
> - « aucun rapport de plantage tiers — pas de Sentry » — true until Sentry
>   shipped.
> - « aucun journal applicatif » — true until the Cloud Run migration.
> - `Env`'s comment justified an OTP echo on staging "because staging has no SMS
>   channel" — true until staging got email, Google and Apple.
> - A smoke harness said a secret was "required only when the target runs
>   `ENV=prod`" — false the same day the echo was closed.
> - `infra-staging.md` said "nothing under `lib/` imports the browser API
>   client". Both halves were wrong, and the correct conclusion it supported
>   survived only by luck.

**Rule:** prefer describing what you *do* over denying what you do not. Where a
denial is unavoidable, pin it with a test that fails when the denied thing
appears — for example, a test that reads `package.json` and fails if the page
denies a dependency that is present.

---

## 8. Prevention is not cleanup

Choosing a decision that stops a problem recurring reads as resolving it. The
existing instances are still there.

> **The incident.** `backend-q1b-smoke-seam.md` §7 was struck through as
> "Resolved — option 3": move the recurring gate to staging. That stopped new
> residue and did nothing about the three accounts already in production, which
> option 1's "then purge by identity suffix" would have. They sat there for
> twelve days under a heading that said resolved.

**Rule:** when you close an item, say explicitly what happens to what already
exists.

---

## 9. A deadline in a document is not a mechanism

> **The incident.** `infra-staging.md` §2.1 filed an open security question
> against itself — "anyone who finds the URL can sign in as any identity" — with
> "**decide before build-order step 5**". Step 5 ran. Nobody noticed. It
> surfaced two days later from an unrelated direction.

**Rule:** if something must not be forgotten, it goes in a test, a CI step or an
alert. A sentence in a design doc is a wish.

---

## 10. Look at the picture

Some defects are only visible, and a passing test can hide them.

> **The incident.** The blocking screen's only action fell **below the fold** at
> 200% text on a floor phone. The widget test passed — because it scrolled to
> find the button first. Only the golden showed it. On the one screen a user
> cannot leave, the way out must never have to be hunted for.

**Rule:** when a change affects rendering, open every changed PNG. When a
generated artifact bundle contains more than you changed, diff it — 46 of 48
golden files were byte-identical, and copying all of them wholesale would have
silently re-baselined screens nobody touched.

---

## 11. The guard you skipped mutating is the one that cannot fire

Not "usually". **Every time it was checked.**

> **The incident.** Three audits of one launch effort compared each PR's
> "mutations watched red" list against the guards that PR actually added. Three
> PRs, three omissions — and the omitted guard was, each time, the one a later
> audit proved could not fail: the analytics denial branch that reduced to
> `expect(false).toBe(false)`; the sitemap guard whose `> 0` passed on the exact
> defect it was written for; the CWV pin that iterated the blocks that exist and
> never asked whether a measured URL had one.
>
> The list in the commit message is not paperwork. It is the only record of
> which guards were actually exercised, and the gap in it predicts the failure.

**And a mutation that does not apply proves nothing.** In one session four
mutations printed a reassuring "GREEN under mutation" while the edit had silently
failed to match — wrong indentation, a moved string. `assert` that the
replacement changed the file, and treat a non-applying mutation as *no result*,
never as a pass.

---

## 12. Widening a list fixes the instance, not the blindness

When a guard misses something, the reflex is to add the missed item. Ask instead
what the list **structurally cannot see**.

> **The incidents, all from one effort.**
> - A third-party allowlist watched `/`, `/connexion` and `/pro/connexion`, and
>   `/pro/inscription` shipped fetching a flag from GitHub Pages. Widened — and
>   it then emerged that of the five routes listed, exactly **one** rendered a
>   phone field at all: `/mon-compte` redirects to `/connexion` when anonymous,
>   and `/connexion` is email-first. The list read as phone-field coverage and
>   was not.
> - The install-prompt guard visited `/`. The identical defect — copy offering
>   an app with no store link — was live on `/pro/connexion` the whole time,
>   because the invariant was stated site-wide in the docstring and enforced on
>   one URL.
> - Self-hosting those flags moved the request to our own origin, which put the
>   *next* failure — the prebuild step deleted, the file 404ing — permanently
>   outside what a third-party allowlist can detect.

**Rule:** for every allowlist, denylist or route list, write down the class of
failure it cannot detect, and put a different guard on that class.

---

## 13. The fix is where the next defect lives

A correction is new code written under time pressure by someone who has stopped
looking for problems because they just found one.

> **The incident.** Three consecutive audits of the same plan each found a live,
> user-facing defect **introduced by the previous round's fix**.
> - The remedy for a false privacy sentence was to rewrite the sentence rather
>   than the software — and the rewrite was still false.
> - The remedy for that shipped a `loadScript` helper that hung on the second
>   tap after a failed load, leaving the sign-in card looking alive and doing
>   nothing — in the file whose own comment claimed to prevent exactly that.
> - The remedy for an orphaned app-install prompt fixed the homepage and left
>   the identical copy live on `/pro/connexion`.
>
> None was found by a user. None was found by the guard written after the
> previous one. All three were found by auditing the **deployed artifact**
> against the plan.

**Rule:** audit the fix with the same suspicion as the defect, and against what
is deployed rather than what was merged. A round of remediation is not a reason
to lower the bar; it is the most likely place to need it.

---

## 14. Audit the step before starting the next one

Not at the end. **Between.**

> **The incident.** A four-phase plan was reported closed three times and was
> closed none of them. Each audit found a live, user-facing defect **introduced
> by the previous round's fix**. The discovery rate did not fall between rounds
> — what changed the outcome was auditing at all.

**Scale it to the change; do not ritualise it.** A ritual nobody can afford is a
rule nobody follows.

| the change | the audit |
|---|---|
| one guard or one fix | probe the deployed thing; mutate the new guard and watch it fail |
| a step of a plan | re-read that step's own deliverables against production, with a control |
| a phase, or anything you are about to call "done" | the adversarial pass — separate eyes, told to refute |

**What the audit is looking for is not "did I write the code".** It is:

- does the new guard fail on the defect it was written for, or only on a
  simpler one nearby?
- is any claim in the commit message an inference wearing an observation's
  label?
- what did fixing this put *out of reach* of an existing guard? (Self-hosting a
  vendor asset moved the next failure to our own origin, where a third-party
  allowlist cannot see it.)

> **Two audits in this repo each produced a finding about the guard just
> written**, not about the code: a coverage check blind to the one origin that
> is never a source literal, and a read-only assertion matching a string inside
> the comment that explained the footgun. Neither was findable by re-reading the
> diff.

**Rule:** finish a step, audit it, *then* start the next. On this project's
evidence the audit is not overhead on the work — it is the part that made the
work true.

---

## The one-line version

**Before you say it works: name the observation that would prove you wrong, and
go make it.**

And when the thing you are checking is your own fix, assume it is wrong in a way
you have not thought of yet — because three times running, it was.
