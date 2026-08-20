# Alert runbooks are rendered as Markdown before they are emailed

**Status:** shipped · **Owner:** backend/infra · **Date:** 2026-08-20

## 1. The finding

Cloud Monitoring stores an alert policy's `documentation.content` with
`mimeType: text/markdown` — the only value the API accepts — and **renders it as
Markdown into the notification email.** Markdown then eats precisely the
characters a runbook is made of.

Observed in the delivered email for *"A per-identity limit REFUSED a request"*
(2026-08-20), not inferred:

| authored | delivered | consequence |
|---|---|---|
| `identity_limits.dart` | `identity<em>limits.dart` | **the `_` is gone** — the path does not exist |
| `--limit=50` | `–limit=50` (en dash) | `gcloud` rejects it |
| `'value(...)'` | `‘value(...)’` (curly) | the shell rejects it |

The command the operator is told to paste, as it actually arrived:

    gcloud logging read ‘resource.type=“cloud_run_revision” …’ –limit=50 –freshness=1h

**Seven of nine policies were affected.** The runbook's first instruction — the
thing you do at 3am before you understand anything — could not be run.

## 2. Two content defects the same email exposed

Independent of rendering, and worse:

1. **An example line the code cannot produce.** The runbook said
   `rate_limited bucket=… hits=11 ceiling=10`. The code prints `limit=`. An
   operator grepping the documented shape finds nothing and concludes the limit
   never fired.
2. **An instruction naming configuration that does not exist.** *"set the
   matching `LIMIT_*` environment variable in `infra/gcp/service.yaml`"* — there
   is no such variable, in that file or anywhere. The ceilings are compiled in.

## 3. The rule

**Anything an operator would type lives inside a code span.** Backticks are the
proven-safe container: a delivered email (the cron-legacy alert) contained a real
`<code>` tag, so code spans survive the renderer.

