#!/usr/bin/env bash
#
# Build a store artifact with the observability defines and the basemap key,
# WITHOUT anyone ever handling the DSN or the key.
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
#
# The CARTO basemap key (`CARTO_BASEMAPS_KEY`, the APP key) is the same gap
# again: without it nothing fails, every map just shows « API KEY REQUIRED ».
# Read from Secret Manager the same way, refused when empty, blank-bearing or
# not shaped like a key, and never printed (docs/design/map-basemap-key.md §5.4).
set -euo pipefail

PLATFORM="${1:-}"
FLAVOUR="${2:-}"
PROJECT="${MYWELI_GCP_PROJECT:-myweli}"

case "$PLATFORM" in ios|android) ;; *)
  echo "usage: $0 <ios|android> <consumer|pro>" >&2; exit 1;; esac
case "$FLAVOUR" in consumer|pro) ;; *)
  echo "usage: $0 <ios|android> <consumer|pro>" >&2; exit 1;; esac

# **Only a reviewed commit becomes a store build** (docs/design/hygiene-batch9.md
# §2.2, B9.2). Checked FIRST, before a secret is read: a binary sent to Apple
# from a branch nobody reviewed, or from a tree with a stray edit in it, is the
# one release no later step can tell apart from a real one — the build number
# is a commit count, and an unreviewed commit counts the same. The runbook said
# `git checkout main && git pull && git status` (app-store-forms.md §11.2); a
# runbook line is a step that gets skipped, so the script refuses instead.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "$(git -C "$REPO" status --porcelain --untracked-files=normal)" ]]; then
  echo "::error:: the working tree is not clean. A store build is a commit, not" >&2
  echo "          a commit plus whatever is lying around:" >&2
  git -C "$REPO" status --short >&2
  exit 1
fi
if ! git -C "$REPO" fetch --quiet origin main; then
  echo "::error:: could not fetch origin/main — refusing to guess what it is." >&2
  exit 1
fi
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
MAIN_SHA="$(git -C "$REPO" rev-parse origin/main)"
if [[ "$HEAD_SHA" != "$MAIN_SHA" ]]; then
  echo "::error:: HEAD is $HEAD_SHA, origin/main is $MAIN_SHA. A store build is" >&2
  echo "          built from origin/main only:" >&2
  echo "            git checkout main && git pull --ff-only" >&2
  exit 1
fi

# **An iOS IPA is validated before anything prints how to upload it**, and the
# validation needs the App Store Connect API key (app-store-forms.md §11.4).
# Asked for now rather than after a ten-minute build: build 587's separate
# validation step never ran (§11.5) — a broken command chain, unnoticed.
if [[ "$PLATFORM" == ios ]]; then
  if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
    echo "::error:: set ASC_KEY_ID and ASC_ISSUER_ID (the App Store Connect API key," >&2
    echo "          app-store-forms.md §11.4): the IPA is validated before the" >&2
    echo "          upload command is printed." >&2
    exit 1
  fi
fi

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

# **The basemap key, read the same way and refused the same way.** Since
# 2026-09-25 CARTO serves no raster tile without a usable key: every map in a
# keyless build shows « API KEY REQUIRED » instead of streets — which is
# exactly what builds up to 555 ship. `AppConfig.cartoBasemapsKey` defaults to
# empty so debug runs and CI show that watermark on purpose; a STORE build
# without the key would be the defect again, so it cannot be made from here.
# It is the APP key (restricted to our bundle ids / packages) — the web has its
# own. Public once shipped (it is in the binary); kept out of git and shell
# history all the same. docs/design/map-basemap-key.md §9.
echo "→ reading CARTO_BASEMAPS_KEY from Secret Manager (never printed)…"
CARTO_KEY="$(gcloud secrets versions access latest --secret=CARTO_BASEMAPS_KEY --project="$PROJECT")"
if [[ -z "$CARTO_KEY" ]]; then
  echo "::error:: CARTO_BASEMAPS_KEY is empty or unreadable. Refusing to build a" >&2
  echo "          release whose maps would show « API KEY REQUIRED »." >&2
  exit 1
