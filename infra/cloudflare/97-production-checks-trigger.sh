#!/usr/bin/env bash
# The 06:00 trigger of production-checks.yml: deploy the Worker and its key
# (docs/design/infra-production-checks-on-time.md §4.3, §4.6; B19.3e).
#
# WHY. GitHub creates production-checks.yml's own 06:00 run 4 to 12 hours late
# (§2.1). The Worker « myweli-production-checks-trigger » has no address and one
# cron; each morning it dispatches the workflow on `main` as a GitHub App
# (worker/production-checks-trigger/src/index.js).
#
# RUN IT ONLY AFTER, in this order (§4.4 « The order », §9 step 4):
#   1. B19.3b — the environment rules, read back green by
#      `bash infra/ci/98-verify-deploy-fence.sh`. This script runs it first and
#      stops on red: without the fence the App's key could start a deploy;
#   2. B19.3c — the owner creates the App (Actions: Read and write, nothing
#      else; no webhook; installed on Zaslons/myweli only), downloads its key,
#      converts it ONCE on their machine and stores it:
#        openssl pkcs8 -topk8 -nocrypt -in <downloaded>.pem -out <converted>.pem
#        gcloud secrets create GITHUB_APP_PRODUCTION_CHECKS_KEY --project myweli \
#          --replication-policy=automatic --data-file=<converted>.pem
#      then deletes both .pem files. The key never goes in chat, in the
#      repository, or in an attachment;
#   3. B19.3d — the IDs PR has set GITHUB_APP_CLIENT_ID and
#      GITHUB_APP_INSTALLATION_ID in the Worker's wrangler.toml.
#
# THE TOKEN. The front door's scoped token (CLOUDFLARE_FRONT_DOOR_TOKEN in Secret
# Manager, 96-api-front-door.sh) holds Account → Workers Scripts: Edit, which is
# what `wrangler deploy` and `secret put` need here. Read into the environment,
# never printed, never on a command line.
#
# THE KEY never lands in a variable or a file: it is checked through a pipe
# (its first line only) and piped into `wrangler secret put` over stdin.
#
# EVERY STEP READS ITS WORK BACK: the secret's name among the Worker's secrets,
# the cron « 0 6 * * * », and no workers.dev address.
#
#   bash infra/cloudflare/97-production-checks-trigger.sh
#
# WHAT IT NEEDS: gcloud (logged in as the owner), gh (for the fence read), jq,
# curl, node/npx.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRANGLER="npx --yes wrangler@4"

PROJECT=myweli
WORKER_NAME=myweli-production-checks-trigger
WORKER_DIR="$HERE/worker/production-checks-trigger"
KEY_SECRET=GITHUB_APP_PRODUCTION_CHECKS_KEY
CRON='0 6 * * *'
CF_API=https://api.cloudflare.com/client/v4

for tool in gcloud gh jq curl npx; do
  command -v "$tool" >/dev/null || { echo "::error:: $tool is required"; exit 1; }
done
[[ -f "$WORKER_DIR/wrangler.toml" ]] ||
  { echo "::error:: $WORKER_DIR/wrangler.toml not found — run from the repo checkout"; exit 1; }

echo "==> 1/4  The fence, first"
bash "$HERE/../ci/98-verify-deploy-fence.sh" ||
  { echo "::error:: the deploy fence is not in place — the App's key could start a deploy. Not deploying (spec §4.4)."; exit 1; }

echo "==> 2/4  The IDs and the key"
# Read from the toml the Worker will run with, not from a copy here.
toml_var() { sed -n "s/^$1 = \"\\(.*\\)\"\$/\\1/p" "$WORKER_DIR/wrangler.toml"; }
CLIENT_ID=$(toml_var GITHUB_APP_CLIENT_ID)
INSTALLATION_ID=$(toml_var GITHUB_APP_INSTALLATION_ID)
[[ -n "$CLIENT_ID" && -n "$INSTALLATION_ID" ]] ||
  { echo "::error:: GITHUB_APP_CLIENT_ID or GITHUB_APP_INSTALLATION_ID is empty in wrangler.toml — the IDs PR (B19.3d) comes first"; exit 1; }
echo "    ✓ client ID $CLIENT_ID, installation $INSTALLATION_ID (not secrets)"

