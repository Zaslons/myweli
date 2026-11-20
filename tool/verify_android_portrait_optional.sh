#!/bin/bash
# Play's device filter: the portrait lock must not make portrait REQUIRED.
#
#   tool/verify_android_portrait_optional.sh <app.apk>
#   tool/verify_android_portrait_optional.sh --badging <file>
#
# The second form reads a saved `aapt2 dump badging`; the tests use it to run
# the refusal paths on every PR (backend/test/infra/
# android_portrait_optional_test.dart).
#
# MainActivity is locked to portrait (docs/design/pro-app-batch7.md §2.9).
# From that lock alone, Play infers a required android.hardware.screen.portrait
# and hides the app from every device that does not report the feature:
# 27 devices at build 785, and the closed track's check named phones, tablets,
# desktop and Android XR (docs/design/android-play-release.md §11, 2026-11-19).
# The manifest declares the feature optional. This reads the MERGED manifest of
# the built APK, which is what Play reads: the source pin
# (mobile/test/infra/android_orientation_test.dart) cannot see a plugin's
# manifest bring the requirement back.
#
# Passes only when the badging names the feature exactly once, as
# `uses-feature-not-required`. Exit 1 = refused; exit 2 = nothing to judge.
set -euo pipefail

usage='usage: verify_android_portrait_optional.sh <app.apk> | --badging <file>'
feature='android.hardware.screen.portrait'

if [[ "${1:-}" == "--badging" ]]; then
  badging="$(cat "${2:?$usage}")"
else
  apk="${1:?$usage}"
  sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  aapt2=""
  if [[ -n "$sdk" ]]; then
    aapt2="$(ls -d "$sdk"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1 || true)"
  fi
  if [[ -z "$aapt2" || ! -x "$aapt2" ]]; then
    echo "verify_android_portrait_optional: no aapt2 under \$ANDROID_HOME/build-tools" >&2
    exit 2
  fi
  if ! badging="$("$aapt2" dump badging "$apk")"; then
    echo "verify_android_portrait_optional: aapt2 could not read $apk" >&2
    exit 2
  fi
fi

# An empty or foreign read would also name no requirement: it must be a badging.
if ! grep -q "^package: name='" <<<"$badging"; then
  echo "verify_android_portrait_optional: not an aapt2 badging (no package line)" >&2
  exit 2
fi

# aapt2 prints features inside `feature-group: label=''`, indented by two
# spaces; the indent is layout, not meaning.
found="$(grep -F "name='$feature'" <<<"$badging" | sed 's/^[[:space:]]*//' || true)"
expected="uses-feature-not-required: name='$feature'"

echo "The badging's lines for $feature:"
echo "${found:-  (none)}"
if [[ "$found" != "$expected" ]]; then
  echo "::error::the APK must declare $feature optional, and only that (expected « $expected »)" >&2
  exit 1
fi
echo "OK: optional. Play infers no requirement from the portrait lock."
