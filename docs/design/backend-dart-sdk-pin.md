# Backend — the Dart SDK pinned at the TLS advisory floor (GHSA-frr6-h895-5pxp)

| | |
|---|---|
| **Status** | Built, not merged. Production is **not** redeployed by this change (§10). |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-10 |
| **PRD ref / phase** | Security, cross-cutting · V1 |
| **ROADMAP entry** | [2026-11-10-backend-dart-sdk-pin.md](../roadmap/entries/2026-11-10-backend-dart-sdk-pin.md) |
| **Skills checked** | myweli-backend-guardrails · myweli-verification-guardrails |
| **Governs** | `backend/Dockerfile` · `.github/workflows/ci.yml` (both backend jobs) · `.github/workflows/deploy-backend.yml` (the image check) · `.github/scripts/verify-image-dart-sdk.sh` · `.github/dependabot.yml` · `backend/test/infra/dart_sdk_pin_test.dart` |

Every claim below is marked **read** (observed, with how) or **inferred** (and
from what). Nothing here was changed in the cloud. The investigation was
read-only, on 2026-11-10.

## 1. Goal & scope

**Goal.** The server is built by an SDK that cannot fall below the first
release that blocks the compromised eMudhra intermediates. CI tests on that
same SDK. A build that drifts from either rule fails a PR. And nothing reaches
Cloud Run through the deploy workflow without its binary having been read as at
or above the floor.

**In scope.**
- Pin `backend/Dockerfile` to `dart:3.13.7@sha256:854f3c50…` and
  `dart_frog_cli 1.2.14`.
- Move CI's backend jobs from 3.10.7 to 3.13.7.
- A guard test; a deploy step that reads the SDK out of the built image
  (§8); a Dependabot `docker` entry; a rollback floor in
  [infra-rollback.md](infra-rollback.md).
- The one defect 3.13.7's analyzer found (§6.2).

**Out of scope, named in §11.** The Android apps (Flutter < 3.47.8 is
affected). Removing eMudhra roots from the image's bundle. A monitor that reads
the serving binary's SDK every day. Rehearsing the first OCI-index image on
Cloud Run.

## 2. The advisory, read

Source: `gh api repos/dart-lang/sdk/security-advisories/GHSA-frr6-h895-5pxp`
(published 2026-10-23T18:51:07Z, severity high, CWE-295). Fix commits read via
the GitHub API.

**What is compromised: intermediates, not roots.** Eight intermediate CA
certificates issued by eMudhra have private keys that can be derived (weak key
generation entropy). Anyone on the network path can mint a certificate for any
domain that chains through one of them.

**Where verification happens.** On Android, Windows and Linux, `dart:io`
verifies chains with the BoringSSL compiled into the program. Web, iOS and
macOS use the browser or Apple's `Security.framework` and are not affected.

**What the fix is.** 3.13.7 is 3.13.6 plus two commits and the version bump
(read with `gh api repos/dart-lang/sdk/compare/3.13.6...3.13.7`):

- `ecb2c83516` rolls BoringSSL to `c7eb007fd106`. That roll includes BoringSSL
  `dd682072baab`, « Block a handful of intermediate certificates », which adds
  `check_blocklist()` to `X509_verify_cert` in `crypto/x509/x509_vfy.cc`. It
  hashes the SPKI of every certificate in the built chain and compares it with
  **eight** hard-coded SHA-256 values. A match raises
  `X509_V_ERR_CERT_REVOKED`. This is in the verifier, so it holds **whatever
  the root store contains**.
- `a9e26a21af` makes Android 14+ load roots from the updatable Conscrypt APEX.
  This only matters on Android.

**Root store vs built-in roots, on Linux.** Read in
`runtime/bin/security_context_linux.cc` at tag `3.13.7`, `dart:io` loads its
root store from the first of these that exists:

1. a file: `/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt`, …;
2. a directory: `/etc/ssl/certs`, …;
3. only if none exists, the roots compiled into the binary.

So on Linux the system CA bundle **is** the root store. The compiled-in roots
are a last resort. The blocklist sits in the verifier, after the store.

