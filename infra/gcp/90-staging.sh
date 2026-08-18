#!/usr/bin/env bash
# Staging on Google Cloud — the database, the runtime identity, the secrets, the
# service, and its (paused) crons. Build-order step 4 of
# docs/design/infra-staging.md.
#
# Run ONCE, by the owner. The deploy service account deliberately cannot do any
# of this: `myweli-deployer@` holds `run.admin` and `artifactregistry.writer`
# and nothing else, so it can deploy a service it did not provision. That split
# is the design — a credential that CI holds should not be able to create
# databases or mint secrets.
#
#   gcloud auth login          # as the account owner
#   bash infra/gcp/90-staging.sh
#
# Idempotent: every step is `describe || create`, so a partial run re-runs. The
# secret VALUES are only written when the secret is new — re-running never
# rotates a live credential behind your back.
#
# PREREQUISITE: infra/cloudflare/90-staging-r2.sh has run and its bucket-scoped
# token exists. This script reads those four values from the environment and
# refuses to invent them; see the block at the top of §4.
set -euo pipefail

PROJECT=myweli
REGION=europe-west9
INSTANCE=myweli-db-staging
SERVICE=myweli-api-staging
RUN_SA="myweli-run-staging@${PROJECT}.iam.gserviceaccount.com"
DEPLOYER_SA="myweli-deployer@${PROJECT}.iam.gserviceaccount.com"
SCHEDULER_SA="myweli-scheduler@${PROJECT}.iam.gserviceaccount.com"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A long random value, base64url, no shell-hostile characters.
gen() { openssl rand -base64 48 | tr -d '\n=' | tr '+/' '-_'; }

# ---------------------------------------------------------------------------
# 1. The database
# ---------------------------------------------------------------------------
# Same tier and shape as production (db-f1-micro, ZONAL, 10 GiB PD_SSD,
# ENCRYPTED_ONLY) so the arithmetic staging rehearses is production's — see
# backend/test/infra/service_files_test.dart, which asserts each environment's
# maxScale fits its instance's connection budget.
#
# THREE DELIBERATE DIFFERENCES, all in the same direction — staging should be
# cheap and destroyable:
#   · 1 retained backup instead of 7, and NO point-in-time recovery. PITR bills
#     transaction-log storage continuously for an environment whose data is
#     synthetic and re-seedable.
#   · deletion protection OFF. Production has it on precisely so it cannot be
#     deleted by accident; staging exists to be torn down and rebuilt, and a
#     protected instance makes that a two-step irritation that gets automated
#     away badly.
#   · backups at 03:00 rather than 02:00, so the two instances do not take their
#     maintenance windows at the same moment on the same shared-core tier.
echo "==> 1/7  Cloud SQL instance ${INSTANCE}"
if gcloud sql instances describe "$INSTANCE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "    ✓ already exists"
else
  # **The edition is pinned, and that is not cosmetic.** Production is
  # ENTERPRISE; gcloud's own default is now ENTERPRISE_PLUS, which refuses
  # shared-core tiers outright:
  #
  #   Invalid Tier (db-f1-micro) for (ENTERPRISE_PLUS) Edition
  #
  # The first run of this script died exactly there. The edition had been read
  # off the live instance along with the rest of the parity — tier, disk,
  # zonality, SSL mode — and then not carried into the command. A property that
  # matters, observed and dropped. Left unpinned it would also fail differently
  # depending on WHEN the script ran, since the default is Google's to change.
  gcloud sql instances create "$INSTANCE" \
    --project="$PROJECT" \
    --database-version=POSTGRES_16 \
    --edition=ENTERPRISE \
    --tier=db-f1-micro \
    --region="$REGION" \
    --availability-type=zonal \
    --storage-size=10 \
    --storage-type=SSD \
    --storage-auto-increase \
    --backup-start-time=03:00 \
    --retained-backups-count=1 \
    --no-enable-point-in-time-recovery \
    --ssl-mode=ENCRYPTED_ONLY \
    --no-deletion-protection \
    -q
  echo "    + created (this takes several minutes)"
fi

echo "==> 2/7  Database and application user"
gcloud sql databases describe myweli --instance="$INSTANCE" --project="$PROJECT" >/dev/null 2>&1 ||
  gcloud sql databases create myweli --instance="$INSTANCE" --project="$PROJECT" -q

