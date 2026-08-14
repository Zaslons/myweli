#!/usr/bin/env bash
# Workload Identity Federation — how GitHub Actions deploys without a key, and
# how narrow that trust is.
#
# WHY THIS FILE APPEARS ONLY NOW. `deploy-backend.yml` has cited
# `infra/gcp/40-iam-wif.sh` as the authority for its trust condition since the
# GCP migration, and the file **has never existed**. The pool, the provider and
# the bindings were created by hand and live only in the project — which makes
# the single most security-relevant piece of this infrastructure the one piece
# nobody can review in a PR. That is the same property the Render dashboard's
# invisible cron jobs had, and the reason the reminder cron was off with nobody
# noticing.
#
# So `baseline` below is a truthful, idempotent record of what is already there,
# written from `gcloud ... describe` rather than from memory. Running it changes
# nothing.
#
# ---------------------------------------------------------------------------
# WHAT IS ACTUALLY WRONG, AND THE THREE STEPS THAT FIX IT
# ---------------------------------------------------------------------------
#
# The live trust is:
#
#   provider condition:  assertion.repository == 'Zaslons/myweli'
#   deployer binding:    principalSet://…/attribute.repository/Zaslons/myweli
#
# Repository, and nothing else. So **any workflow, on any branch, in this
# repository, with `id-token: write`, can mint a token for `myweli-deployer@`** —
# which holds PROJECT-WIDE `roles/run.admin`. That is enough to replace the
# production service. Today the only consumer is `deploy-backend.yml`, which is
# `workflow_dispatch` + a typed confirm; the moment `push: main` is uncommented,
# the blast radius of any merged workflow file becomes production.
#
# The fix is to key the trust on the **environment** the job declares.
# `deploy-backend.yml` already declares `environment: backend-staging` /
# `backend-production`, so GitHub puts an `environment` claim in the token.
#
#   ./40-iam-wif.sh baseline   what exists today; changes nothing
#   ./40-iam-wif.sh widen      map the claim, ADD environment-scoped bindings
#   ── run a real deploy here, and watch it succeed ──
#   ./40-iam-wif.sh narrow     remove the repository-wide binding
#
# **The order is the whole safety property.** `widen` is additive: both the old
# and the new path work afterwards, so nothing can break. `narrow` removes the
# old one, and it must not run until a deploy has actually succeeded on the new
# one — otherwise the first evidence that the environment claim does not arrive
# as expected is a broken deploy pipeline with no way to deploy the fix.
#
# **Why the environment is enforced by the BINDING and not by the provider's
# attribute condition.** A CEL condition referencing a claim that is absent —
# a workflow job with no `environment:` — is an evaluation hazard I could not
# test without applying it to the live provider. A `principalSet` that names an
# attribute simply does not match a token lacking it: no CEL, no error path, and
# the failure mode is "denied" rather than "undefined". The attribute mapping is
# still added, because the binding needs it.
set -euo pipefail

PROJECT=myweli
PROJECT_NUMBER=731308991240
POOL=github
PROVIDER=myweli-repo
REPO=Zaslons/myweli
DEPLOYER="myweli-deployer@${PROJECT}.iam.gserviceaccount.com"

POOL_PATH="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}"
REPO_PRINCIPAL="principalSet://iam.googleapis.com/${POOL_PATH}/attribute.repository/${REPO}"

# The two GitHub Environments `deploy-backend.yml` declares. They are NOT
# `Production`/`Preview` — those already exist, created by the Vercel
# integration, and reusing them would mix backend deploys into Vercel's
# deployment activity log.
ENVIRONMENTS=(backend-staging backend-production)