fi
if [[ "$CARTO_KEY" =~ [[:space:]] ]]; then
  echo "::error:: CARTO_BASEMAPS_KEY contains whitespace — a paste went wrong." >&2
  exit 1
fi
# Shape, not value — as for the DSN. Non-empty and blank-free still lets a
# placeholder through (`TODO`, a truncated paste), and CARTO answers a key it
# does not know with the watermark, exactly as if there were none. A CARTO key
# is letters, digits, `_` and `-`, and long; the message never echoes it.
if [[ ! "$CARTO_KEY" =~ ^[A-Za-z0-9_-]{20,}$ ]]; then
  echo "::error:: CARTO_BASEMAPS_KEY does not look like a CARTO key (letters," >&2
  echo "          digits, _ or -, at least 20 of them). Value not shown." >&2
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
# `pubspec.yaml`'s build number is `+1` and nothing overrode it, so every
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
  --dart-define=CARTO_BASEMAPS_KEY="$CARTO_KEY"
  --build-number "$BUILD_NUMBER"
  # Release builds are obfuscated (ROADMAP Part 5). Without the split debug
  # info, every Sentry stack trace is unreadable symbols — the report arrives
  # and tells you nothing, which is its own kind of blind.
  --obfuscate
  --split-debug-info=build/symbols/"$FLAVOUR"
)