# The password is generated here and never printed. It goes straight into
# STAGING_DATABASE_URL below; if that secret already exists this whole branch is
# skipped, so re-running cannot desynchronise the user from the secret.
if gcloud secrets describe STAGING_DATABASE_URL --project="$PROJECT" >/dev/null 2>&1; then
  echo "    ✓ user + STAGING_DATABASE_URL already provisioned"
  DB_PASSWORD=""
else
  DB_PASSWORD="$(gen)"
  if gcloud sql users list --instance="$INSTANCE" --project="$PROJECT" \
       --format='value(name)' | grep -qx myweli_app; then
    gcloud sql users set-password myweli_app --instance="$INSTANCE" \
      --project="$PROJECT" --password="$DB_PASSWORD" -q
  else
    gcloud sql users create myweli_app --instance="$INSTANCE" \
      --project="$PROJECT" --password="$DB_PASSWORD" -q
  fi
fi

# ---------------------------------------------------------------------------
# 2. The runtime identity
# ---------------------------------------------------------------------------
# **Its own service account, not production's `myweli-run@`.** Reusing that one
# would be cheaper and would make the whole secret split cosmetic: it holds
# `secretAccessor` on every PRODUCTION secret version, so a staging manifest
# naming `DATABASE_URL` instead of `STAGING_DATABASE_URL` would simply work, and
# the isolation would rest on nobody mistyping a YAML key in a file that a push
# trigger deploys. This account is bound below to the thirteen `STAGING_*`
# secrets and the four shared ones, and to nothing else.
echo "==> 3/7  Runtime service account ${RUN_SA}"
gcloud iam service-accounts describe "$RUN_SA" --project="$PROJECT" >/dev/null 2>&1 ||
  gcloud iam service-accounts create myweli-run-staging \
    --project="$PROJECT" \
    --display-name="MyWeli backend — staging runtime" -q

# The proxy sidecar connects as this identity.
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${RUN_SA}" \
  --role=roles/cloudsql.client --condition=None -q >/dev/null

# The deployer must be allowed to RUN a service AS this account — without it,
# `run services replace` fails with a permission error naming the service
# account rather than the deployer, which reads like the wrong problem.
gcloud iam service-accounts add-iam-policy-binding "$RUN_SA" \
  --project="$PROJECT" \
  --member="serviceAccount:${DEPLOYER_SA}" \
  --role=roles/iam.serviceAccountUser -q >/dev/null

# ---------------------------------------------------------------------------
# 3. Owner-supplied values
# ---------------------------------------------------------------------------
# Read from the environment, and the run STOPS if any is missing. The
# alternative — inventing a placeholder — is how an environment ends up
# configured, green, and quietly unable to do the thing the value was for.
echo "==> 4/7  Checking owner-supplied values"
: "${STAGING_R2_BUCKET:?run infra/cloudflare/90-staging-r2.sh first, then export the four R2 values it prints}"
: "${STAGING_R2_KYC_BUCKET:?missing}"
: "${STAGING_R2_DEPOSIT_BUCKET:?missing}"
: "${STAGING_R2_PUBLIC_BASE_URL:?missing — the r2.dev URL for the staging public bucket}"
: "${STAGING_R2_ACCESS_KEY_ID:?missing — from the BUCKET-SCOPED token}"
: "${STAGING_R2_SECRET_ACCESS_KEY:?missing — from the BUCKET-SCOPED token}"
: "${STAGING_ADMIN_EMAIL:?missing — the staging super-admin login, e.g. admin@staging.myweli.test}"

# A production R2 bucket name here would silently point staging at production
# storage, which is the exact failure `r2_token_scope_test.dart` exists to catch
# on the credential side. Cheap to also refuse on the name side.
for v in "$STAGING_R2_BUCKET" "$STAGING_R2_KYC_BUCKET" "$STAGING_R2_DEPOSIT_BUCKET"; do
  case "$v" in
    *-staging) ;;
    *) echo "::error:: R2 bucket '$v' is not a *-staging bucket"; exit 1 ;;
  esac
done
echo "    ✓ all present"

# ---------------------------------------------------------------------------
# 4. Secrets
# ---------------------------------------------------------------------------
# Thirteen `STAGING_*` twins. The other four mounts in service-staging.yaml —
# SENTRY_DSN, GOOGLE_CLIENT_IDS, APPLE_CLIENT_IDS, R2_ACCOUNT_ID — are
# deliberately SHARED with production and are not created here; they need an
# accessor binding for the new identity instead (below).
echo "==> 5/7  Secrets"