**The Linux condition, and a wrinkle in the advisory.** The advisory says
Linux is affected only where the system `ca-certificates` bundle has « not
[been] updated … to remove the affected roots », for example in static
containers. But what is compromised are intermediates, and a CA bundle holds
roots. The only fix a bundle could carry is removing the eMudhra **roots**
themselves. Debian has not done that (§3.1): the bundle in the newest
`dart:3.13.7` image still trusts all three. Today, then, a refreshed bundle
fixes nothing. The SDK is the fix.

## 3. What production runs

### 3.1 Read on 2026-11-10

| Fact | Value | How it was read |
|---|---|---|
| Serving revision | `myweli-api-00048-9f4`, 100 %, `latestRevision: true` (no pin) | `gcloud run services describe myweli-api` → `status.traffic` (not `spec.template`, not `latestReadyRevisionName`, which lie after a pin) |
| Image | `europe-west9-docker.pkg.dev/myweli/myweli/api@sha256:a9c536eaec39c568373776621754bf52ad542c11ca3913a64eb678ffc0a6f877`, tag `4e78e48` | `gcloud run revisions describe` + `gcloud artifacts docker tags list --filter=version:…` |
| Built | 2026-11-03T12:41:46Z, by run 41637727028 (push of `4e78e48`) | Artifact Registry `createTime`; the image config's `created` agrees |
| Deployed | 2026-11-10T00:55:57Z, by dispatch run 42731941335 (a promotion of that tag) | revision `creationTimestamp` |
| Base image | `dart:stable@sha256:517cbeb4612c4dff11c983edea521d5aef3f47a674c23684fad5e89803ca5b1c` | build log: `#6 [build 1/7] FROM docker.io/library/dart:stable@sha256:517c…` |
| …which is | Dart **3.13.7**, Debian trixie snapshot, built 2026-10-28 | Docker Hub registry API: the amd64 config's history downloads `release/3.13.7/sdk` |
| **Binary's own SDK** | `Dart 3.13.7 (stable) (Thu Oct 22 14:28:57 2026 -0700) on "linux_x64"` | Read-only pull of the image's last layer (`/app/bin/server`) from Artifact Registry, then `strings` |
| CA bundle | `/etc/ssl/certs/ca-certificates.crt`, 148 certificates, dated 2026-10-28. It includes **emSign Root CA - G1, emSign Root CA - C1, emSign ECC Root CA - C3** (eMudhra) | The image's first layer, extracted, then `openssl x509 -subject` on each certificate |
| Trust bypass in code | none: no `badCertificateCallback`, `onBadCertificate` or custom `SecurityContext` in `backend/lib`, `routes`, `main.dart` | grep |

**The control (does the version read discriminate?).** The previous revision,
`00047-55v` (image `a0ee1cd`, built 2026-10-25), also reads 3.13.7, so it
proves nothing on its own. `00046-bzg` (image `eca4db6`, built 2026-10-22)
reads **3.13.6**. The read tells versions apart.

**The newest `dart:3.13.7` digest** is `854f3c50…b215` (built 2026-11-05,
Debian snapshot `@1793827419`). It is what both `dart:3.13.7` and `dart:stable`
resolve to today, and the newest merge build (`45a5d0f`, run 42877442610)
already used it. Its CA bundle is **byte-identical** to production's (`cmp`).

**Exposure window (inferred from the reads above).** Production verified TLS
with a pre-3.13.7 SDK up to `00047`'s creation, 2026-10-25T22:43Z. That is
about 52 hours after the advisory was published, and an unknown time after the
compromise itself (the advisory says only « October 2026 »). Exploiting it
needed an attacker on the path between Cloud Run's egress and Apple, Google or
Cloudflare. Nothing in this repo can tell whether that happened. **Unverified,
and not verifiable from here.**

### 3.2 Reading an image's SDK — read-only, repeatable

Use this before a rollback pin or an `image_tag` promotion to anything older
than `a0ee1cd`. It needs only Artifact Registry read access, and it relies on
the Dockerfile's last `COPY` being the server binary.

```bash
R=https://europe-west9-docker.pkg.dev/v2/myweli/myweli/api
DIGEST=sha256:…   # gcloud run revisions describe <rev> --region europe-west9 --format='value(spec.containers[0].image)'
AT=$(gcloud auth print-access-token); D=$(mktemp -d)
LAYER=$(curl -sS -H "Authorization: Bearer $AT" \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' \
  "$R/manifests/$DIGEST" | python3 -c 'import json,sys;print(json.load(sys.stdin)["layers"][-1]["digest"])')
curl -sSL -H "Authorization: Bearer $AT" "$R/blobs/$LAYER" | tar -xz -C "$D"
strings -a "$D/app/bin/server" | grep -m1 'on "linux_x64"'   # want ≥ 3.13.7
```