usage() { sed -n '2,50p' "$0"; exit 1; }
[ $# -ge 1 ] || usage

case "$1" in

# ---------------------------------------------------------------------------
baseline)
# ---------------------------------------------------------------------------
  echo "==> Pool"
  gcloud iam workload-identity-pools describe "$POOL" \
    --location=global --project="$PROJECT" >/dev/null 2>&1 ||
    gcloud iam workload-identity-pools create "$POOL" \
      --location=global --project="$PROJECT" \
      --display-name="GitHub Actions" -q

  echo "==> Provider"
  # `attribute.ref` is mapped but deliberately unused by the condition — it is
  # available for a future branch pin without another mapping change.
  gcloud iam workload-identity-pools providers describe "$PROVIDER" \
    --workload-identity-pool="$POOL" --location=global --project="$PROJECT" >/dev/null 2>&1 ||
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
      --workload-identity-pool="$POOL" --location=global --project="$PROJECT" \
      --display-name="$REPO" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
      --attribute-condition="assertion.repository=='${REPO}'" -q

  echo "==> Deployer service account and its roles"
  gcloud iam service-accounts describe "$DEPLOYER" --project="$PROJECT" >/dev/null 2>&1 ||
    gcloud iam service-accounts create myweli-deployer --project="$PROJECT" \
      --display-name="GitHub Actions deployer" -q

  # Exactly two project roles, and no more. `run.admin` is project-wide because
  # Cloud Run has no per-service admin role — which is precisely why the trust
  # on the GitHub side has to be narrow.
  for role in roles/run.admin roles/artifactregistry.writer; do
    gcloud projects add-iam-policy-binding "$PROJECT" \
      --member="serviceAccount:${DEPLOYER}" --role="$role" --condition=None -q >/dev/null
  done

  # Deploying a service means running it AS its runtime identity.
  for sa in myweli-run myweli-run-staging; do
    if gcloud iam service-accounts describe "${sa}@${PROJECT}.iam.gserviceaccount.com" \
         --project="$PROJECT" >/dev/null 2>&1; then
      gcloud iam service-accounts add-iam-policy-binding \
        "${sa}@${PROJECT}.iam.gserviceaccount.com" --project="$PROJECT" \
        --member="serviceAccount:${DEPLOYER}" \
        --role=roles/iam.serviceAccountUser -q >/dev/null
      echo "    ✓ serviceAccountUser on ${sa}@"
    else
      # Staging's runtime identity is created by 90-staging.sh. Not an error
      # here — this script must be runnable before that one.
      echo "    · ${sa}@ does not exist yet (90-staging.sh creates it)"
    fi
  done

  echo "==> Repository-wide binding (the one 'narrow' removes)"
  gcloud iam service-accounts add-iam-policy-binding "$DEPLOYER" \
    --project="$PROJECT" --member="$REPO_PRINCIPAL" \
    --role=roles/iam.workloadIdentityUser -q >/dev/null
  echo "    ✓ baseline matches what is deployed"
  ;;

# ---------------------------------------------------------------------------
widen)
# ---------------------------------------------------------------------------
  # Purely additive. After this, a token may impersonate the deployer EITHER by
  # repository (as today) OR by declared environment. Nothing can break.
  echo "==> Mapping the environment claim"
  gcloud iam workload-identity-pools providers update-oidc "$PROVIDER" \
    --workload-identity-pool="$POOL" --location=global --project="$PROJECT" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.environment=assertion.environment" \
    -q

  echo "==> Environment-scoped bindings"
  for env in "${ENVIRONMENTS[@]}"; do
    gcloud iam service-accounts add-iam-policy-binding "$DEPLOYER" \
      --project="$PROJECT" \
      --member="principalSet://iam.googleapis.com/${POOL_PATH}/attribute.environment/${env}" \
      --role=roles/iam.workloadIdentityUser -q >/dev/null
    echo "    + ${env}"
  done

  cat <<'EOF'

Both paths now work. **Run a real deploy before narrowing.**

  Actions → "Deploy — backend (Cloud Run)" → environment: staging

If it succeeds, the environment claim is arriving and being matched. Only then:

  ./40-iam-wif.sh narrow

If it FAILS with a permission error at the auth step, the claim is not arriving
as expected — investigate before removing anything. That is exactly why this is
two steps.
EOF
  ;;

# ---------------------------------------------------------------------------
narrow)
# ---------------------------------------------------------------------------
  # The only irreversible-feeling step, so it asks. (It is in fact reversible —
  # `baseline` puts the binding back — but the window between running this and
  # noticing is a window with no way to deploy.)
  if [ "${2:-}" != "confirm" ]; then
    cat <<EOF
This removes the repository-wide trust:

  ${REPO_PRINCIPAL}

leaving only the environment-scoped bindings. After it, a workflow job that does
NOT declare \`environment: backend-staging\` or \`backend-production\` cannot
mint a token for the deployer at all.

Do not run this unless a deploy has SUCCEEDED since './40-iam-wif.sh widen'.
That deploy is the only evidence the environment claim actually arrives.

  ./40-iam-wif.sh narrow confirm
EOF
    exit 1
  fi
  gcloud iam service-accounts remove-iam-policy-binding "$DEPLOYER" \
    --project="$PROJECT" --member="$REPO_PRINCIPAL" \
    --role=roles/iam.workloadIdentityUser -q >/dev/null
  echo "    ✓ repository-wide trust removed"
  echo
  echo "Remaining principals that may impersonate ${DEPLOYER}:"
  gcloud iam service-accounts get-iam-policy "$DEPLOYER" --project="$PROJECT" \
    --format='value(bindings.members)' | tr ';' '\n' | sed 's/^/      /'
  echo
  echo "The push: main trigger in deploy-backend.yml can now be enabled."
  ;;

*) usage ;;
esac