put_secret() { # name value
  local name="$1" value="$2"
  if gcloud secrets describe "$name" --project="$PROJECT" >/dev/null 2>&1; then
    echo "    ✓ $name exists (value untouched)"
  else
    gcloud secrets create "$name" --project="$PROJECT" \
      --replication-policy=automatic -q
    printf '%s' "$value" |
      gcloud secrets versions add "$name" --project="$PROJECT" --data-file=- -q >/dev/null
    echo "    + $name created"
  fi
  gcloud secrets add-iam-policy-binding "$name" --project="$PROJECT" \
    --member="serviceAccount:${RUN_SA}" \
    --role=roles/secretmanager.secretAccessor -q >/dev/null
}

# DATABASE_URL points at the proxy sidecar on loopback — the connection string
# carries no information about WHICH database it reaches; that lives only in the
# two `cloudsql-instances` strings in service-staging.yaml.
if [ -n "$DB_PASSWORD" ]; then
  put_secret STAGING_DATABASE_URL \
    "postgres://myweli_app:${DB_PASSWORD}@127.0.0.1:5432/myweli"
else
  put_secret STAGING_DATABASE_URL ""   # exists; the value is left alone
fi

# Generated, never copied from production. A shared JWT_SECRET would let a token
# minted in staging — where we deliberately hand out admin credentials —
# authenticate against production.
put_secret STAGING_JWT_SECRET "$(gen)"
put_secret STAGING_MESSAGING_WEBHOOK_SECRET "$(gen)"
put_secret STAGING_ADMIN_PASSWORD "$(gen)"

# **A Resend key that cannot deliver, on purpose.** Email is a live channel
# reaching real inboxes, and §3.3's rule is that staging never has one. Sign-in
# still works: `ENV=staging` is not `isProd`, so the OTP is echoed in the
# response and nothing needs to arrive. The guard requires the variable to be
# non-empty, not to be valid.
put_secret STAGING_RESEND_API_KEY "re_staging_placeholder_delivery_is_disabled"

put_secret STAGING_ADMIN_EMAIL "$STAGING_ADMIN_EMAIL"
put_secret STAGING_R2_BUCKET "$STAGING_R2_BUCKET"
put_secret STAGING_R2_KYC_BUCKET "$STAGING_R2_KYC_BUCKET"
put_secret STAGING_R2_DEPOSIT_BUCKET "$STAGING_R2_DEPOSIT_BUCKET"
put_secret STAGING_R2_PUBLIC_BASE_URL "$STAGING_R2_PUBLIC_BASE_URL"
put_secret STAGING_R2_ACCESS_KEY_ID "$STAGING_R2_ACCESS_KEY_ID"
put_secret STAGING_R2_SECRET_ACCESS_KEY "$STAGING_R2_SECRET_ACCESS_KEY"

# The four shared ones: no new secret, only read access for the new identity.
# Each is a non-credential — a write-only Sentry DSN, two public OAuth client-id
# allowlists, and the Cloudflare account id — which is why sharing them is
# correct rather than merely convenient (service-staging.yaml states the reason
# per entry).
for name in SENTRY_DSN GOOGLE_CLIENT_IDS APPLE_CLIENT_IDS R2_ACCOUNT_ID; do
  gcloud secrets add-iam-policy-binding "$name" --project="$PROJECT" \
    --member="serviceAccount:${RUN_SA}" \
    --role=roles/secretmanager.secretAccessor -q >/dev/null
  echo "    ✓ $name shared (read access granted)"
done

# ---------------------------------------------------------------------------
# 5. The service
# ---------------------------------------------------------------------------
# Created here with a placeholder image so the URL exists for the Scheduler jobs
# and the CORS/callback values below. The real deploy is deploy-backend.yml with
# `environment: staging`, which substitutes the digest it just built.
echo "==> 6/7  Cloud Run service ${SERVICE}"
if gcloud run services describe "$SERVICE" --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "    ✓ already exists — deploy with deploy-backend.yml, not from here"
else
  # `hello` is Google's own public image. Deliberately NOT the real backend: a
  # first revision built by hand would be an artifact nobody reviewed, and the
  # point of the declarative file is that every real revision comes from CI.
  sed -e 's|__IMAGE__|gcr.io/cloudrun/hello|g' \
      -e 's|__RELEASE__|bootstrap|g' \
    "$HERE/service-staging.yaml" > /tmp/service-staging-bootstrap.yaml
  gcloud run services replace /tmp/service-staging-bootstrap.yaml \
    --region="$REGION" --project="$PROJECT" -q
  rm -f /tmp/service-staging-bootstrap.yaml
  echo "    + created with a placeholder image"
