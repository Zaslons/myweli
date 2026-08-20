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

## 6. Related

- `docs/design/backend-email-send-budget.md` §8.2–8.3 — the first two instances:
  the runbook arrived **empty**, then arrived with its most important sentence missing.
- `docs/design/backend-identity-rate-limits.md` §8.2 — why production is observed.