## 4. Decision: pin version **and** digest

Production was patched by timing, not by design. `FROM dart:stable` resolved
to 3.13.7 on the days `a0ee1cd` and `4e78e48` were built. Four ways the next
build could have gone below the floor:

1. **The Dockerfile's own advice.** Its comment said « Pin `dart:3.10` (or a
   digest) for fully reproducible prod builds ». Followed today, that ships the
   vulnerable verifier.
2. **A rollback or promotion** of any revision or tag from before `a0ee1cd`
   (§3.1; [infra-rollback.md](infra-rollback.md) §0 now says so).
3. **A floating tag**, which answers whatever Docker Hub serves that minute.
4. **CI compiled with 3.10.7.** No test ever ran on the compiler that ships,
   so nothing would notice a difference between the two.

**The pin.** `FROM dart:3.13.7@sha256:854f3c50b1cbd4a5a54c9fa67d4f5b6702ac49b4a26d21a80e7712a72528b215 AS build`.
The version is for humans and for the guard. The digest is for
reproducibility: when both are given, Docker resolves by digest. The digest
chosen is the newest 3.13.7 build, the base the newest image already uses
(§3.1).

**`dart_frog_cli 1.2.14`**, the version CI's boot smoke already uses. Before,
the image took whatever pub.dev served that day. That is the same class of
floating input.

**Rejected: refresh the CA bundle in the Dockerfile** (`apt-get install
--only-upgrade ca-certificates` before the copy). It reintroduces a
build-time-dependent input, which is exactly what the pin removes. And today it
would change nothing: Debian's bundle still has the emSign roots (§2).

**Not taken, offered (§11): drop the three emSign roots from the image's
bundle.** This is defence in depth against intermediates under those roots
that nobody has disclosed yet. No endpoint in §7 chains to eMudhra as far as
anyone knows (**unverified**: the chains were not inspected). It means
maintaining a custom trust store, against an advisory the SDK already closes.

## 5. Keeping the pin fresh

A pin freezes two things: the SDK, and the base's `/etc/ssl/certs`. The bundle
now changes only when the digest does.

- **Dependabot `docker` on `/backend`, weekly.** A new Dart patch release
  arrives as a PR. **Unverified:** whether Dependabot also proposes a new
  digest under the *same* tag (the official image is rebuilt for Debian
  updates, as 3.13.7 was on 2026-11-05). If it does not, a bundle refresh
  without a version bump stays a manual bump.
- **Such a PR is red on purpose** until ci.yml's `sdk:` follows in the same PR.
  `dart_sdk_pin_test` says exactly that in its failure message. This is the
  price of rule 3 in §8.

## 6. CI alignment, and what 3.13.7 found

