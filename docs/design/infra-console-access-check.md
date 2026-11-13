# Console Access check: every address of the admin console must keep sending an anonymous visitor to the Cloudflare Access sign-in — design spec

| | |
|---|---|
| **Status** | **Approved and built 2026-11-13** (owner: « add the daily check »), on `ci/console-access-daily-check`, **merged 2026-11-13** (#781, `0f53e663`). 25 mutations watched red (16 at build, 9 after the review); green against production from the owner's Mac; **green on GitHub** in its first run (production-checks run 43422200006, 2026-11-13, dispatched on `03ffc953`): the job log shows all six addresses answering 302 to their own host's Access sign-in from GitHub's network |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-13 |
| **PRD ref / phase** | Operations, no product requirement · V1 |
| **Module** | `infra/cloudflare/98-verify-console-access.sh`, the `access` job of `.github/workflows/production-checks.yml`, `backend/test/infra/console_access_check_test.dart` |
| **ROADMAP entry** | [2026-11-13-console-access-daily-check.md](../roadmap/entries/2026-11-13-console-access-daily-check.md) |
| **Origin** | [LAUNCH.md](../LAUNCH.md), the box « Cloudflare Access is configured on the `myweli-admin` Pages project »; [DEPLOYMENT.md](../DEPLOYMENT.md) § Phase E, « Restrict »; [entry of 2026-11-13](../roadmap/entries/2026-11-13-admin-console-deployed-access-pages-dev.md) |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-backend-guardrails ✓ · myweli-verification-guardrails ✓ · no app, web, API or contract change |

---

## 1. Goal & scope

**Goal.** If any address the admin console is served from stops sending an anonymous visitor to the Cloudflare Access sign-in, the daily monitor turns red that morning and the owner is told on the alarm issue.

**Why.** Access lives only in the Cloudflare dashboard: the application « Myweli Admin », policy « Admins ». No file in this repository describes it, and nothing read it after 2026-08-19. On 2026-11-13, while deploying the console, an anonymous `GET https://myweli-admin.pages.dev/main.dart.js` answered `200` with the whole bundle (5.17 MB), and so did each deploy's preview address: Access covered `admin.myweli.com` alone. Nobody could sign in from there (the API's preflight for that origin carries no `Access-Control-Allow-Origin`), but the console's code and its admin routes were public, probably since the Pages project was created. The owner added `myweli-admin.pages.dev` and `*.myweli-admin.pages.dev` to the application by hand that day. A hand edit in a dashboard can be undone by hand, by a Cloudflare change, or by a new application that shadows this one, and a read-back written in LAUNCH.md is true for a day (verification guardrails §7, §9).

**In scope:**
- A read-only script that asks each address once, as nobody, and says for each what came back (§3).
- A daily job in `production-checks.yml` whose red reaches the alarm issue (§4).
- A test that runs the real script against a local server, both ways, and holds the job's wiring (§7).

**Out of scope, and why:**
- **Managing Access as code** (Terraform or the API). It would need a Cloudflare token with Access rights in CI. CI's only Cloudflare token is `deploy-admin.yml`'s `CLOUDFLARE_API_TOKEN`, documented there as « Cloudflare Pages: Edit » (its real scope is visible only in the dashboard); giving CI one that can edit Access is what this avoids. An anonymous read needs no identity at all.
- **Fixing what it finds.** The fix is a dashboard edit by the owner; the message names it.
- **The API.** `api.myweli.com` is not behind Access, by design: its admin routes are guarded by the backend's own admin authentication (T66). This check is about the console's pages and code only.

## 2. UX, API, data model — not applicable

No screen, endpoint, contract or table changes. The only « user » is the person reading the alarm issue and the job log; §5 is their copy.

## 3. What it asserts (`infra/cloudflare/98-verify-console-access.sh`)

For each URL, **one** anonymous `GET`, redirects **not** followed (`curl -sS -o /dev/null --max-time 20 --retry 2 --retry-delay 5`; `--retry` covers timeouts, a failed DNS lookup (seen with curl 8.7.1) and 408, 429, 500, 502, 503, 504, never a refused connection). `-w` reads the status, the resolved `Location` and the `cf-mitigated` header, one per line (`%header{}` needs curl 7.84; `ubuntu-latest` has 8.5).

