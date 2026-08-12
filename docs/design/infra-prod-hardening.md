# Production hardening — phase 2

| | |
|---|---|
| **Module** | infrastructure (`myweli` / `europe-west9`) + `backend/` + CI |
| **Status** | **Complete.** Six findings: four fixed in code/CI, two applied to the live project. |
| **Related** | [infra-staging.md](infra-staging.md) §7 · [LAUNCH.md](../LAUNCH.md) · [BACKEND.md](../BACKEND.md) §7 |

Designing staging required auditing the live GCP project, and that audit found
six defects in **production** having nothing to do with staging. They were
deferred here so staging would not discover them by accident, at the worst
moment.

This document records **what was actually done**, including where the original
diagnosis was wrong — three of the six were misdiagnosed, and two of the
proposed fixes would have caused an outage.

---

## 1. Outcome

| # | Finding | Verdict on inspection | Fix | Where |
|---|---|---|---|---|
| 1 | `deletionProtectionEnabled: false` | confirmed | `gcloud sql instances patch` | §3.1 |
| 2 | `CRON_SECRET` a plaintext Scheduler header | confirmed, **understated** | **code** — verify the OIDC token | [#352](https://github.com/Zaslons/myweli/pull/352) |
| 3 | Public IP + weak SSL | **half wrong** — the IP is load-bearing | SSL only, via `gcloud` | §3.2 |
| 4 | FCM prunes push tokens on any 400 | confirmed, and a **security bug** | **code** | [#351](https://github.com/Zaslons/myweli/pull/351) |
| 5 | Connection ceiling breached on paper | confirmed; **proposed fix would restart and OOM** | **code** — lower the pool | [#353](https://github.com/Zaslons/myweli/pull/353) |
| 6 | `deploy-admin.yml` auto-deploys to prod | confirmed — **89 production deploys** | **CI** | [#354](https://github.com/Zaslons/myweli/pull/354) |

**Only two of the four "cloud" findings were cloud changes.** The other two were
code, and in both cases the obvious `gcloud` fix was the wrong one.

---

## 2. The three corrections

Recorded because a wrong diagnosis that gets quietly rewritten teaches nothing.

### 2.1 The FCM trigger (§3.1 of the staging spec)

**Claimed:** pointing production at the staging Firebase project would delete
every push token.

**Actually:** a wrong project returns **403** `PERMISSION_DENIED` /
`SENDER_ID_MISMATCH`, which the provider already counted as a failed send. That
path was correct.

**What was true is worse.** `_isInvalidToken` substring-matched
`INVALID_ARGUMENT`, and FCM v1 carries that string in `error.status` for *every*
400 — so it was functionally `if (statusCode == 400) return true`. Since the
payload is identical per token in the fan-out, any payload-level 400 pruned
**all** of them. And `businessName` had no length bound while being interpolated
into every booking push, so **a salon owner could delete the push tokens of
every client who booked with them.** Recorded as **T62** in BACKEND.md §7.

### 2.2 The public IP is load-bearing — do NOT remove it

**Claimed:** Cloud SQL has an unnecessary public IP.

**Actually:** it is the only path from the backend to the database. The
`cloud-sql-proxy` sidecar runs with **no `--private-ip` flag**, and the Cloud Run
service has **no VPC egress at all** — no connector, no `network-interfaces`.
`service.yaml`'s own comment says the sidecar was chosen "over private IP
because that needs a VPC on day one." `--no-assign-ip` would have taken
production down.

The exposure is also narrower than recorded: `authorizedNetworks` is **empty**,
so port 5432 from the internet is already refused. Only the SSL half was real,
and only that half was applied (§3.2).

### 2.3 Patching `max_connections` would have caused an outage

**Claimed fix:** raise the flag to 100.

**Actually:** it `requiresRestart: true` on a **ZONAL** instance with no replica,
and the app has **no connection retry** — `main.dart` awaits
`initializeDatabase()`, which takes an advisory lock, and `connectTimeout` is a
deadline rather than a grace period. A restart could kill revisions rather than
stall them. And 100 backends at ~8 MB each needs ~800 MB against the instance's
**0.6 GB**, trading a connection ceiling for an OOM.

Fixed in code instead: `maxConnectionCount` 8 → 4. Zero downtime.

---

## 3. What was applied to the live project

Two commands. Both metadata-only: **no restart, no dropped connections.**

### 3.1 Deletion protection

```bash
gcloud sql instances patch myweli-db --project=myweli --deletion-protection
```

| | value |
|---|---|
| before | `deletionProtectionEnabled: False` · backups `True` · PITR `True` · `RUNNABLE` |
| after | `deletionProtectionEnabled: True` · `RUNNABLE` |
| production | `/health` ok throughout |

Note on the original write-up: there is **one** such setting in gcloud, not two.
`--deletion-protection` writes `settings.deletionProtectionEnabled`; there is no
top-level field. The genuine second knob is Terraform's client-side
`deletion_protection`, and this repo has no `.tf` files.

Deleting the instance now requires `--no-deletion-protection` first — which is
the point.

### 3.2 SSL mode

```bash
gcloud sql instances patch myweli-db --project=myweli --ssl-mode=ENCRYPTED_ONLY
```

| | value |
|---|---|
| before | `sslMode: ALLOW_UNENCRYPTED_AND_ENCRYPTED` · `ipv4Enabled: True` · `authorizedNetworks:` *(empty)* |
| after | `sslMode: ENCRYPTED_ONLY` · `RUNNABLE` |
| production | `/health` ok **and `/providers` returning rows** |

That second check is the one that matters: `/health` never touches the database,
so only a real query proves the proxy path survived.

Safe because the backend reaches the instance through the Cloud SQL Auth Proxy
on port 3307 — IAM auth with an ephemeral client certificate, always TLS. The
`SslMode.disable` in `database.dart` governs only the loopback hop to the
sidecar, which the instance never sees.

**Not** `TRUSTED_CLIENT_CERTIFICATE_REQUIRED` — that demands client certs the
proxy does not present in this configuration.

Per Google: enforcing SSL does not restart the instance, and applies only to
**new** connections. Existing unencrypted sessions would stay connected; there
are none here, since the only client is the proxy.

---

## 4. Deliberately not done

- **Removing the public IP** — §2.2. It is the only route to the database.
- **Patching `max_connections`** — §2.3. Restart + OOM.
- **Removing `allUsers` from `roles/run.invoker`** on Cloud Run. It would make
  the OIDC token actually enforced at the infrastructure layer, and it would
  **break the entire public API**: the same `myweli-api` service serves the
  mobile and web clients through `api.myweli.com`. That is why finding 2 is
  fixed in the application instead.
- **Removing the `X-Cron-Secret` header** from the Scheduler jobs — see §5.

## 5. Follow-ups, each gated on evidence rather than a guess

1. **Retire the cron header.** Both jobs still carry `CRON_SECRET` as a literal.
   The backend now prefers the OIDC token and logs `cron_auth_legacy` whenever
   the header is used instead. When a real scheduled run is observed *without*
   that line, set `CRON_OIDC_AUDIENCE` and `CRON_SERVICE_ACCOUNT`, confirm again,
   then strip the header from both jobs. Order matters: prove the new path
   returns 200 before removing the old one.
2. **The default compute service account holds `roles/editor`**, which is what
   makes the header readable by anything running as it. Worth narrowing
   independently of the cron work.
3. **Deploy.** None of phase 2's backend fixes are in production yet —
   `deploy-backend.yml` has still never run. That first execution deserves to be
   its own deliberate act.
4. **Rehearse a restore.** LAUNCH.md §5.5 remains open: PITR is on and has never
   been exercised. Deletion protection reduces the chance of needing it; it does
   not make an unrehearsed backup a backup.