if [[ "$PLATFORM" == ios ]]; then
  echo "→ flutter build ipa --flavor $FLAVOUR --target $ENTRY --build-number $BUILD_NUMBER (DSN + basemap key injected, not shown)"
  # Everything this run exports is newer than this marker (see below).
  BUILD_MARK="$(mktemp)"
  flutter build ipa "${COMMON[@]}"
  # **Park the IPA under the flavour's own name.** `flutter build ipa` exported
  # every flavour to the same build/ios/ipa/MyWeli.ipa — measured
  # 2026-08-29, when `ios pro` silently overwrote the consumer IPA and only a
  # bytes-level entitlement check caught it. Android never had this problem
  # (bundle paths are flavour-specific); iOS now matches. Refuse loudly if
  # the expected file is absent rather than "succeeding" with nothing.
  #
  # **Find the IPA by recency, not by name.** Xcode names the export after
  # CFBundleName, which is per flavour since the App Store audit (#550):
  # « MyWeli Pro.ipa » for pro, « MyWeli.ipa » for consumer. The fixed name
  # this used to expect refused a good pro build on 2026-10-07 (build 551).
  # Exactly one IPA newer than the marker, and not an already-parked
  # MyWeli-<flavour>.ipa, or nothing moves.
  IPA_DIR="build/ios/ipa"
  FRESH=()
  while IFS= read -r -d '' f; do
    FRESH+=("$f")
  done < <(find "$IPA_DIR" -maxdepth 1 -name '*.ipa' ! -name 'MyWeli-*.ipa' -newer "$BUILD_MARK" -print0 2>/dev/null)
  rm -f "$BUILD_MARK"
  if [[ ${#FRESH[@]} -ne 1 ]]; then
    echo "::error:: expected exactly one IPA exported by this build in $IPA_DIR — found ${#FRESH[@]}." >&2
    exit 1
  fi
  mv "${FRESH[0]}" "$IPA_DIR/MyWeli-$FLAVOUR.ipa"
  [[ -f "$IPA_DIR/DistributionSummary.plist" ]] && \
    mv "$IPA_DIR/DistributionSummary.plist" "$IPA_DIR/DistributionSummary-$FLAVOUR.plist"
  echo "→ IPA: mobile/$IPA_DIR/MyWeli-$FLAVOUR.ipa"

  # **Park the archive under its flavour AND build** (B9.2), like the IPA.
  # `flutter build ipa` writes build/ios/archive/Runner.xcarchive for every
  # flavour, so the next build overwrote it — and the archive holds the dSYMs
  # Sentry needs to read a native crash. It was copied by hand (§11.2).
  ARCHIVE_DIR="build/ios/archive"
  if [[ ! -d "$ARCHIVE_DIR/Runner.xcarchive" ]]; then
    echo "::error:: this build left no $ARCHIVE_DIR/Runner.xcarchive — nothing to keep." >&2
    exit 1
  fi
  ARCHIVE="$ARCHIVE_DIR/Runner-$FLAVOUR-$BUILD_NUMBER.xcarchive"
  rm -rf "$ARCHIVE"
  mv "$ARCHIVE_DIR/Runner.xcarchive" "$ARCHIVE"
  echo "→ archive: mobile/$ARCHIVE"

  # **Validate before anything says « upload »** (B9.2). A refusal here stops
  # everything: no upload command, no symbol command — an IPA Apple will not
  # take is not a release.
  echo "→ xcrun altool --validate-app mobile/$IPA_DIR/MyWeli-$FLAVOUR.ipa"
  if ! xcrun altool --validate-app "$IPA_DIR/MyWeli-$FLAVOUR.ipa" \
      --api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID"; then
    echo "::error:: App Store Connect refused the IPA (above). Not printing the" >&2
    echo "          upload command: fix the build, then run this again." >&2
    exit 1
  fi
else
  echo "→ flutter build appbundle --flavor $FLAVOUR --target $ENTRY --build-number $BUILD_NUMBER (DSN + basemap key injected, not shown)"
  flutter build appbundle "${COMMON[@]}"
fi

# **What is left for the operator**, for THIS build — its symbols, its release,
# its commits. Printed, not run: they need the Sentry token, which this script
# deliberately never holds.
BUNDLE="com.myweli.app"
[[ "$FLAVOUR" == pro ]] && BUNDLE="com.myweli.pro"
VERSION="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' pubspec.yaml)"
# The release the app reports: SentryFlutter's `package@version+build`
# (error_reporting.dart — `release` is deliberately not set by hand).
RELEASE="$BUNDLE@$VERSION+$BUILD_NUMBER"
SYMBOLS="mobile/build/symbols/$FLAVOUR"
# The archive's dSYMs: without them a NATIVE crash (a plugin, the engine) stays
# unreadable — the Dart symbols cover only Dart frames (B9.2).
[[ "$PLATFORM" == ios ]] && SYMBOLS="$SYMBOLS mobile/$ARCHIVE/dSYMs"

cat <<NOTE

This build's symbols: $SYMBOLS.

**Upload them to Sentry before releasing**, or every stack trace stays
obfuscated. That step needs a Sentry auth token and is the one thing this
script deliberately does not do for you — token from Secret Manager, never
pasted; no --url needed (the org token embeds its own API address, measured —
the CLI ignores a manual one with a warning). From the repository root:

  export SENTRY_AUTH_TOKEN="\$(gcloud secrets versions access latest \\
      --secret=SENTRY_AUTH_TOKEN --project=myweli)"
  sentry-cli debug-files upload --include-sources -o myweli -p myweli-app \\
      $SYMBOLS

Verify against the SERVER, not the upload log:
GET /api/0/projects/myweli/myweli-app/files/dsyms/ must list the new debug
IDs. Uploads are debug-ID-matched and release-independent — re-uploading is a
no-op.

**Name the commits this release carries**, so a new issue in it shows its
suspect commits (B9.4) — the release is the app's own, $RELEASE:

  sentry-cli releases -o myweli -p myweli-app new "$RELEASE"
  sentry-cli releases -o myweli set-commits "$RELEASE" \\
      --commit "Zaslons/myweli@$HEAD_SHA"
NOTE

if [[ "$PLATFORM" == ios ]]; then
  cat <<UPLOAD

**Validated by App Store Connect.** Upload it (app-store-forms.md §11.5):

  xcrun altool --upload-package mobile/build/ios/ipa/MyWeli-$FLAVOUR.ipa \\
      --api-key "\$ASC_KEY_ID" --api-issuer "\$ASC_ISSUER_ID" --wait --show-progress
UPLOAD
fi