CI's two backend jobs (`backend`, `backend-boot-smoke`) move from 3.10.7 to
3.13.7. Run locally with the official 3.13.7 macOS arm64 SDK (sha256 checked
against `dart-archive`'s `.sha256sum`):

### 6.1 The formatter

3.13.7's formatter rewrites six files: test and smoke-tool files only, all
`expect(x, [ … ], reason: …)` call layouts. Reformatted in this change.

**Consequence for local work.** Dart 3.12.2, the one bundled with this
machine's Flutter, **accepts the old layout and rejects the new one**. After
this change, run `dart format` on `backend/` with 3.13.7, not with Flutter's
`dart`. The same applies to `dart_frog build`: mason compiles its hooks with
whichever `dart` is first on `PATH`. A mismatch fails with « Invalid kernel
binary format version (expected 138, found 130) ». That is local only: inside
the image there is one SDK.

### 6.2 The analyzer: a real defect

`warning • unawaited_return_in_try_block` at
`lib/src/messaging/messaging_service.dart:54`. `sendTemplate` documents
« returns the stored row, or null when skipped/failed-to-record (never
throws) ». But it returned `_outbox.append(…)` un-awaited from inside its
`try`. A failed outbox write, a Future that completes with an error, settles
after the `try` has exited, and the error reaches the caller.

**Proved before it was fixed.** A new test in `messaging_test.dart` uses an
outbox whose `append` fails asynchronously. Run against the unfixed code, it
went red: the `StateError` surfaced at `MessagingService.sendTemplate`. With
`return await`, it is green.

**Impact today: none in production.** `MESSAGING_PROVIDER=disabled`
(`infra/gcp/service.yaml`). The defect would have surfaced the day messaging is
switched on.

## 7. Outbound TLS through `dart:io` — the inventory

Every one of these is verified by the binary's BoringSSL against
`/etc/ssl/certs/ca-certificates.crt`. Hosts are read from code. Hosts that sit
in secrets were not read.

| Purpose | Host | Code | Live in prod? |
|---|---|---|---|
| Google sign-in — JWKS | `www.googleapis.com/oauth2/v3/certs` | `auth/id_token_verifier.dart` → `jwks_cache.dart` | yes (`AUTH_METHODS=google,apple,email`) |
| Apple sign-in — JWKS | `appleid.apple.com/auth/keys` | same | yes |
| Apple — code exchange, revoke on deletion | `appleid.apple.com/auth/token`, `/auth/revoke` | `auth/apple_tokens.dart` | yes |
| FCM — OAuth token | `oauth2.googleapis.com/token` | `push/access_token_source.dart` | yes (`FCM_*` set) |
| FCM — send | `fcm.googleapis.com/v1/projects/…/messages:send` | `push/fcm_v1_push_provider.dart` | yes |
| R2 — HEAD/PUT/DELETE (presigned) | `<account>.r2.cloudflarestorage.com` | `storage/storage_service.dart`; deletes in `provider_account_service.dart`, `privacy/user_erasure_service.dart`, `demo/demo_reset_service.dart` | yes |
| E-mail | `api.resend.com` | `email/resend_email_provider.dart` | yes (`RESEND_API_KEY`) |
| Error reporting | the `SENTRY_DSN` host (a secret, not read) | `sentry` package, `observability/error_reporter.dart` | yes |
| Web rebuild hook | `WEB_DEPLOY_HOOK_URL` (a secret, not read) | `site/site_rebuild_notifier.dart` (raw `HttpClient`) | yes |
| SMS / WhatsApp | `api.twilio.com`, `api.ng.termii.com` | `messaging/*_messaging_provider.dart` | **no**: `MESSAGING_PROVIDER=disabled` |

**Not `dart:io` TLS.** Postgres goes to `127.0.0.1:5432` (per the
`service.yaml` comment; the `DATABASE_URL` secret was not read). There
`database.dart` selects `SslMode.disable`, and the `cloud-sql-proxy` sidecar
(Go, not Dart) encrypts the hop. Inbound traffic is terminated by Google's
front end behind the Cloudflare Worker.

## 8. Security, and the guard

Threat-model row **T81** ([BACKEND.md](../BACKEND.md) §7): **S/I**. An on-path
attacker presents a forged certificate for Apple, Google, FCM, R2, Resend or
Sentry. With it they can read or alter sign-in keys, push tokens, uploads and
e-mail.

**Two guards, because the first one reads a tag and Docker builds a digest.**

`backend/test/infra/dart_sdk_pin_test.dart` (on every PR) parses the
Dockerfile with comment lines stripped, as Docker reads it, and parses the
workflows as YAML. It enforces four rules:

1. the single `FROM dart…` stage is `dart:X.Y.Z@sha256:<64 hex>`;
2. `X.Y.Z ≥ FLOOR`. The floor lives in one place, `FLOOR=` in
   `.github/scripts/verify-image-dart-sdk.sh`, and the floor itself may never
   be below 3.13.7;
3. every job whose `working-directory` is `backend` sets up exactly `X.Y.Z`,
   and `dart_frog_cli` is pinned in the image and equal to CI's. Both backend
   jobs must exist, so the comparison cannot pass over an empty set;
4. the deploy workflow runs the image check after `id: build` and before
   `gcloud run services replace`, with no `if:`, on
   `steps.build.outputs.image`.

**The blind spot of rules 1–2** (verification §12): `dart:3.13.7@sha256:<a
3.13.6 digest>` satisfies both, and builds 3.13.6. Only the built bytes can
see that. **`.github/scripts/verify-image-dart-sdk.sh`** (on every deploy run)
works read-only. It fetches the image's manifest (an OCI index is resolved to
its `linux/amd64` entry), streams the last layer, which is `/app/bin/server`,
and greps the VM's version string. It refuses anything that is not
`Dart X.Y.Z (stable)` with `X.Y.Z ≥ FLOOR`. It fails closed: an unreadable
manifest, layer or version is a refusal. A promotion (`image_tag`) builds
nothing, so this is its only SDK check, and it is what turns the rollback floor
into a mechanism for [infra-rollback.md](infra-rollback.md) §4.3. A §4.1
traffic pin still bypasses it.

