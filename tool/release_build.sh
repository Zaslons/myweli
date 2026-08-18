#!/usr/bin/env bash
#
# Build a store artifact with the observability defines, WITHOUT anyone ever
# handling the DSN.
#
#   ./tool/release_build.sh ios consumer
#   ./tool/release_build.sh android pro
#
# ## Why this script exists rather than a documented command
#
# `mobile-store-submission.md` §5 has always carried the right command, with
# `--dart-define=SENTRY_DSN=<the myweli-app DSN>` in it. A placeholder in a
# runbook is a step that gets skipped under pressure, and the failure is silent:
# `error_reporting.dart` treats an absent DSN as "reporting off" ON PURPOSE
# (telemetry that can break the app is worse than no telemetry), so a build
# without it starts, runs, looks perfect and reports nothing. That is precisely
# the state LAUNCH.md §5.2 recorded for weeks — code complete and inert.
#
# So the DSN comes from Secret Manager at build time. Nobody copies it, nobody
# pastes it into a shell history, and a build that cannot read it FAILS here
# rather than shipping blind.
#
# The other two defines are already fatal at runtime (`build_config_guard.dart`
# refuses a release build without them). Sentry deliberately is not — so this
# script is where that gap is closed, at the only moment it can be.
set -euo pipefail

PLATFORM="${1:-}"
FLAVOUR="${2:-}"
PROJECT="${MYWELI_GCP_PROJECT:-myweli}"

case "$PLATFORM" in ios|android) ;; *)
  echo "usage: $0 <ios|android> <consumer|pro>" >&2; exit 1;; esac
case "$FLAVOUR" in consumer|pro) ;; *)
  echo "usage: $0 <ios|android> <consumer|pro>" >&2; exit 1;; esac

echo "→ reading MOBILE_SENTRY_DSN from Secret Manager (never printed)…"
DSN="$(gcloud secrets versions access latest --secret=MOBILE_SENTRY_DSN --project="$PROJECT")"
if [[ -z "$DSN" ]]; then
  echo "::error:: MOBILE_SENTRY_DSN is empty or unreadable. Refusing to build a" >&2
  echo "          release that would report nothing — see LAUNCH.md §5.2." >&2
  exit 1
fi
# Shape, not value. A DSN that is merely non-empty can still be a placeholder,
# and the whole point is that a blind build must not be possible from here.
if [[ ! "$DSN" =~ ^https://[0-9a-f]+@o[0-9]+\.ingest\.[a-z0-9.-]+\.sentry\.io/[0-9]+$ ]]; then
  echo "::error:: MOBILE_SENTRY_DSN does not look like a Sentry DSN." >&2
  exit 1
fi

# The mobile project, NOT the backend's. They are three separate projects, and
# pointing the app at the backend's would put phone crashes in the API's release
# health — where nobody would look for them.
if [[ "$DSN" == "$(gcloud secrets versions access latest --secret=SENTRY_DSN --project="$PROJECT" 2>/dev/null || true)" ]]; then
  echo "::error:: MOBILE_SENTRY_DSN is the BACKEND's DSN. The app needs its own" >&2
  echo "          project, or phone crashes land in the API's release health." >&2
  exit 1
fi

cd "$(dirname "$0")/../mobile"

COMMON=(
  --release
  --flavor "$FLAVOUR"
  --dart-define=USE_API_BACKEND=true
  --dart-define=API_BASE_URL=https://api.myweli.com
  --dart-define=SENTRY_DSN="$DSN"
  --dart-define=SENTRY_ENV=production
  # Release builds are obfuscated (ROADMAP Part 5). Without the split debug
  # info, every Sentry stack trace is unreadable symbols — the report arrives
  # and tells you nothing, which is its own kind of blind.
  --obfuscate
  --split-debug-info=build/symbols/"$FLAVOUR"
)

if [[ "$PLATFORM" == ios ]]; then
  echo "→ flutter build ipa --flavor $FLAVOUR (DSN injected, not shown)"
  flutter build ipa "${COMMON[@]}"
else
  echo "→ flutter build appbundle --flavor $FLAVOUR (DSN injected, not shown)"
  flutter build appbundle "${COMMON[@]}"
fi

cat <<'NOTE'

Symbols were written to mobile/build/symbols/<flavour>/.

**Upload them to Sentry before releasing**, or every stack trace stays
obfuscated. That step needs a Sentry auth token and is the one thing this
script deliberately does not do for you:

  sentry-cli debug-files upload --include-sources -o <org> -p myweli-app \
    mobile/build/symbols/<flavour>
NOTE