# The first line only, through a pipe: the key itself is never held here.
# `sed -n 1p`, not `head -n 1`: head closes the pipe early, and under
# pipefail gcloud's SIGPIPE would read as « cannot read ».
KEY_HEAD=$(gcloud secrets versions access latest --secret="$KEY_SECRET" --project="$PROJECT" | sed -n 1p) ||
  { echo "::error:: cannot read $KEY_SECRET from Secret Manager — create it as the header says"; exit 1; }
# The PEM armour is built from a label, so that no line of this file has the
# shape of a key: gitleaks' private-key rule scans every commit of every branch,
# and two literal armour lines in a row read to it as a key.
LABEL='PRIVATE KEY'
case "$KEY_HEAD" in
  "-----BEGIN $LABEL-----") echo "    ✓ $KEY_SECRET is a PKCS#8 key (value not shown)" ;;
  "-----BEGIN RSA $LABEL-----")
    echo "::error:: $KEY_SECRET is PKCS#1, as GitHub downloads it. Convert it once (openssl pkcs8 -topk8 -nocrypt, header), add the result as a new version, then re-run."
    exit 1
    ;;
  *) echo "::error:: $KEY_SECRET does not start like a PEM private key"; exit 1 ;;
esac

echo "==> 3/4  Deploy, then the key"
CLOUDFLARE_API_TOKEN=$(gcloud secrets versions access latest \
  --secret=CLOUDFLARE_FRONT_DOOR_TOKEN --project="$PROJECT") ||
  { echo "::error:: cannot read CLOUDFLARE_FRONT_DOOR_TOKEN from Secret Manager (96-api-front-door.sh)"; exit 1; }
export CLOUDFLARE_API_TOKEN
[[ -n "$CLOUDFLARE_API_TOKEN" ]] || { echo "::error:: CLOUDFLARE_FRONT_DOOR_TOKEN is empty"; exit 1; }
if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  CLOUDFLARE_ACCOUNT_ID=$(gcloud secrets versions access latest \
    --secret=R2_ACCOUNT_ID --project="$PROJECT" 2>/dev/null || true)
fi
[[ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]] ||
  { echo "::error:: no Cloudflare account ID: export CLOUDFLARE_ACCOUNT_ID or keep R2_ACCOUNT_ID in Secret Manager"; exit 1; }
export CLOUDFLARE_ACCOUNT_ID

(cd "$WORKER_DIR" && $WRANGLER deploy)
gcloud secrets versions access latest --secret="$KEY_SECRET" --project="$PROJECT" |
  (cd "$WORKER_DIR" && $WRANGLER secret put GITHUB_APP_KEY)

echo "==> 4/4  Read back"
if ! (cd "$WORKER_DIR" && $WRANGLER secret list 2>&1) | grep -q 'GITHUB_APP_KEY'; then
  echo "::error:: GITHUB_APP_KEY is not among the Worker's secrets after 'secret put'"
  exit 1
fi
echo "    ✓ secret GITHUB_APP_KEY is bound (names only are listed)"

# The bearer header in a 0600 scratch file, so the token is on no command line.
AUTH_HEADER_FILE=$(mktemp)
trap 'rm -f "$AUTH_HEADER_FILE"' EXIT
chmod 600 "$AUTH_HEADER_FILE"
printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_API_TOKEN" >"$AUTH_HEADER_FILE"
cf_get() { curl -sS "$CF_API$1" -H "@$AUTH_HEADER_FILE"; }

SCRIPT_PATH="/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/$WORKER_NAME"
CRONS=$(cf_get "$SCRIPT_PATH/schedules" | jq -c '[.result.schedules[]?.cron]')
if [[ "$CRONS" == "[\"$CRON\"]" ]]; then
  echo "    ✓ one cron, $CRON (UTC)"
else
  echo "::error:: the Worker's crons are $CRONS, expected [\"$CRON\"]"
  exit 1
fi
SUBDOMAIN=$(cf_get "$SCRIPT_PATH/subdomain" | jq -r '.result.enabled')
if [[ "$SUBDOMAIN" == "false" ]]; then
  echo "    ✓ no workers.dev address: nothing on the internet can call it"
else
  echo "::error:: the Worker's workers.dev address is enabled ($SUBDOMAIN) — workers_dev = false did not take"
  exit 1
fi

echo "==> Deployed. Next morning, read: the run created at about 06:00 by the App,"
echo "    and Cloudflare's « Trigger Events » for the event and its CPU time (spec §4.9)."
