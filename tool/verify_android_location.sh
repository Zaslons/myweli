#!/bin/bash
# The client app asks for approximate location only.
#
#   tool/verify_android_location.sh <app.apk>
#   tool/verify_android_location.sh --badging <file>
#
# The second form reads a saved `aapt2 dump badging`; the tests use it to run
# the refusal paths on every PR (backend/test/infra/android_location_test.dart).
#
# MyWeli (the client) centres a map and picks the nearest commune: approximate
# location does both, and a client app without ACCESS_FINE_LOCATION needs no
# precise-location declaration on Play (due 2027-01-27). Precise location is
# MyWeli Pro's alone, from its own manifest (A6, decision 272,
# docs/design/consumer-location.md §1, §8.3). This reads the MERGED manifest of
# the built APK, which is what Play reads: the source pin
# (mobile/test/infra/android_location_permission_test.dart) cannot see a
# plugin's manifest bring precise location back.
#
# Passes only when the badging declares ACCESS_COARSE_LOCATION and no line
# names ACCESS_FINE_LOCATION in quotes, whatever its form: `uses-permission`,
# `uses-permission-sdk-23`, with or without `maxSdkVersion`. (An implied
# feature's reason names it without quotes, and only beside a permission line,
# which is what is refused.) Exit 1 = refused; exit 2 = nothing to judge.
set -euo pipefail

usage='usage: verify_android_location.sh <app.apk> | --badging <file>'
fine='android.permission.ACCESS_FINE_LOCATION'
coarse='android.permission.ACCESS_COARSE_LOCATION'

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
    echo "verify_android_location: no aapt2 under \$ANDROID_HOME/build-tools" >&2
    exit 2
  fi
  if ! badging="$("$aapt2" dump badging "$apk")"; then
    echo "verify_android_location: aapt2 could not read $apk" >&2
    exit 2
  fi
fi

# An empty or foreign read would also name no precise location: it must be a
# badging.
if ! grep -q "^package: name='" <<<"$badging"; then
  echo "verify_android_location: not an aapt2 badging (no package line)" >&2
  exit 2
fi

precise="$(grep -F "'$fine'" <<<"$badging" || true)"
approximate="$(grep -E "^uses-permission(-sdk-23)?: name='$coarse'" <<<"$badging" || true)"

echo "The badging's location permissions:"
grep -F "_LOCATION'" <<<"$badging" || echo "  (none)"

if [[ -n "$precise" ]]; then
  echo "::error::the client APK must not ask for precise location ($fine): it needs a Play declaration, and approximate does what the client uses it for" >&2
  exit 1
fi
if [[ -z "$approximate" ]]; then
  echo "::error::the client APK must declare $coarse: without it the map, « Près de moi » and the dialog itself are gone" >&2
  exit 1
fi
echo "OK: approximate location only. The client app needs no precise-location declaration."