**Green for a URL only if both hold:**
1. the status is a redirect: `301`, `302`, `303`, `307` or `308`;
2. its `Location`, as curl resolves it, is `https://<team host>/cdn-cgi/access/login/<the requested host>`, the query ignored (`kid`, `meta` and `redirect_url` change on each request). The team host is compared to the whole authority, so a look-alike (`<team host>.evil.example`), a userinfo trick (`<team host>@evil.example`), a port or plain `http` are red. The path is compared whole, so the sign-in of **another** hostname is red.

The team host defaults to `blue-base-1ad1.cloudflareaccess.com`, the Zero Trust team domain every read on 2026-11-13 named.

**Every URL is checked before the script exits**, and each is reported, so one red line never hides a second. Exit `1` if any is red.

**The default list, six URLs: three hostnames, each at `/` and at `/main.dart.js`:**

| URL | Why this one |
|---|---|
| `https://admin.myweli.com/` | The custom domain, the address people use. Covered since before 2026-08-19 |
| `https://admin.myweli.com/main.dart.js` | The console's code. An Access application or a Bypass policy can be scoped to a path; protecting the page but not the bundle would leave the code public with `/` still green |
| `https://myweli-admin.pages.dev/` | The Pages project's own address, public until 2026-11-13 |
| `https://myweli-admin.pages.dev/main.dart.js` | The exact request that answered `200` with 5.17 MB on 2026-11-13 |
| `https://zz-access-probe.myweli-admin.pages.dev/` | The wildcard `*.myweli-admin.pages.dev`. Preview addresses are `<hash>.myweli-admin.pages.dev` and the hash changes with every deploy, so no real one can be written down for good. Access answers **before** Pages, so a fixed made-up label tests the wildcard rule itself: on 2026-11-13 it answered `302` to `…/cdn-cgi/access/login/zz-access-probe.myweli-admin.pages.dev`, like the real preview `3749e1e1.myweli-admin.pages.dev` |
| `https://zz-access-probe.myweli-admin.pages.dev/main.dart.js` | The same path argument, under the wildcard |

**Left out, on purpose:**
- **A real preview hash** (`3749e1e1.…` today): it changes with the next deploy, and the check would then probe an address nobody serves.
- **`main.myweli-admin.pages.dev`**: it falls under the same wildcard rule as the probe, so it tests nothing more about Access. It answered `302` on 2026-11-13; whether Pages serves anything there cannot be read from outside, since Access answers first.

**Red, and the line it prints (each starts `::error::`, so GitHub shows it as an annotation):**