**It was run locally, read-only, against real images.** Results:
`4e78e48` (production, plain Docker manifest) passed at 3.13.7.
`eca4db6` (`00046`) was refused at 3.13.6. `45a5d0f` (the next promotion
candidate, an **OCI index**) passed at 3.13.7. A bare tag, and a digest that
does not exist, both failed closed. The first draft accepted image manifests
only, and failed closed on the newest build: `45a5d0f`, built on
`ubuntu-26.04`, is an index, while `4e78e48` and `a0ee1cd`, built on
`ubuntu-24.04`, are plain manifests (runner image read from each run's log). So
it would presumably have refused every build from the new runner. The index
case was found by running the script against the newest image, not by reading
it.

**Which event turns them red** (verification §15): a downgrade, a channel tag,
a missing digest, an unpinned CLI, one file bumped without the other, a floor
lowered under 3.13.7, the check moved after the deploy or made conditional, or
a built binary below the floor. All of these are defects. Bumping the
Dockerfile and ci.yml together is the repair, and it stays green.

## 9. Testing — what was run

- `dart_sdk_pin_test`: 9 green. **Mutations watched red** are listed in the
  commit message.
- `verify-image-dart-sdk.sh`: five real cases, read-only (§8).
- `messaging_test`: the new test red on the unfixed code, then 8/8 green.
- Whole backend on **3.13.7**: format clean (433 files), analyze 0 issues,
  `dart test` 2073 passed and 10 skipped. The 10 are the Postgres-backed tests,
  which skip without `DATABASE_URL`; CI runs them against its database.
- The Dockerfile's build steps, rehearsed on 3.13.7: `pub global activate
  dart_frog_cli 1.2.14` → `dart_frog build` → `dart compile exe`. They produced
  a binary that reports 3.13.7. This ran on macOS arm64 in a scratch copy with
  its own pub cache. **The `linux/amd64` image itself was not built here**
  (Docker was not running). Its first build is the push to `main` after merge.

## 10. Rollout

- **Merging deploys nothing.** `infra/gcp/staging.state` reads `absent`, so
  the push run builds and pushes an image and runs the pin checks, now
  including the image SDK check, and that is all. That run is also the first
  real build of the pinned Dockerfile, and the first time the new step runs
  with the deployer's credentials. Locally it ran with the owner's.
- **Production needs no redeploy for this advisory.** It already serves
  3.13.7 (§3.1). Promoting the next image is a routine release, and per the
  standing rule it waits for the owner's yes.

## 11. Open questions & follow-ups

1. **The Android apps (out of scope here, likely the larger exposure).** CI
   builds them with Flutter **3.44.9**, below the fixed 3.47.8. Their
   `dart:io` traffic on Android is affected; iOS and web are not.
2. **Drop the emSign roots from the image's bundle?** §4 gives the case for
   and against. Owner's call.
3. **A monitor for the serving SDK.** For a §4.1 traffic pin the rollback
   floor is still a sentence (verification §9). A daily check could run
   `verify-image-dart-sdk.sh` against `status.traffic`'s digest. It needs
   Artifact Registry read access for the checks' service account, which is a
   cloud IAM change and the owner's to make.
4. **The next promotion ships an image format production has never run.**
   Merge builds since `ubuntu-latest` moved to 26.04 push an **OCI image
   index** (the amd64 image plus a BuildKit attestation manifest); `4e78e48`,
   which is serving, is a plain Docker v2 manifest. Cloud Run is expected to
   resolve the index to its `linux/amd64` entry. **Unverified**: staging is
   absent, so nothing has rehearsed it. The first production promotion of
   `45a5d0f` or later is that rehearsal, unless the deploy job pins
   `runs-on: ubuntu-24.04` or builds with `--provenance=false`. Owner's call.
