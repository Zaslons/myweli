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

# **The two ways a store build fails Google sign-in without saying so**, both
# real on 2026-08-22, both invisible to the whole test suite:
#
#   the signing key — Google matches an Android sign-in by (package, cert
#   SHA-1), and the only fingerprint registered is a development keystore. Every
#   build tested here works; the Play-signed build fails for everyone.
#
#   the audience — the backend accepts only the client ids in GOOGLE_CLIENT_IDS.
#   Giving the Pro app its own OAuth clients fixed the client side and moved the
#   rejection downstream, where it looks like the user's fault.
#
# This is the only moment both halves are visible at once: the repository knows
# which client the build will present, Secret Manager knows which the backend
# will accept. A test can see the first, a monitor the second, neither both.
echo "→ verifying $FLAVOUR/$PLATFORM can actually sign in with Google…"
node "$(dirname "$0")/../infra/mobile/96-verify-google-identity.mjs" \
  --platform "$PLATFORM" --flavour "$FLAVOUR"

cd "$(dirname "$0")/../mobile"

# **`--flavor` chooses the NATIVE config; `--target` chooses the APP.** Without
# the target, every build compiles `lib/main.dart` — so `release_build.sh <p> pro`
# produced an artifact with the Pro bundle id, the Pro icon and the Pro Firebase
# config, containing the CONSUMER app. It builds, signs, uploads and installs;
# you find out when you open it. `main.dart` mounts `AppRouter`, `main_pro.dart`
# mounts `ProRouter`, and nothing branches on the flavour at runtime, so there is
# no later chance to notice.
ENTRY="lib/main.dart"
[[ "$FLAVOUR" == pro ]] && ENTRY="lib/main_pro.dart"

# **The build number is the identity of a release here, and it was frozen at 1.**
#
# `pubspec.yaml` says `version: 1.0.0+1` and nothing overrode it, so every
# artifact this script has ever produced claimed to be build 1. Both stores
# reject a second upload with a build number already used — but the store is the
# least of it. `client-version-gate.md` establishes "build numbers, not semver"
# as the release identity, and three things already key on it: the server-side
# version floor (`GET /client-version`), the Sentry release string, and the
# staged-rollout crash-free signal. All three were wired to a constant.
#
# The commit count is monotonic on main, reproducible from a commit, and needs
# nobody to remember anything.
BUILD_NUMBER="$(git -C "$(dirname "$0")/.." rev-list --count HEAD 2>/dev/null || true)"

# Refuse rather than default, exactly as the DSN checks above do. A shallow
# clone silently returns a SMALLER count, which is the one way this could go
# backwards — and a build number that goes backwards is unrecoverable: the store
# will not accept the number again, ever.
if [[ -z "$BUILD_NUMBER" || ! "$BUILD_NUMBER" =~ ^[0-9]+$ || "$BUILD_NUMBER" -lt 1 ]]; then
  echo "::error:: could not derive a build number from the git history." >&2
  echo "          Refusing to build an artifact that would claim build 1 —" >&2
  echo "          the number both stores use to tell releases apart." >&2
  exit 1
fi
if [[ "$(git -C "$(dirname "$0")/.." rev-parse --is-shallow-repository)" != "false" ]]; then
  echo "::error:: this is a SHALLOW clone, so the commit count is short and the" >&2
  echo "          build number would go BACKWARDS. Fetch the full history:" >&2
  echo "            git fetch --unshallow" >&2
  exit 1
fi

COMMON=(
  --release
  --flavor "$FLAVOUR"
  --target "$ENTRY"
  --dart-define=USE_API_BACKEND=true
  --dart-define=API_BASE_URL=https://api.myweli.com
  --dart-define=SENTRY_DSN="$DSN"
  --dart-define=SENTRY_ENV=production
  --build-number "$BUILD_NUMBER"
  # Release builds are obfuscated (ROADMAP Part 5). Without the split debug
  # info, every Sentry stack trace is unreadable symbols — the report arrives
  # and tells you nothing, which is its own kind of blind.
  --obfuscate
  --split-debug-info=build/symbols/"$FLAVOUR"
)

if [[ "$PLATFORM" == ios ]]; then
  echo "→ flutter build ipa --flavor $FLAVOUR --target $ENTRY --build-number $BUILD_NUMBER (DSN injected, not shown)"
  flutter build ipa "${COMMON[@]}"
else
  echo "→ flutter build appbundle --flavor $FLAVOUR --target $ENTRY --build-number $BUILD_NUMBER (DSN injected, not shown)"
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