| What came back | The line |
|---|---|
| `2xx` | « the console is PUBLIC at `<url>` », then the fix (§5) |
| a redirect to anywhere but the sign-in for this host | the code, where it pointed (query removed) and where it should have pointed, then the fix. If the path is right and only the host is a different `*.cloudflareaccess.com`, it adds that the team domain may have been renamed, and that the default in the script needs the new one |
| a redirect with no `Location` | the code and « no Location », then the fix |
| `404` on the probe | « Pages does not know this made-up address, so Access no longer answers before Pages there — the wildcard `*.myweli-admin.pages.dev` is gone, and every preview address is public », then the fix |
| any other status (`403`, `5xx` after retries, a `404` on another address) | « answered `<code>`: neither the Access sign-in nor the console. Red, but it does not show the console is public », then a look by hand (open the address in a private window, read « Myweli Admin », add the hostname back only if it is missing) and **no** « Fix: » line. When Cloudflare marked the answer `cf-mitigated`, it says so: a challenge of the machine running the check, not of the console's visitors |
| no answer at all (curl's `000`) | « could not reach `<url>` — nothing measured » with curl's error. **Red**: a check that measured nothing is not green (the `basemap` job's rule) |

**The fix names the hostname Access is configured with.** For the probe, that is the wildcard: « Fix: add `*.myweli-admin.pages.dev` back … », followed by « every preview address is public without `*.myweli-admin.pages.dev` » and « Do not put the probe's own name … in the application: that would turn this check green with every preview still public ». Adding `zz-access-probe.myweli-admin.pages.dev` itself to « Myweli Admin » would make Access redirect the probe to its own sign-in (green) while every real `<hash>.myweli-admin.pages.dev` stayed public. That is the one path by which following the check's own output could leave the console public with the check green, which is why the probe's fix never names the probe.

**If the wildcard goes**, the probe gets whatever Pages answers for an alias it does not know: a `404`, per the 2026-11-13 notes and per `https://zz-access-probe.cloudflare-docs.pages.dev/`, a Pages project with no Access, read the same day. The check does not depend on which: anything but the Access redirect is red, and §5 says what a `404` on the probe means.

**The rehearsal seam.** `CONSOLE_ACCESS_URLS` (URLs separated by spaces or newlines) and `CONSOLE_ACCESS_TEAM_HOST` replace the list and the team host, and the script says so on its first line. They exist so the test can reach every red branch against a local server; reaching them against production means removing Access. Set but empty, either one is refused rather than swapped for the default or read as « nothing failed ». No workflow may set either (§7).

**Read-only and anonymous by construction.** `curl` with `GET` and nothing else: no method flag, no body, no header, no cookie. A credential would let the request through Access and hide exactly what this asks.

## 4. Where it runs

The `access` job of `production-checks.yml`: daily at 06:00 UTC, and on `workflow_dispatch`. It checks out the repo to run the script, holds `permissions: contents: read` and nothing else (no issues, no id-token: like `cardphoto`, it reads public addresses), and has no secret. It is in `report.needs` and `clear.needs`, so a red run opens or comments the « Production checks are failing » issue mentioning the owner, and the alarm cannot close while it is red. Its result is on the issue's status line (« console access ») and the issue body carries one paragraph on it (§5).

It is a monitor, not a gate: Access changes in a dashboard, not on a merge.

## 5. What red means, and the fix

**Red means an address did not answer with the Access sign-in for itself.** Usually the console is public there; a `403`, a `5xx` or a `404` off the probe shows nothing public, and says so; `000` means nothing could be read. The paragraph in the alarm issue, and each error line, say:

- **A `200` (or any `2xx`):** the console is public at that address. Add the hostname back to the Access application « Myweli Admin » in the Cloudflare dashboard (Zero Trust → Access → Applications), policy « Admins » unchanged — [DEPLOYMENT.md](../DEPLOYMENT.md) « Restrict ». Then re-run the job.
- **A `404` (or a `2xx`) on `zz-access-probe`:** the wildcard `*.myweli-admin.pages.dev` is gone from the application, so every real preview address is public. Add `*.myweli-admin.pages.dev` back, **never the probe's own name**: that would turn this check green with every preview still public.
- **A `403`, a `5xx`, or a `404` on another address:** neither the console nor the sign-in answered. Not proof of exposure: open the address in a private window and read « Myweli Admin » before editing Access, and add the hostname back only if it is missing. A `403` marked `cf-mitigated` is Cloudflare challenging the machine that ran the check (§8).
- **A redirect to another `*.cloudflareaccess.com`, right path:** the team domain was renamed. Nothing is public; update the default team host in the script, in a PR.
- **`000`:** re-run the job. If it stays red, look at the address by hand.

## 6. Security

- **No identity, no secret, no write.** The job's token can read the repo's contents and nothing else. The script cannot change anything anywhere: a `GET` to a public address.
- **Threat model.** No new surface or trust boundary: it adds a daily read of an existing control. The control itself (Access in front of the console) has no row in [BACKEND.md](../BACKEND.md) §7, because the backend never relies on it (T66: the admin login is throttled and checked by the API whatever Access does).
- **Logs.** The error lines print `Location` without its query, so the `meta` and `kid` values Access puts there never reach a job log.

## 7. Testing plan (`backend/test/infra/console_access_check_test.dart`)

It runs the **real** script with `bash`, against a local `HttpServer` (`dart:io`) through the two overrides, with only `PATH` from outside, and asynchronously (a synchronous spawn would block the server it calls):
- **Green:** a `302` to `https://<team>/cdn-cgi/access/login/127.0.0.1?…`, and the same for `301`, `303`, `307`, `308`.
- **Red, each with its line:** `200` (« PUBLIC », « Myweli Admin », « Restrict », the fix naming that very hostname and no probe note); a redirect to another host; Pages' own relative redirect; the team host but another hostname's sign-in; a login path that only starts with the right hostname; a look-alike host; a userinfo host; plain `http`; a renamed team domain (and its hint); a redirect with no `Location`; a closed port (« nothing measured »).
- **Red, nothing shown public:** a `404` and a `403` from the local server say « neither the Access sign-in nor the console », « does not show the console is public » and « Look by hand », with no « Fix: » line; a `403` with `cf-mitigated: challenge`, read through the real curl, is named as a challenge.
- **All are checked:** a bad URL first, then good ones, then a second bad one: exit `1`, both bad named, both good reported, « 2 of 4 ».
- **Vacuity:** a list of spaces only is refused, an empty team host too, and either variable set but empty is refused with no request made (never swapped for the production list).
- **The default list, against a stand-in `curl`** that logs each call and answers as Access does: with no override, the script asks for exactly the six URLs of §3, in that order, never with `-L`, and is green; the same stand-in answering `200` for `myweli-admin.pages.dev` turns it red, with that hostname's fix and no wildcard. Answering `404` or `200` for the probe, the fix names `*.myweli-admin.pages.dev`, says every preview is public, warns off the probe's own name and never says « add zz-access-probe »; a `404` there says the wildcard is gone; a `403` there asks for a look by hand at the wildcard. This holds the list, the default team host and the probe's fix without touching production.
- **Wired:** the job exists, checks out before it runs exactly `bash infra/cloudflare/98-verify-console-access.sh`, holds `contents: read` only, sets no env; no workflow assigns either override; the job's result is in `report`'s env and status line, and the body, read as the issue reads it, names the fix, the wildcard rather than the made-up name, that a `403`, a `5xx` or a `404` elsewhere shows nothing public, and `cf-mitigated`. The script is executable and names no credential.

`production_alarm_test.dart` already derives `report.needs` and `clear.needs` from the jobs in the file, and `web/tests/production-alarm-status.test.ts` derives the status line, so both hold the new job with no edit.

**Watched red** before merge: each mutation listed in §9 step 2, on committed code, restored with `git checkout` and the tree read back clean after each.

## 8. What it cannot see

Stated so nobody reads it as more (verification guardrails §12):
- **Who the policy lets in.** An anonymous request sees that Access answers, not what « Admins » allows. A policy widened to « Everyone » or to any e-mail with a one-time PIN still sends visitors to the sign-in, and stays green.
- **A new address.** A second Pages project, a new custom domain, or the bundle copied anywhere else is not on the list.
- **Other paths.** It reads `/` and `/main.dart.js`. A Bypass policy on, say, `/assets/*` would not show. The bundle is the part that matters, and it is read.
- **The hours between runs.** Once a day: a hostname removed at 06:05 UTC is public until the next morning.
- **Whether GitHub's network gets the same answer as a laptop.** Measured from the owner's Mac only until the first run on GitHub. If Cloudflare ever challenges GitHub's addresses, the job goes red with a `403`. That is red for the wrong reason, and the log says so: it shows nothing public, asks for a look by hand before any Access edit, and names the challenge when Cloudflare marks the answer `cf-mitigated`. A challenge without that header reads as any other `403`.

## 9. Rollout

1. The branch carries the script, the job, the test and these docs.
2. ~~Mutations on committed code~~ **Done 2026-11-13: 16 of 16 red**, each on the test it was aimed at:

   | Mutation (one edit) | Fell |
   |---|---|
   | `2xx` read as green | « 200: the console is PUBLIC there », « a bad one first… », « a public address in the production list » |
   | the `Location` host check dropped | look-alike, userinfo, port, foreign host, renamed team |
   | the path check dropped | another hostname's sign-in, a prefix, a longer path |
   | `000` read as green | « no answer at all », « a bad one first… » |
   | stop after the first failure | « a bad one first… », « a public address in the production list » |
   | the wildcard probe dropped from the defaults | the three default-list tests |
   | `access` removed from `clear.needs` | `production_alarm_test` « clear hears from every other job in the file »; `console_access_check_test` « a red run reaches the alarm » |
   | `-L` added to curl | 16 tests, green and red |
   | a plain-`http` `Location` accepted | « plain http to the team host » |
   | `Location` printed with its query | the five cases whose `Location` carries one |
   | `:-` instead of `-` for the list | « a variable set but empty is refused » |
   | `myweli-admin.pages.dev/main.dart.js` dropped from the defaults | the three default-list tests |
   | the job overrides the list inline | « runs exactly the script », « sets no variable » |
   | `access` removed from `report.needs` | `production_alarm_test` « report hears from every other job in the file »; `console_access_check_test` « a red run reaches the alarm » |
   | « console access » dropped from the status line | « a red run reaches the alarm » |
   | the job's `permissions` block removed | « holds contents: read and nothing else » |

   **After the review, 2026-11-13: 9 of 9 red** on `31d55c21`, in `console_access_check_test`, each restored and the tree read back clean:

   | Mutation (one edit) | Fell |
   |---|---|
   | the probe's fix built from the probe's own name, not the wildcard | the four probe tests (`404`, `200`, `403`, « says the wildcard is gone ») |
   | a `404` on the probe read like any other `404` | the probe `404` tests |
   | the « add back » fix printed again for a `403`, a `5xx` or a `404` elsewhere | « 404 on an address that is not the probe », « 403 », the challenge, the probe `403` |
   | `cf-mitigated` no longer read by curl | « a Cloudflare challenge of the runner is named as one » |
   | the probe note (every preview, never the probe's name) dropped | the probe `404` and `200` tests |
   | the probe note printed for every hostname | « 200 on a real hostname: its fix names that hostname, no probe note » |
   | every hostname mapped to a wildcard | five tests, among them « a public address in the production list » |
   | the alarm paragraph naming the probe as the fix | « a red run reaches the alarm » |
   | the alarm paragraph calling a `403`, a `5xx` or a `404` elsewhere proof of exposure | « a red run reaches the alarm » |
3. ~~Live, from the owner's Mac~~ **Done 2026-11-13, 10:35 UTC**: the defaults all six green, each `302` to the sign-in of its own hostname; the list overridden to `https://myweli.com/` → red « the console is PUBLIC at https://myweli.com/ » (200); to `https://cloudflare-docs.pages.dev/` → red, « answered 404 »; to `https://127.0.0.1:9/` → red, « could not reach … — nothing measured » (curl 7). **Again after the review, 10:59 UTC**: the defaults all six green; `https://cloudflare-docs.pages.dev/` → red, « answered 404: neither the Access sign-in nor the console », the look by hand and no « Fix: » line; `https://zz-access-probe.cloudflare-docs.pages.dev/` → red, « the wildcard `*.cloudflare-docs.pages.dev` is gone » and « Fix: add `*.cloudflare-docs.pages.dev` back ».
4. Merge. Until then the 06:00 schedule runs `main`'s file, which has no `access` job; the first scheduled run after the merge is the first daily one. A `workflow_dispatch` on the branch before merging would read it from GitHub's network, on the owner's say. **Merging it starts `deploy-backend.yml`**, because the new test lives under `backend/`, one of its push paths. With `infra/gcp/staging.state` at `absent`, that run builds and pushes an image tagged with the merge SHA and runs the pin and emitter checks against production; it deploys nothing. The production promotion names its `image_tag` on purpose, so the new tag changes nothing there.

## 10. Definition of done

- [x] `dart format` clean · `dart analyze --fatal-infos --fatal-warnings` = 0 · `backend/test/infra/` green · the whole backend suite green (at `83b30945`; after the review fixes, `backend/test/infra/` only).
- [x] Every mutation of §9 step 2 watched red, the review's nine included.
- [x] LAUNCH.md (the Access box), DEPLOYMENT.md « Restrict », `deploy-admin.yml`'s header, `infra/cloudflare/README.md`, the spec index and a roadmap entry ([2026-11-13](../roadmap/entries/2026-11-13-console-access-daily-check.md)) updated in the same PR.
- [ ] Feature branch + PR; CI green; no Claude attribution.
- [x] After merge: the first run read in the job log, not only its conclusion (run 43422200006, a dispatch, 2026-11-13: six 302s to the right sign-in); and the « not merged » status lines (this spec's Status, the row in [README.md](README.md), the roadmap entry's first line) set to merged, with the PR number and SHA.

## 11. Open questions

None.
