#!/usr/bin/env bash
#
# Regenerate the mobile golden baseline — ON LINUX.
#
# Why not just `flutter test --update-goldens` locally? Because Flutter
# rasterizes glyphs through CoreText on macOS and FreeType on Linux: same font,
# same Skia, different pixels. CI runs on ubuntu, so a golden authored on a Mac
# fails there on every PR, forever. Linux is the SOLE authority
# (docs/design/SYSTEM.md §20).
#
# This runs the test in the same Flutter the CI runner pins, on the same OS, so
# the bytes it writes are the bytes CI will compare against.
#
#   ./tool/update_goldens.sh                 # regenerate everything
#   ./tool/update_goldens.sh tokens_color    # …only files matching a name
#
# No Docker? Run the "Goldens — regenerate" workflow from the GitHub Actions tab
# and download the `goldens` artifact instead. Same result, slower.

set -euo pipefail

# Must match .github/workflows/ci.yml (subosito/flutter-action `flutter-version`).
# If CI moves, move this in the same PR or the baseline silently rots.
FLUTTER_VERSION="3.44.9"
IMAGE="ghcr.io/cirruslabs/flutter:${FLUTTER_VERSION}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="${1:-}"

if ! docker info >/dev/null 2>&1; then
  cat >&2 <<'EOF'
✗ Docker isn't running.

  Start Docker Desktop and try again — or, if you'd rather not:
  run the "Goldens — regenerate" workflow from the GitHub Actions tab,
  download the `goldens` artifact, and unzip it over
  mobile/test/golden/goldens/.
EOF
  exit 1
fi

# cirruslabs publishes on its own schedule and LAGS behind Flutter stable — at
# the time of the 3.44.9 move the 3.44 series stopped at `.0` while 3.41 already
# went to `.9`. They lag, they do not skip, so this becomes available again on
# its own.
#
# Until it does, REFUSE rather than substitute. Falling back to a near-miss tag
# would regenerate the baseline against a different Flutter than CI compares
# with — the precise failure the FLUTTER_VERSION comment above exists to
# prevent, and it would look like success. A missing image costs one workflow
# run; a baseline written by the wrong renderer costs a day of chasing pixels.
if ! docker manifest inspect "${IMAGE}" >/dev/null 2>&1; then
  cat >&2 <<EOF
✗ No image published for Flutter ${FLUTTER_VERSION}: ${IMAGE}

  cirruslabs lags Flutter stable by a few releases. This script will start
  working again when they publish it — nothing here needs changing.

  Meanwhile, use the authoritative path (it is what CI itself runs):
    gh workflow run goldens.yml --ref \$(git rev-parse --abbrev-ref HEAD)
  then download the \`goldens\` artifact and unzip it over
  mobile/test/golden/goldens/.

  Do NOT point IMAGE at a nearby version. The bytes would not be CI's.
EOF
  exit 1
fi

echo "→ Regenerating goldens in ${IMAGE} (linux/amd64)…"
echo "  The runner is ubuntu, so these bytes are the ones CI will compare."

# --platform: on an Apple-silicon Mac, Docker would otherwise pull the arm64
# image and rasterize slightly differently from CI's x86_64 runner. Emulated and
# slower, but it produces the bytes that actually matter.
docker run --rm \
  --platform linux/amd64 \
  -v "${REPO_ROOT}:/repo" \
  -w /repo/mobile \
  -e TZ=UTC \
  "${IMAGE}" \
  bash -lc "
    set -e
    git config --global --add safe.directory /repo
    flutter pub get
    flutter test test/golden --update-goldens ${FILTER:+--plain-name '${FILTER}'}
  "

# The container's `flutter pub get` writes mobile/.dart_tool/package_config.json
# — inside the mounted repo — with CONTAINER paths (/root/.pub-cache/...). Left
# that way, `dart format` and `dart analyze` on the host then crash trying to
# read packages that don't exist here… and `dart format` reports success while
# formatting nothing. Which is exactly how unformatted files reach CI.
#
# So put the host's own package config back before returning.
echo
echo "→ Restoring the host's package config (the container's pub get overwrote it)…"
(cd "${REPO_ROOT}/mobile" && flutter pub get >/dev/null)

echo
echo "✓ Done. Review every changed PNG before committing:"
echo "    git status --short mobile/test/golden/goldens/"
echo
echo "  A wrong baseline is worse than none — every later PR is diffed against it."