fi

# Publicly invokable. Staging has no load balancer, so its own run.app URL is
# the only door, and Vercel previews reach it from a browser.
gcloud run services add-iam-policy-binding "$SERVICE" \
  --region="$REGION" --project="$PROJECT" \
  --member=allUsers --role=roles/run.invoker -q >/dev/null

# Read back, never constructed: Cloud Run publishes two run.app hostnames for
# one service and `gcloud run services list` prints the one that is NOT
# `status.url`.
STAGING_URL=$(gcloud run services describe "$SERVICE" \
  --region="$REGION" --project="$PROJECT" --format='value(status.url)')
echo "    → ${STAGING_URL}"

# ---------------------------------------------------------------------------
# 6. Crons — created PAUSED
# ---------------------------------------------------------------------------
# `*/15` against `minScale: 0` is ~96 cold starts a day, each running migrations
# behind the advisory lock, for an environment nobody is using between
# rehearsals. They exist so the path is provable; they are resumed deliberately:
#
#   gcloud scheduler jobs resume myweli-reminders-staging --location=$REGION
#
# **OIDC only — no `X-Cron-Secret`.** Production still carries that header as a
# transitional fallback, and it is readable in plaintext by anyone with
# `cloudscheduler.jobs.get`. Staging is the environment where the OIDC path can
# be proven to carry traffic on its own, which is the evidence production needs
# before the header is retired (BACKEND.md §7 T21).
echo "==> 7/7  Cloud Scheduler jobs (created paused)"
make_job() { # name schedule path
  local name="$1" schedule="$2" path="$3"
  if gcloud scheduler jobs describe "$name" --location="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
    echo "    ✓ $name exists"
    return
  fi
  gcloud scheduler jobs create http "$name" \
    --project="$PROJECT" --location="$REGION" \
    --schedule="$schedule" --time-zone=Etc/UTC \
    --uri="${STAGING_URL}${path}" --http-method=POST \
    --oidc-service-account-email="$SCHEDULER_SA" \
    --oidc-token-audience="$STAGING_URL" -q
  # No `--paused` flag exists on create — verified against the CLI — so pausing
  # is a second call. Between the two, one tick may fire; harmless against a
  # freshly created service with no data.
  gcloud scheduler jobs pause "$name" --location="$REGION" --project="$PROJECT" -q
  echo "    + $name created and PAUSED"
}
make_job myweli-reminders-staging     '*/15 * * * *' /internal/cron/reminders
make_job myweli-subscriptions-staging '0 3 * * *'    /internal/cron/subscriptions

cat <<EOF

Staging infrastructure is up. Three things remain, in order.

1. **Finish service-staging.yaml.** Two values could not exist until now,
   because they are derived from the service's own URL:

     CRON_OIDC_AUDIENCE    ${STAGING_URL}
     WEB_ORIGINS           (unchanged for now — localhost only until step 5)

   Add the CRON_* pair to infra/gcp/service-staging.yaml, in the block that
   currently explains why they are absent, and open a PR. Without them
   \`CronAuth\` runs on the shared secret alone — the same gap production had
   until PR #369.

2. **Deploy for real**: Actions → "Deploy — backend (Cloud Run)" →
   environment \`staging\`. The verify step asserts the service reports
   \`env=staging\`, so a manifest pointed at the wrong place fails loudly.

3. **Tighten the WIF trust condition** — but only AFTER a staging deploy has
   succeeded, so the thing being narrowed is known to work first. The provider
   is pinned on \`attribute.repository\` alone, which means any workflow on any
   branch can mint a token holding project-wide \`run.admin\` — enough to
   replace PRODUCTION. \`deploy-backend.yml\` now declares \`environment:\`, so
   the OIDC token carries an environment claim a condition can match. That
   script is owed and does not exist yet; neither does \`40-iam-wif.sh\`, which
   this repo has cited since the migration and never contained.

   **Do not uncomment the \`push: main\` trigger before that lands.**
EOF