**And every one of these heredocs is unquoted**, so a bare backtick in the script
is command substitution. It must be written `\`` — and *not* `\\`` , which is a
backslash followed by a **live** backtick. That second form is not hypothetical:
the transform that introduced code spans double-escaped the one file that already
had them, and `${INSTANCE}\` ran as a command, producing malformed policy JSON.

## 4. The mechanism

`backend/test/infra/alert_runbooks_test.dart` — 43 tests, run by the ordinary
backend job. It reads every `infra/gcp/*.sh` and asserts:

- identifiers containing `_`, `--flags`, and whole command lines are inside code spans
- no backtick is unescaped (would run) or double-escaped (would also run)
- **the shell actually emits valid JSON** — it runs each heredoc and parses the
  result, which is the only oracle that sees a live backtick
- code spans are balanced, so one cannot leak into the next paragraph
- **the example log line uses the same keys the code prints** — this is what
  `ceiling=` failed
- **every `SCREAMING_SNAKE` variable a runbook points at `service.yaml` for is
  actually set there** — this is what `LIMIT_*` failed

### 4.1 Two holes in the guard's first draft

Worth recording, because a guard that reads the wrong string is worse than none:

- It read **one** runbook per file. `88-email-budget-alert.sh` ships **two**
  policies and `80-uptime-checks.sh` builds **two** `DOC=` strings, so three of
  eight were reported green without being read.
- It matched `"content": "${DOC}"` and took the literal `${DOC}`, then scanned
  onward into unrelated shell and flagged a backtick that was never in a runbook.

Both were found by asserting on the **count of policies discovered**, which is
now a test.

## 5. Verification

Mutations watched red: `limit=` → `ceiling=` · an escaped backtick made live ·
a backtick double-escaped · a closing backtick removed · a command lifted out of
its span. Each restored green afterwards.

**What is still unproven:** that a code span suppresses the *typographic*
substitutions (en dash, curly quotes) as well as emphasis. Standard Markdown
excludes code from both, and the delivered `<code>` tag proves spans render — but
the span we observed contained no hazard characters. **The next alert email is
the falsifier**, and the command in it is either pasteable or it is not.

## 5.1 Applying it to the live policies

`infra/gcp/93-sync-runbooks.sh` pushes the repo's runbook text onto the live
policies, and exists because **every other script here only calls
`policies create`.** A policy's identity is the numeric id assigned at creation,
not its `displayName`, so those scripts cannot re-run. When the runbooks were
last corrected (§8.3 of the send-budget spec, 2026-08-19) it was done with a
hand-written REST `PATCH` **that was never committed** — which is why the drift
was invisible again the next day.

It changes **only `documentation.content`**. `gcloud alpha monitoring policies
update` with `--documentation-from-file` and *no* `--policy-from-file` does a
read-modify-write and sends `updateMask=documentation.content` — narrower even
than August's `updateMask=documentation`, because it cannot touch `mimeType`.
Passing `--policy-from-file` instead sends `updateMask=None`, a **full replace**
that would drop `alertStrategy`, `notificationChannels` and `conditions`.
`--fields` does not help: it accepts only `disabled` and `notificationChannels`,
and requires the policy body it is trying to avoid.

### What an adversarial review of it found

- **An empty render would blank a live runbook, and the read-back would certify
  it** — `got == want` with both empty. `gcloud` does not treat an empty file as
  "no change" either. The script now refuses anything under 200 characters, and
  refuses an odd number of backticks, which is what an executed code span leaves.
- **Popping `documentation` from both sides before comparing** proves nothing
  about the field being changed. The script asserts the stored content equals the
  intended content *first*, and only then compares everything else.
- **The run is not atomic.** It is idempotent instead: a policy already matching
  the repo is skipped, so the recovery from a partial run is to re-run it. Every
  pre-patch capture is kept for rollback, and a failure prints what already moved.

### 5.2 `DRY=1` is the drift detector

```
DRY=1 bash infra/gcp/93-sync-runbooks.sh
```

Writes nothing; prints per policy whether the live text still matches the repo.
Run it whenever a runbook changes, and after any incident that made someone edit
a policy in the console.

**This is the check August did not have.** The runbooks were corrected on
2026-08-19 by a `PATCH` nobody committed, and by the next day nothing in the repo
could say whether production still carried that text — which is precisely how the
same class of defect came back and was found from a delivered email rather than
from a test.

The guard in `backend/test/infra/alert_runbooks_test.dart` checks the **scripts**.
Only this dry run checks the **live policies**, and only it would notice a sync
that stopped halfway.

### 5.3 Applied, 2026-08-20

All **7** policies needing a change were patched; the two uptime policies were
correctly left alone. Verified three independent ways:

1. **Per patch** — stored content equals the intended content, *and* every field
   outside `documentation` is deep-equal to the pre-patch capture.
2. **Fresh re-scan of live content** — the same hazard scan that found the defect
   now reports **0 hazards across all 9 policies**, and the identity-limit runbook
   contains no `ceiling=` and no `LIMIT_*`.
3. **Drift check** — a fresh render byte-matches a fresh read on all 7.

The invocation matched the source-verified safe form exactly: only
`--documentation-from-file`, and `printf '%s'` to write it, because gcloud's
`FileContents` does not strip and a trailing newline would land in the stored
text. No policy carries `documentation.subject` or `links`, so nothing was at
risk from the narrower mask either way.

## 5.4 Proven by a delivered email, 2026-08-20

The cron alert was triggered deliberately (an unauthenticated `POST` to
`/internal/cron/subscriptions` on staging, 403). The delivered mail settles §5's
open question — **a code span suppresses the typographic substitutions as well as
emphasis**:

| claim | delivered |
|---|---|
| underscores survive | `CRON_OIDC_AUDIENCE` — intact |
| `--` stays two hyphens | `--location`, `--region`, `--format` — intact |
| quotes stay straight | `--format='value(httpTarget.oidcToken.audience)'` |
| no en dash inside a span | clean |

And prose outside the spans still gets proper typography, which is what it should
get. **The commands in that email are pasteable as printed.**

### 5.4.1 The same email exposed one more defect

Its `<p>` structure showed **two `gcloud` commands sharing one paragraph.**
Markdown folds a single newline into a space, so consecutive command lines
arrive run-together on one wrapped line, and an operator can copy both as one
command. Separated by a blank line, and guarded: no two command spans may share
a paragraph.

Finding it required looking at the *structure* of the delivered HTML rather than
the characters in it — the four character-level claims all passed.

### 5.4.2 And a defect in the guard itself

The paragraph test failed on a runbook that was already correct. The cause was in
the guard's own decoder: the file holds `\\n`, the shell strips one level and
JSON the second, but the test decoded only one — leaving a stray backslash before
every newline, so a split on `\n\n` never matched and **every runbook read as a
single paragraph**. Every earlier test still passed, because they all worked
per-span rather than per-paragraph.

Third instance of the same lesson from this file: *a guard that reads the wrong
string is worse than none.* The first two were reading one runbook per file, and
taking `${DOC}` literally.

### 5.4 The drift check watched the less important half

Until 2026-08-20 `93-sync-runbooks.sh` compared only `documentation.content`.
**The filter is the half that decides whether an alert can fire at all**, and it
was unwatched — which is how *"A per-identity limit could NOT be enforced"*
shipped with an unanchored `textPayload:"rate_limit_unavailable"`, was corrected
in the repo, and still had the dry run report `same`.

It now compares filters too, and **reports rather than patches**. Changing a
filter means replacing the whole policy, which regenerates the condition's
generated id unless done as a read-modify-write — a different and riskier
operation than swapping a text field. Detection is the half that must never be
silent; the fix stays deliberate, and the script prints the exact recipe.

**The first version of that check was itself reading the wrong string.**
`render()` extracts the heredoc but did not carry across the script's shell
assignments, so `${SERVICES}` — which names both Cloud Run services — expanded to
nothing and the repo-side filter came out as `... AND  AND ...`. Three perfectly
correct policies were reported as drifted. Fourth instance in this file of the
same lesson, and the reason the fix carries the simple single-quoted assignments
across.

### 5.5 The sync tool converges, and the renderer had to be fixed first

#453 made the tool *detect* filter drift and print a recipe for fixing it by
hand. That institutionalised the hand-patch. It now **converges** every field the
repo declares — `combiner`, `alertStrategy`, `notificationChannels`,
`documentation`, each condition's `displayName` and filter — across **all 11**
policies, up from 9.

**Two renderer bugs had to be fixed first, and either would have been
destructive.**

| | |
|---|---|
| `notificationChannels` rendered as `[""]` | every script resolves `CHANNEL=$(gcloud …)`, a command substitution the assignment grep cannot capture. A converge would have **detached all nine policies from the project's only channel**, while each still read *enabled, no incidents*. |
| `85` rendered `database_id=":myweli-db"` | live is `"myweli:myweli-db"`; `PROJECT=myweli` is a bare word, also uncaptured. Extending detection first would have reported drift against a **correct** production policy. |

Both are why the order was renderer → detection → converge, and why the first
`DRY=1` run reading **`changed: 0, already correct: 11`** is the discriminating
result rather than a formality.

### 5.5.1 Read-modify-write is required, and here is the proof

The API contract says *"Existing conditions are deleted if they are not
updated"*. Measured on a throwaway policy created and deleted for the purpose:

```
condition name present in the body   14090412480863057604 -> 14090412480863057604   preserved
condition name omitted (a raw body)  14090412480863057604 -> 16910435644902405133   CHURNED
```

A repo body carries no `conditions[].name`, so feeding one straight to
`--policy-from-file` deletes and recreates the condition on **every run**,
orphaning open incidents. The tool takes the live object and overwrites only the
declared fields.

### 5.5.2 `enabled` is declared and never converged

Every body now says `"enabled": true` — absence means enabled on write, which is
a coin flip that always lands the same way, not a declaration.

**A live `enabled: false` is a hard stop**, not drift. Someone muted an alert
deliberately; a sync tool has no standing to overrule that, and doing so
mid-incident is the worst possible moment.

### 5.5.3 The read-back got stronger

It asserted *"nothing else moved"* by popping `documentation` and comparing the
rest — protection that is **lost for any field the moment it is popped** to allow
a change. It now asserts **exactly the declared fields changed, exactly to the
declared values**, that condition ids are the ones we started with, and that the
write did not disable the policy.

### 5.6 An alert must not watch for a string the running artifact cannot emit

Three legs, and the third was missing:

| question | answered by |
|---|---|
| does the repo's filter match a string the code prints? | `alert_runbooks_test.dart` — **the working tree** |
| does the live policy match the repo? | `93-sync-runbooks.sh` |
| **can the artifact each service is RUNNING produce it?** | **`95-emitter-lag.sh`** |

The third is what failed on 2026-08-20: `#445` merged its emitter after the last
production deploy, so production ran a commit without the string while the policy
filtered for it. Reproducible from git without touching anything:

```
PIN_myweli_api=34d55c0 bash infra/gcp/95-emitter-lag.sh
  FAIL  A per-identity limit REFUSED a request  'rate_limited bucket='
          myweli-api=CANNOT EMIT   myweli-api-staging=ok
```

**It checks every service a filter names, on every run — not the one just
deployed.** That distinction is the whole point: the deploys after `#445` were
staging pushes, and staging *did* have the string. A check scoped to the deployed
service would have passed on every one of them while production stayed blind.

**It runs after the deploy, deliberately.** As a gate it would block the very
deploy that fixes the lag. The failure message leads with *"the deploy succeeded
and traffic is live — this is about alert coverage"*, because a red run after a
healthy shift otherwise reads as a broken release, and repeated misreadings train
people to ignore red.

**Provenance is a pair, not a label.** The revision's `commit` label is
self-reported; a registry tag is mutable and `latest` shares a digest with a real
SHA in this registry. Neither is sound alone. The check resolves
`IMAGE:<label>` back to a digest and requires it to equal the digest the revision
is serving — and prints which method it used, because an unverified fact stated
as verified is the defect, not the fallback.

**It refuses to run on a shallow clone.** `git grep <old-sha>` cannot work there,
so `deploy-backend.yml`'s checkout now sets `fetch-depth: 0`. A check that cannot
look must fail, not pass.

**And it names what it cannot check** — the load-balancer and metric-based
filters — rather than covering a third of the surface while looking total.

### 5.6.1 One extractor, pinned to the other

`policy-bodies.sh` now holds the renderer, shared by `93` and `95`. The Dart test
regexes raw script text and cannot interpolate `${SERVICES}`, so it cannot say
which services a filter names; a test asserts the two agree on the literal set,
so they cannot drift.

### 5.6.2 Created before deployed

The create scripts now run the check after creating a policy and **warn**, naming
the services that cannot yet emit the string. Warned rather than refused:
staging an alert just ahead of its deploy is a legitimate order, and a hard stop
only pushes someone into creating the policy in the console instead.

### 5.6.3 What the first real CI run showed

Two things, on the staging deploy of `365afe3`:

**It caught genuine drift immediately.** `myweli-api 0b23724` against
`myweli-api-staging 365afe3` — production lagging staging, which is the exact
condition that unmasks this hole. Correctly `ok`, because `0b23724` does contain
all five strings. Both resolved as *"label verified against the serving digest"*,
so the provenance chain works under the deploy service account.

**And it leaked two raw permission ERRORs into a passing step.**
`80-uptime-checks.sh` looks up its uptime `CHECK_ID` live, and the deployer has no
monitoring read. Nothing was actually wrong — `80`'s filters are metric-based and
skipped either way — but **unexplained ERROR lines inside a green step teach
people to ignore errors**, which is the opposite of what a check is for. `render()`
now captures stderr and the caller says it once, in words, pointing at the
skipped list.

## 6. Related

- `docs/design/backend-email-send-budget.md` §8.2–8.3 — the first two instances:
  the runbook arrived **empty**, then arrived with its most important sentence missing.
- `docs/design/backend-identity-rate-limits.md` §8.2 — why production is observed.
